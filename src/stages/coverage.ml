open Analysis
open Lib

type target = Unit | Python_alpha | Tezt_coverage

let target_to_string = function
  | Unit -> "test-unit"
  | Python_alpha -> "test-python-alpha"
  | Tezt_coverage -> "test-tezt-coverage"

let template analysis =
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
        env "VIRTUAL_ENV" "/home/tezos/.venv";
        env "PATH" "$VIRTUAL_ENV/bin:$PATH";
        env "COVERAGE_OPTION" "--instrument-with bisect_ppx";
        env "BISECT_FILE" "/tezos/_coverage_output/";
        env "COVERAGE_OUTPUT" "_coverage_output";
        run "opam exec -- make coverage-report";
        run
          {|opam exec -- make coverage-report-summary | sed 's@Coverage: [[:digit:]]\+/[[:digit:]]\+ (\(.*%%\))@Coverage: \1@|};
        run "opam exec -- make coverage-report-cobertura";
      ])

let test_coverage ~builder (analysis : Tezos_repository.t Current.t) =
  let label = Fmt.str "integration:test_coverage" in
  Builder.build builder ~label (Current.map template analysis)
