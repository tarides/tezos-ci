module Git = Current_git
module Docker = Current_docker.Default
open Stages

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

let commit gref =
  Git.clone ~schedule:monthly ~gref "https://gitlab.com/tezos/tezos"

(* https://gitlab.com/tezos/tezos/-/merge_requests/2970/commits *)
let _commits =
  [
    commit "master";
    commit "638f524f5e8a0bd43271202e98d62683e0120057";
    (* Stdlib.Compare.Z: use Z.Compare rather than Make(Z) *)
  ]
  |> Current.list_seq

let do_build ~filter label =
  match filter with None -> true | Some filter -> List.mem label filter

let _maybe_build ~filter ~label v =
  if do_build ~filter label then v ()
  else
    let open Current.Syntax in
    let* () = Current.return ~label:("Build skipped: " ^ label) () in
    Current.active `Ready

let pipeline ocluster _filter =
  let repo_tezos =
    Git.clone ~schedule:monthly ~gref:"master" "https://gitlab.com/tezos/tezos"
  in
  let builder =
    match ocluster with
    | None -> Lib.Builder.make_docker repo_tezos
    | Some ocluster -> Lib.Builder.make_ocluster `Docker ocluster repo_tezos
  in
  Stages.v
    (Merge_request { from_branch = "dev"; to_branch = "master" })
    (repo_tezos |> Current.map Git.Commit.id)
  |> Stages.pipeline ~builder

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
  let engine =
    Current.Engine.create ~config:current_config (fun () ->
        pipeline ocluster filter)
  in
  let site =
    let routes = Current_web.routes engine in
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
