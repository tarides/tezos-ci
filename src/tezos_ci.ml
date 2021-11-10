module Git = Current_git
module Gitlab = Current_gitlab
module Docker = Current_docker.Default

let () = Logging.init ()
let program_name = "tezos-ci"

let repo_id =
  { Gitlab.Repo_id.owner = "tezos"; name = "tezos"; project_id = 3836952 }

let ppl_ci ~index ~ocluster ~gitlab =
  Gitlab.Api.ci_refs gitlab ~staleness:(Duration.of_day 30) repo_id
  |> Current.list_iter (module Gitlab.Api.Commit) @@ fun head ->
     let commit = Current.map Gitlab.Api.Commit.id head in
     let builder =
       match ocluster with
       | None -> Lib.Builder.make_docker
       | Some ocluster -> Lib.Builder.make_ocluster `Docker ocluster
     in
     let task =
       Pipeline.v
         (Merge_request { from_branch = "master"; to_branch = "master" })
         commit
       |> Pipeline.pipeline ~builder
     in
     Current.all
       [
         task.current;
         Website.Index.update_state index
           ~id:
             (Current.map
                (fun commit -> "commit:" ^ Current_git.Commit_id.hash commit)
                commit)
           task.subtasks_status;
       ]

let ppl_master ~index ~ocluster ~gitlab =
  let head = Gitlab.Api.head_commit gitlab repo_id in
  let repo_tezos_master = Git.fetch (Current.map Gitlab.Api.Commit.id head) in
  let builder =
    match ocluster with
    | None -> Lib.Builder.make_docker
    | Some ocluster -> Lib.Builder.make_ocluster `Docker ocluster
  in
  let task =
    Pipeline.v (Branch "master") (repo_tezos_master |> Current.map Git.Commit.id)
    |> Pipeline.pipeline ~builder
  in
  Current.all
    [
      task.current;
      Website.Index.update_state index
        ~id:(Current.return "branch:master")
        task.subtasks_status;
    ]

let pipeline ~index ocluster gitlab =
  [
    ("master", ppl_master ~index ~ocluster ~gitlab);
    ("ci", ppl_ci ~index ~ocluster ~gitlab);
  ]
  |> Current.all_labelled

let main current_config mode gitlab (`Ocluster_cap cap) =
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
        pipeline ~index ocluster gitlab)
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

let cmd =
  let doc = "an OCurrent pipeline" in
  ( Term.(
      const main
      $ Current.Config.cmdliner
      $ Current_web.cmdliner
      $ Current_gitlab.Api.cmdliner
      $ ocluster_cap),
    Term.info program_name ~doc )

let () = Term.(exit @@ eval cmd)
