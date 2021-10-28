type source =
  | Schedule of Current_cache.Schedule.t
  | Branch of string
  | Tag of string
  | Merge_request of { from_branch : string; to_branch : string }

type t = { source : source; commit : Current_git.Commit_id.t Current.t }

let v source commit = { source; commit }

type mode =
  | Development
  | Development_manual
  | Master_and_releases
  | Master
  | Development_documentation
  | Opam_packaging
  | Development_coverage
  | Development_arm64
  | Extended_test_pipeline
  | Commit_tag_is_version
  | Always

let branch_match branch target = Astring.String.is_infix ~affix:target branch

let is_version t =
  (* TODO: implement /\A\d+\.\d+\.\d+\z/*)
  match String.split_on_char '.' t with [ _; _; _ ] -> true | _ -> false

type should_run = Yes | Manual | No

let should_run mode source =
  let branch_or_mr_source_branch_match value = function
    | Branch branch when branch_match branch value -> true
    | Merge_request { from_branch; _ } when branch_match from_branch value ->
        true
    | _ -> false
  in
  let is_master_or_release = function
    | Schedule _ | Branch "master" | Tag _ -> true
    | v -> branch_or_mr_source_branch_match "release" v
  in

  match (mode, source) with
  | Development, v when not (is_master_or_release v) -> Yes
  | Development, _ -> No
  | Development_manual, v when not (is_master_or_release v) -> Manual
  | Development_manual, _ -> No
  | Master_and_releases, v when is_master_or_release v -> Yes
  | Master_and_releases, _ -> No
  | Master, Branch "master" -> Yes
  | Master, _ -> No
  | Development_documentation, Schedule _ -> Yes
  | Development_documentation, v when branch_or_mr_source_branch_match "doc" v
    ->
      Yes
  | Development_documentation, _ -> No
  | Development_coverage, Schedule _ -> Yes
  | Development_coverage, _ -> No
  | Development_arm64, Schedule _ -> Yes
  | Development_arm64, v when branch_or_mr_source_branch_match "arm64" v -> Yes
  | Development_arm64, _ -> No
  | Extended_test_pipeline, Schedule _ -> Yes
  | Extended_test_pipeline, _ -> No
  | Opam_packaging, Branch "master"
  | Opam_packaging, Merge_request _
  | Opam_packaging, Schedule _ ->
      Yes
  | Opam_packaging, Branch branch when branch_match branch "opam" -> Yes
  | Opam_packaging, _ -> No
  | Commit_tag_is_version, Tag tag when is_version tag -> Yes
  | Commit_tag_is_version, _ -> No
  | Always, _ -> Yes

let stages =
  [
    ( "build",
      [
        (Development, "x86_64", Build.x86_64);
        (Development_arm64, "arm64", Build.arm64);
        (*  (Development, Doc.build);*)
      ] );
    (* ( "sanity_ci",
         [ (Development, Lints.sanity_ci); (Always, Lints.docker_hadolint) ] );
       ( "test",
         [
           (Development, Integration.all);
           (Always, Lints.misc_checks);
           (Always, Lints.check_precommit_hook);
           (Development, Unittest.all);
         ] );
       ( "doc",
         [
           (Master, Publish.documentation);
           (Development_documentation, Test_doc_scripts.all);
         ] );
       ("packaging", [ (Opam_packaging, Packaging.all) ]);
       ("build_release", [ (Master_and_releases, Publish.build_release) ]);
       ("publish_release", [ (Commit_tag_is_version, Publish.publish_release) ]);
       ("test_coverage", [ (Development_coverage, Coverage.test_coverage) ]);
       ( "manual",
         [
           (Development_manual, Doc.build_all); (Development_manual, Doc.linkcheck);
         ] );*)
  ]

(* execute the pipeline *)
let pipeline ~builder { source; commit } =
  let open Current.Syntax in
  let analysis = Analysis.Analyse.v (Current_git.fetch commit) in
  List.fold_left
    (fun analysis (stage_name, tasks) ->
      let analysis =
        (* add a label *)
        let+ () = Current.return ~label:stage_name ()
        and+ analysis = analysis in
        analysis
      in
      let jobs =
        tasks
        |> List.map (fun (mode, name, current) ->
               match should_run mode source with
               | No ->
                   Current.return
                     ~label:("Skipped " ^ stage_name ^ ":" ^ name)
                     ()
               | _ -> current ~builder analysis)
        |> Current.all
        |> Current.collapse ~key:"stages" ~value:stage_name ~input:analysis
      in
      Current.gate ~on:jobs analysis)
    analysis stages
  |> Current.ignore_value
