module Git = Current_git
module Gitlab = Current_gitlab
module Docker = Current_docker.Default

let program_name = "tezos-ci"

let repo_id =
  { Gitlab.Repo_id.owner = "tezos"; name = "tezos"; project_id = 3836952 }

let ci_refs_staleness = Duration.of_day 1

let ci_refs gitlab =
  let to_ptime str =
    Ptime.of_rfc3339 str |> function
    | Ok (t, _, _) -> t
    | Error (`RFC3339 (_, e)) -> Fmt.failwith "%a" Ptime.pp_rfc3339_error e
  in
  let is_not_stale ~default_ref (ref, commit) =
    let cutoff = Unix.gettimeofday () -. Duration.to_f ci_refs_staleness in
    let active x =
      let committed =
        Ptime.to_float_s (to_ptime (Gitlab.Api.Commit.committed_date x))
      in
      committed > cutoff
    in
    let is_default = function
      | Pipeline.Source.Branch name ->
          default_ref = (`Ref ("refs/heads" ^ name) : Gitlab.Api.Ref.t)
      | _ -> false
    in
    is_default ref || active commit
  in

  let process_ref = function
    | `PR number ->
        Pipeline.Source.Merge_request
          { from_branch = string_of_int number; to_branch = "master" }
    | `Ref ref -> (
        match String.split_on_char '/' ref with
        | "refs" :: "heads" :: branch -> Pipeline.Source.Branch (String.concat "/" branch)
        | [ "refs"; "tags"; tag ] -> Pipeline.Source.Tag tag
        | _ -> failwith ("Could not process ref " ^ ref))
  in

  let process_refs refs =
    let default_ref = Gitlab.Api.default_ref refs in
    Gitlab.Api.all_refs refs
    |> Gitlab.Api.Ref_map.bindings
    |> List.map (fun (ref, commit) -> (process_ref ref, commit))
    |> List.filter (is_not_stale ~default_ref)
  in

  let open Current.Syntax in
  Current.component "CI refs"
  |> let> () = Current.return () in
     Gitlab.Api.refs gitlab repo_id
     |> Current.Primitive.map_result (Result.map process_refs)

module RefCommit = struct
  type t = Pipeline.Source.t * Gitlab.Api.Commit.t

  let pp f (source, commit) =
    Fmt.pf f "%s: %a" (Pipeline.Source.id source) Gitlab.Api.Commit.pp commit

  let compare (s1, c1) (s2, c2) =
    match Pipeline.Source.compare s1 s2 with
    | 0 -> Gitlab.Api.Commit.compare c1 c2
    | v -> v
end

let pipeline ~index ocluster gitlab =
  ci_refs gitlab
  |> Current.list_iter (module RefCommit) @@ fun src ->
     let open Current.Syntax in
     Current.component "pipeline"
     |> let** source = Current.map fst src in
        let commit =
          Current.map (fun (_, commit) -> commit |> Gitlab.Api.Commit.id) src
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
             ~input:src

let main () current_config mode gitlab (`Ocluster_cap cap) =
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
        pipeline ~index ocluster gitlab)
  in
  let site =
    let routes =
      Routes.(
        (s "webhooks" / s "gitlab" /? nil)
        @--> Gitlab.webhook ~webhook_secret:(Gitlab.Api.webhook_secret gitlab))
      :: Website.routes index
      @ Current_web.routes engine
    in
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
  |> Result.map_error (fun (`Msg msg) -> msg)

(* Command-line parsing *)

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
  let info = Cmd.info program_name ~doc ~sdocs in
  Cmd.v info Term.(
        const main
        $ Logging.cmdliner
    $ Current.Config.cmdliner
    $ Current_web.cmdliner
    $ Current_gitlab.Api.cmdliner
    $ ocluster_cap)

let () = exit (Cmd.eval_result cmd)
