module Git = Current_git
module Gitlab = Current_gitlab
module Docker = Current_docker.Default
module Pipeline = Octez.Pipeline

let program_name = "tezos-ci-local"

let pipeline ~index ocluster =
  let source =
    Pipeline.Source.Merge_request
      { from_branch = "master"; to_branch = "master" }
  in
  let commit =
    Git.clone
      ~schedule:(Current_cache.Schedule.v ())
      ~gref:"master" "https://gitlab.com/tezos/tezos.git"
    |> Current.map Git.Commit.id
  in
  let builder =
    match ocluster with
    | None -> Lib.Builder.make_docker
    | Some ocluster -> Lib.Builder.make_ocluster `Docker ocluster
  in
  let task = Pipeline.v ~builder source commit in
  let current = Current_web_pipelines.Task.current task in
  let state = Current_web_pipelines.Task.state task in
  Current.all [ current; Website.update_state index state ]
  |> Current.collapse ~key:"pipeline"
       ~value:(Pipeline.Source.to_string source)
       ~input:commit

(* TODO Add switch to choose between pipelines to run. *)
let main () current_config mode (`Ocluster_cap cap) =
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
  let index = Website.make () in
  let engine =
    Current.Engine.create ~config:current_config (fun () ->
        pipeline ~index ocluster)
  in
  let site =
    let routes = Website.routes index engine @ Current_web.routes engine in
    Current_web.Site.(v ~has_role:allow_all) ~name:program_name routes
  in
  Logging.run
    (Lwt.choose
       [ Current.Engine.thread engine
       ; (* The main thread evaluating the pipeline. *)
         Current_web.run ~mode site (* Optional: provides a web UI *)
       ])
  |> Result.map_error (fun (`Msg msg) -> msg)

(* Command-line parsing *)

let version =
  match Build_info.V1.version () with
  | None -> "n/a"
  | Some v -> Build_info.V1.Version.to_string v

open Cmdliner

let named f = Cmdliner.Term.(app (const f))

let ocluster_cap =
  Arg.value
  @@ Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None
  @@ Arg.info ~doc:"The OCluster submission capability file." ~docv:"FILE"
       [ "ocluster-cap" ]
  |> named (fun x -> `Ocluster_cap x)

let cmd =
  let doc = "an OCurrent pipeline" in
  let sdocs = Manpage.s_common_options in
  let info = Cmd.info program_name ~doc ~sdocs ~version in
  Cmd.v info
    Term.(
      const main $ Logging.cmdliner $ Current.Config.cmdliner
      $ Current_web.cmdliner $ ocluster_cap)

let () = exit @@ Cmd.eval_result cmd
