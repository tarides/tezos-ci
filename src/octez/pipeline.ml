module Source = struct
  type t =
    | Schedule of Current_cache.Schedule.t
    | Branch of string
    | Tag of string
    | Merge_request of
        { from_branch : string
        ; to_branch : string
        }

  let id = function
    | Schedule _ -> Fmt.str "schedule"
    | Branch b -> Fmt.str "branch:%s" b
    | Tag t -> Fmt.str "tag:%s" t
    | Merge_request { from_branch; to_branch } ->
      Fmt.str "mr:%s:%s" from_branch to_branch

  let marshal = id

  let unmarshal v =
    match String.split_on_char ':' v with
    | [ "schedule" ] -> failwith "not implemented"
    | [ "branch"; branch ] -> Branch branch
    | [ "tag"; tag ] -> Tag tag
    | [ "mr"; from_branch; to_branch ] ->
      Merge_request { from_branch; to_branch }
    | _ -> failwith "unknown source"

  let to_string = function
    | Schedule _ -> Fmt.str "Schedule"
    | Branch b -> Fmt.str "Branch %s" b
    | Tag t -> Fmt.str "Tag %s" t
    | Merge_request { from_branch; to_branch } ->
      Fmt.str "MR #%s on %s" from_branch to_branch

  let link_to = function
    | Schedule _ -> ""
    | Branch b -> "https://gitlab.com/tezos/tezos/-/tree/" ^ b
    | Tag t -> "https://gitlab.com/tezos/tezos/-/tags/" ^ t
    | Merge_request { from_branch; _ } ->
      "https://gitlab.com/tezos/tezos/-/merge_requests/" ^ from_branch
  (* XXX: hack *)

  let compare s1 s2 = compare s1 s2 (* XXX: better compare function ?*)

  module Map = Map.Make (struct
    type nonrec t = t

    let compare = compare
  end)
end

type mode =
  | Development
  | Development_manual
  | Master_and_releases
  | Master
  | Development_documentation
  | Opam_packaging
  | Development_coverage
  | Development_arm64
  | Commit_tag_is_version
  | Always

let branch_match branch target = Astring.String.is_infix ~affix:target branch

