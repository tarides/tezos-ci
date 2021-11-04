open Analysis
open Lib

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
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      [
        user ~uid:100 ~gid:100;
        workdir "/tezos/";
        copy ~from:(`Build "src") [ "/tezos/" ] ~dst:".";
        copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
        run ". ./scripts/version.sh";
        env "VIRTUAL_ENV" "/home/tezos/.venv";
        env "PATH" "$VIRTUAL_ENV/bin:$PATH";
        env "COVERAGE_OPTION" "--instrument-with bisect_ppx";
        env "BISECT_FILE" "/tezos/_coverage_output/";
        run "opam exec -- make %s || true" (target_to_string target);
        run "opam exec -- make coverage-report";
        run "opam exec -- make coverage-report-summary";
        run "tail -n 100 _coverage_report/*";
      ])

let test_coverage ~builder (analysis : Tezos_repository.t Current.t) =
  [ Unit; Python_alpha; Tezt_coverage ]
  |> List.map (fun target ->
         let label =
           Fmt.str "integration:test_coverage:%s" (target_to_string target)
         in
         Builder.build builder ~label (Current.map (template ~target) analysis))
  |> Task.all ~name:(Current.return "integration:test_coverage")
