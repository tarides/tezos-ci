open Analysis
open Lib

let tezt_job_total = 25

let template ~script analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      [
        user ~uid:1000 ~gid:1000; 
        workdir "/home/tezos/src";
        copy ~from:(`Build "src") [ "/tezos/" ] ~dst:".";
        copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
        run ". ./scripts/version.sh";
        env "VIRTUAL_ENV" "/home/tezos/.venv";
        env "PATH" "$VIRTUAL_ENV/bin:$PATH";
        run "mkdir tests_python/tmp";
        run "touch tests_python/tmp/empty__to_avoid_glob_failing";
        workdir "tests_python";
        run "%s; exit_code=$?; tail -n 100 tmp/*; exit $exit_code" script;
      ])

let pytest ~tezt_job =
  let script =
    Fmt.str
      {|opam exec -- poetry run pytest --exitfirst --prev-junit-xml test-results.xml --job %d/%d --color=yes --log-dir=tmp "--junitxml=reports/report_%d_%d.xml" --timeout 1800 2>&1 | tee "tmp/test_%d.out" | tail |}
      tezt_job tezt_job_total tezt_job tezt_job_total tezt_job
  in
  template ~script

let examples =
  let script =
    {|PYTHONPATH=\$PYTHONPATH:./ poetry run python examples/forge_transfer.py &&
    PYTHONPATH=\$PYTHONPATH:./ poetry run python examples/example.py && 
    PYTHONPATH=./ poetry run pytest --exitfirst examples/test_example.py |}
  in
  template ~script

let all ~builder (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let protocol_tests =
    List.init tezt_job_total (fun n -> n + 1) (* 1, 2, ..., tezt_job_total *)
    |> List.map (fun n ->
           let label = Fmt.str "integration:pytest:%d" n in
           Lib.Builder.build builder ~label
             (Current.map (pytest ~tezt_job:n) analysis))
    |> Task.all ~name:(Current.return "integration:pytest")
  in
  let examples =
    let examples = Current.map examples analysis in
    Lib.Builder.build ~label:"integration:pytest_examples" builder examples
  in
  Task.all ~name:(Current.return "intgeration") [ protocol_tests; examples ]
