module Git = Current_git
module Docker = Current_docker.Default

let () = Logging.init ()
let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) ()

module Commit_sequence = struct
  module Key = struct
    type t = Current_git.Commit.t list

    let digest v =
      List.map Current_git.Commit.hash v
      |> String.concat ";"
      |> Digest.string
      |> Digest.to_hex
  end

  type state = {
    mutable digest : string;
    mutable index : int;
    mutable max : int;
  }

  let empty digest = { digest; index = 0; max = 0 }

  let update_to state digest max =
    state.digest <- digest;
    state.max <- max;
    state.index <- 0

  let next ~job state values =
    let digest = Key.digest values in
    if digest <> state.digest then update_to state digest (List.length values);
    let return_value = List.nth values state.index in
    Current.Job.log job "Commit #%d/%d: %a" (state.index + 1) state.max
      Git.Commit.pp return_value;
    if state.index + 1 < state.max then state.index <- state.index + 1
    else state.index <- 0;
    return_value

  module Op = struct
    let id = "commit-sequence"

    type t = state

    module Key = Key
    module Value = Current_git.Commit

    let auto_cancel = false
    let pp f _ = Fmt.string f "commit sequence"

    let build state job commits =
      let open Lwt.Syntax in
      let* () = Current.Job.start ~level:Harmless job in
      Lwt.return_ok (next ~job state commits)
  end

  module Seq = Current_cache.Make (Op)

  let _v commits =
    let state = empty "" in
    let open Current.Syntax in
    Current.component "Cycle commits"
    |> let> commits = commits in
       Seq.get state commits
end

let program_name = "tezos-ci"

let commit hash =
  Current_git.Commit_id.v ~repo:"https://gitlab.com/tezos/tezos" ~gref:"master"
    ~hash

(* https://gitlab.com/tezos/tezos/-/merge_requests/2970/commits *)
let commits =
  [
    commit "faf7d9a7947fd796c0c9ed59097524c5452533dd";
    commit "1ce49351fe8c9a89d89660d0df89f0446bd252e8";
    commit "6b5b3ce62551cf2ca16e3fef8a175e25f9211319";
    commit "d733352620da926021b1872f355fa2510c859c65";
  ]

let ppl ~index ~ocluster commit =
  let builder =
    match ocluster with
    | None -> Lib.Builder.make_docker
    | Some ocluster -> Lib.Builder.make_ocluster `Docker ocluster
  in
  let task =
    Pipeline.v
      (Merge_request { from_branch = "master"; to_branch = "master" })
      (Current.return commit)
    |> Pipeline.pipeline ~builder
  in
  Current.all
    [
      task.current;
      Website.Index.update_state index
        ~id:(Current.return ("commit:" ^ Current_git.Commit_id.hash commit))
        task.subtasks_status;
    ]

let ppl_master ~index ~ocluster =
  let repo_tezos_master =
    Git.clone ~schedule:monthly ~gref:"master" "https://gitlab.com/tezos/tezos"
  in
  let builder =
    match ocluster with
    | None -> Lib.Builder.make_docker
    | Some ocluster -> Lib.Builder.make_ocluster `Docker ocluster
  in
  let task =
    Pipeline.v
      (Merge_request { from_branch = "master"; to_branch = "master" })
      (repo_tezos_master |> Current.map Git.Commit.id)
    |> Pipeline.pipeline ~builder
  in
  Current.all
    [
      task.current;
      Website.Index.update_state index
        ~id:(Current.return "branch:master")
        task.subtasks_status;
    ]

let pipeline ~index ocluster _filter =
  ppl_master ~index ~ocluster :: (commits |> List.map (ppl ~index ~ocluster))
  |> Current.all

let main current_config mode (`Ocluster_cap cap) (`Filter filter) =
  let ocluster =
    Option.map
      (fun cap ->
        let vat = Capnp_rpc_unix.client_only_vat () in
        let submission_cap = Capnp_rpc_unix.Vat.import_exn vat cap in
        let connection =
          Current_ocluster.Connection.create ~max_pipeline:20 submission_cap
        in
        Current_ocluster.v connection)
      cap
  in
  let index = Website.Index.make () in
  let engine =
    Current.Engine.create ~config:current_config (fun () ->
        pipeline ~index ocluster filter)
  in
  let site =
    let routes = Website.Index.routes index @ Current_web.routes engine in
    Current_web.Site.(v ~has_role:allow_all) ~name:program_name routes
  in
  Logging.run
    (Lwt.choose
       [
         Current.Engine.thread engine;
         (* The main thread evaluating the pipeline. *)
         Current_web.run ~mode site;
         (* Optional: provides a web UI *)
       ])

(* Command-line parsing *)

open Cmdliner

let named f = Cmdliner.Term.(app (const f))

let ocluster_cap =
  Arg.value
  @@ Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None
  @@ Arg.info ~doc:"The ocluster submission capability file" ~docv:"FILE"
       [ "ocluster-cap" ]
  |> named (fun x -> `Ocluster_cap x)

let filter =
  Arg.value
  @@ Arg.opt ~vopt:(Some []) Arg.(some (list string)) None
  @@ Arg.info ~doc:"Only build a subset of the jobs." [ "f"; "filter" ]
  |> named (fun x -> `Filter x)

let cmd =
  let doc = "an OCurrent pipeline" in
  ( Term.(
      const main
      $ Current.Config.cmdliner
      $ Current_web.cmdliner
      $ ocluster_cap
      $ filter),
    Term.info program_name ~doc )

let () = Term.(exit @@ eval cmd)
