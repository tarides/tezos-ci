module Git = Current_git
module Docker = Current_docker.Default
module Analyse = Analyse
module Packaging = Packaging
module Gitlab = Current_gitlab

let () = Logging.init ()
(* TODO This seems to be setup to Ocurrent a bunch of commits. *)
(* let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) () *)

(* module Commit_sequence = struct *)
(*   module Key = struct *)
(*     type t = Current_git.Commit.t list *)

(*     let digest v = *)
(*       List.map Current_git.Commit.hash v *)
(*       |> String.concat ";" *)
(*       |> Digest.string *)
(*       |> Digest.to_hex *)
(*   end *)

(*   type state = { *)
(*     mutable digest : string; *)
(*     mutable index : int; *)
(*     mutable max : int; *)
(*   } *)

(*   let empty digest = { digest; index = 0; max = 0 } *)

(*   let update_to state digest max = *)
(*     state.digest <- digest; *)
(*     state.max <- max; *)
(*     state.index <- 0 *)

(*   let next ~job state values = *)
(*     let digest = Key.digest values in *)
(*     if digest <> state.digest then update_to state digest (List.length values); *)
(*     let return_value = List.nth values state.index in *)
(*     Current.Job.log job "Commit #%d/%d: %a" (state.index + 1) state.max *)
(*       Git.Commit.pp return_value; *)
(*     if state.index + 1 < state.max then state.index <- state.index + 1 *)
(*     else state.index <- 0; *)
(*     return_value *)

(*   module Op = struct *)
(*     let id = "commit-sequence" *)

(*     type t = state *)

(*     module Key = Key *)
(*     module Value = Current_git.Commit *)

(*     let auto_cancel = false *)
(*     let pp f _ = Fmt.string f "commit sequence" *)

(*     let build state job commits = *)
(*       let open Lwt.Syntax in *)
(*       let* () = Current.Job.start ~level:Harmless job in *)
(*       Lwt.return_ok (next ~job state commits) *)
(*   end *)

(*   module Seq = Current_cache.Make (Op) *)

  (* let v commits = *)
  (*   let state = empty "" in *)
  (*   let open Current.Syntax in *)
  (*   Current.component "Cycle commits" *)
  (*   |> let> commits = commits in *)
  (*      Seq.get state commits *)
(* end *)

module Spec = struct
  module Docker = struct
    let pool = Current.Pool.create ~label:"docker build" 1

    let obuilder_spec_build ~label spec =
      let open Current.Syntax in
      let dockerfile =
        let _ = Bos.OS.Dir.create (Fpath.v "/tmp/tezos-ci") in
        let dockerfile =
          let+ spec = spec in
          Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
        in
        let path =
          let+ dockerfile = dockerfile in
          let hash = Digest.string dockerfile |> Digest.to_hex in
          Fpath.v (Fmt.str "/tmp/tezos-ci/Dockerfile.%s.tez" hash)
        in
        let+ () = Current_fs.save path dockerfile and+ path = path in
        `File path
      in
      Docker.build ~label ~pool ~pull:true ~dockerfile
  end

  module Ocluster = struct
    let obuilder_build ~ocluster ~label spec src =
      let open Current.Syntax in
      let spec =
        let+ spec = spec in
        let spec_str = Fmt.to_to_string Obuilder_spec.pp spec in
        { Cluster_api.Obuilder_job.Spec.spec = `Contents spec_str }
      in
      let src =
        let+ src = src in
        [ Git.Commit.id src ]
      in
      Current_ocluster.build_obuilder ocluster ~label ~src ~pool:"linux-arm64"
        spec

    let docker_build ~ocluster ~label spec src =
      let open Current.Syntax in
      let options =
        {
          Cluster_api.Docker.Spec.build_args = [];
          squash = false;
          buildkit = true;
          include_git = true;
        }
      in
      let spec =
        let+ spec = spec in
        Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
      in
      let src =
        let+ src = src in
        [ Git.Commit.id src ]
      in
      Current_ocluster.build ocluster ~options ~label ~src ~pool:"linux-arm64"
        (`Contents spec)
  end
end

let program_name = "tezos-ci"

(* TODO Replaced by `Gitlab.Api.head_commit gitlab repo_id` *)
(* let commit gref = *)
(*   Git.clone ~schedule:monthly ~gref "https://gitlab.com/tezos/tezos" *)

(* https://gitlab.com/tezos/tezos/-/merge_requests/2970/commits *)
(* let commits = *)
(*   [ *)
(*     commit "master"; *)
(*     commit "638f524f5e8a0bd43271202e98d62683e0120057"; *)
(*     (\* Stdlib.Compare.Z: use Z.Compare rather than Make(Z) *\) *)
(*   ] *)
(*   |> Current.list_seq *)

let repo_id =
  Gitlab.Repo_id.({owner = "tezos"; name = "tezos"})

let do_build ~filter label =
  match filter with None -> true | Some filter -> List.mem label filter

let maybe_build ~filter ~label v =
  if do_build ~filter label then v ()
  else
    let open Current.Syntax in
    let* () = Current.return ~label:("Build skipped: " ^ label) () in
    Current.active `Ready

let pipeline ocluster filter gitlab =
  let open Current.Syntax in
  (* let repo_tezos = Commit_sequence.v commits in *)
  let head = Gitlab.Api.head_commit gitlab repo_id in
  (* |> Current.list_iter (module Gitlab.Api.Commit) @@ fun head -> *)
  let repo_tezos = Git.fetch (Current.map Gitlab.Api.Commit.id head) in

  let build =
    match ocluster with
    | None ->
        fun ~label spec ->
          maybe_build ~filter ~label @@ fun () ->
          Spec.Docker.obuilder_spec_build ~label spec (`Git repo_tezos)
          |> Current.ignore_value
    | Some ocluster ->
        fun ~label spec ->
          maybe_build ~filter ~label @@ fun () ->
          Spec.Ocluster.docker_build ~ocluster ~label spec repo_tezos
  in
  let analysis = Analyse.v repo_tezos in
  let build_spec =
    let+ analysis = analysis in
    Build.v analysis.version
  in
  let build_job = build ~label:"build" build_spec in
  let analysis = Current.gate ~on:build_job analysis in
  Current.all_labelled
    [
      ( "integration",
        Integration.job ~build analysis
        |> Current.collapse ~key:"stage" ~value:"integration" ~input:analysis );
      ( "packaging",
        Packaging.job ~build analysis
        |> Current.collapse ~key:"stage" ~value:"packaging" ~input:analysis );
      ( "tezt",
        Tezt.job ~build analysis
        |> Current.collapse ~key:"stage" ~value:"tezt" ~input:analysis );
      ( "coverage",
        Coverage.job ~build analysis
        |> Current.collapse ~key:"stage" ~value:"coverage" ~input:analysis );
    ]

let main current_config mode gitlab (`Ocluster_cap cap) (`Filter filter) =
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
        pipeline ocluster filter gitlab)
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
      $ Current_gitlab.Api.cmdliner 
      $ ocluster_cap
      $ filter),
    Term.info program_name ~doc )

let () = Term.(exit @@ eval cmd)
