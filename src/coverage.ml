type target = Unit | Python_alpha | Tezt_coverage

let target_to_string = function
  | Unit -> "test-unit"
  | Python_alpha -> "test-python-alpha"
  | Tezt_coverage -> "test-tezt-coverage"

let template ~target version =
  let build = Build.v version in
  let from = Variables.docker_image_runtime_build_test_dependencies version in
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

let job ~build (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let version =
    let+ analysis = analysis in
    analysis.version
  in
  [ Unit ]
  |> List.map (fun target ->
         let label =
           Fmt.str "integration:test_coverage:%s" (target_to_string target)
         in
         build ~label (Current.map (template ~target) version))
  |> Current.all