let is_version t =
  (* TODO: implement /\A\d+\.\d+\.\d+\z/*)
  match String.split_on_char '.' t with
  | [ _; _; _ ] -> true
  | _ -> false

type should_run =
  | Yes
  | Manual
  | No

let should_run mode source =
  let branch_or_mr_source_branch_match value = function
    | Source.Branch branch when branch_match branch value -> true
    | Merge_request { from_branch; _ } when branch_match from_branch value ->
      true
    | _ -> false
  in
  let is_master_or_release = function
    | Source.Schedule _ | Branch "master" | Tag _ -> true
    | v -> branch_or_mr_source_branch_match "release" v
  in

  match (mode, source) with
  | Development, v when not (is_master_or_release v) -> Yes
  | Development, _ -> No
  | Development_manual, v when not (is_master_or_release v) -> Manual
  | Development_manual, _ -> No
  | Master_and_releases, v when is_master_or_release v -> Yes
  | Master_and_releases, _ -> No
  | Master, Source.Branch "master" -> Yes
  | Master, _ -> No
  | Development_documentation, Schedule _ -> Yes
  | Development_documentation, v when branch_or_mr_source_branch_match "doc" v
    -> Yes
  | Development_documentation, _ -> No
  | Development_coverage, Schedule _ -> Yes
  | Development_coverage, _ -> Manual
  | Development_arm64, Schedule _ -> Yes
  | Development_arm64, v when branch_or_mr_source_branch_match "arm64" v -> Yes
  | Development_arm64, _ -> Manual
  | Opam_packaging, Branch "master"
  | Opam_packaging, Merge_request _
  | Opam_packaging, Schedule _ -> Yes
  | Opam_packaging, Branch branch when branch_match branch "opam" -> Yes
  | Opam_packaging, _ -> No
  | Commit_tag_is_version, Tag tag when is_version tag -> Yes
  | Commit_tag_is_version, _ -> No
  | Always, _ -> Yes

let stages =
  let open Stages in
  [ ("base_images", [ (Development, "build", Base_image.build) ])
  ; ( "build"
    , [ (Development, "x86_64", Build.x86_64)
      ; (Development_arm64, "arm64", Build.arm64)
      ; (Development, "doc", Doc.build)
      ] )
  ; ( "sanity_ci"
    , [ (Development, "sanity_ci", Lints.sanity_ci)
      ; (Always, "docker_hadolint", Lints.docker_hadolint)
      ] )
  ; ( "test"
    , [ (Development, "integration", Integration.all)
      ; (Development, "integration:tezt", Tezt.job)
      ; ( Development
        , "test-liquidity-baking-scripts"
        , Test_liquidity_baking_scripts.test )
      ; (Always, "misc", Lints.misc_checks)
      ; (Always, "check_precommit_hook", Lints.check_precommit_hook)
      ; (Development, "unit tests", Unittest.all)
      ] )
  ; ( "doc"
    , [ (Master, "documentation", Publish.documentation)
      ; (Development_documentation, "dev documentation", Test_doc_scripts.all)
      ] )
  ; ("packaging", [ (Opam_packaging, "packaging", Packaging.all) ])
  ; ( "build_release"
    , [ (Master_and_releases, "build_release", Publish.build_release) ] )
  ; ( "publish_release"
    , [ (Commit_tag_is_version, "publish_release", Publish.publish_release) ] )
  ; ( "test_coverage"
    , [ (Development_coverage, "test_coverage", Coverage.test_coverage) ] )
  ; ( "manual"
    , [ (Development_manual, "doc:build_all", Doc.build_all)
      ; (Development_manual, "doc:linkcheck", Doc.linkcheck)
      ] )
  ]

let pipeline_stage ~stage_name ~gate ~builder ~analysis ~source stage =
  let jobs =
    stage
    |> List.map (fun (mode, name, task) ->
           match should_run mode source with
           | No -> Lib.Task.skip ~name "Shouldn't run in this pipeline"
           | Manual ->
             let builder = Lib.Builder.manual builder in
             task ~builder analysis |> Lib.Task.allow_failures
           | Yes -> task ~builder analysis)
  in
  let current =
    List.map Current_web_pipelines.Task.current jobs
    |> Current.all
    |> Current.collapse ~key:"stages" ~value:stage_name
         ~input:(Current.all [ analysis |> Current.ignore_value; gate ])
  in
  (current, jobs)

type metadata =
  { source : Source.t
  ; commit : Current_git.Commit_id.t
  }

(* execute the pipeline *)
let v ~builder source commit =
  let open Current.Syntax in
  let analysis = Analysis.Analyse.v (Current_git.fetch commit) in
  let current, pages =
    List.fold_left
      (fun (gate, rest) (stage_name, tasks) ->
        let gate =
          (* add a label *)
          let+ () = Current.return ~label:stage_name ()
          and+ () = gate in
          ()
        in
        let jobs, pages =
          let gated_builder = Lib.Builder.gate ~gate builder in
          pipeline_stage ~stage_name ~gate ~builder:gated_builder ~source
            ~analysis tasks
        in
        (Current.gate ~on:jobs gate, (stage_name, pages) :: rest))
      (Current.return (), [])
      stages
  in

  let state =
    Current.collapse ~key:"stages_state_root" ~value:"root" ~input:analysis
    @@ let+ stages =
         pages |> List.rev
         |> List.map (fun (stage_name, substages) ->
                List.map Current_web_pipelines.Task.state substages
                |> Current.list_seq
                |> Current.map (fun jobs ->
                       { Current_web_pipelines.State.jobs
                       ; metadata = stage_name
                       })
                |> Current.collapse ~key:"stages_state" ~value:stage_name
                     ~input:analysis)
         |> Current.list_seq
       and+ commit = commit in
       { Current_web_pipelines.State.stages; metadata = { source; commit } }
  in
  Current_web_pipelines.Task.v ~current ~state
