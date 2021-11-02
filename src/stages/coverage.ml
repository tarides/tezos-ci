open Analysis

type target = Unit | Python_alpha | Tezt_coverage

let target_to_string = function
  | Unit -> "test-unit"
  | Python_alpha -> "test-python-alpha"
  | Tezt_coverage -> "test-tezt-coverage"

let template ~target analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  Obuilder_spec.(
    stage ~from ~child_builds:[ ("build", build) ]
      [
        user ~uid:100 ~gid:100;
        workdir "/home/tezos";
        copy [ "/" ] ~dst:"./";
        copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
        run "find . -maxdepth 3";
        run ". ./scripts/version.sh";
        run ". /home/tezos/.venv/bin/activate";
        env "COVERAGE_OPTION" "--instrument-with bisect_ppx";
        env "BISECT_FILE" "/home/tezos/_coverage_output/";
        run "opam exec -- make %s || true" (target_to_string target);
        run "opam exec -- make coverage-report";
        run "opam exec -- make coverage-report-summary";
        run "tail -n 100 _coverage_report/*";
      ])

let _job ~build (analysis : Tezos_repository.t Current.t) =
  [ Unit ]
  |> List.map (fun target ->
         let label =
           Fmt.str "integration:test_coverage:%s" (target_to_string target)
         in
         build ~label (Current.map (template ~target) analysis))
  |> Current.all

let test_coverage ~builder:_ _ =
  Task.empty ~name:"integration:test_coverage"
