open Analysis
open Lib

let template ~script analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      [
        user ~uid:100 ~gid:100;
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

let slow_test ~protocol_id test_name =
  let script =
    Fmt.str
      {|opam exec -- poetry run pytest "tests_%s/test_%s.py" --exitfirst -m "slow" -s --log-dir=tmp "--junitxml=reports/%s_%s.xml" 2>&1 | tee "tmp/%s_%s.out" | tail |}
      protocol_id test_name protocol_id test_name protocol_id test_name
  in
  template ~script

let fast_test ~protocol_id =
  let script =
    Fmt.str
      {|opam exec -- poetry run pytest "tests_%s/" --exitfirst -m "not slow" -s --log-dir=tmp "--junitxml=reports/%s_batch.xml" 2>&1 | tee "tmp/%s_batch.out" | tail |}
      protocol_id protocol_id protocol_id
  in
  template ~script

let examples =
  let script =
    {|PYTHONPATH=\$PYTHONPATH:./ poetry run python examples/forge_transfer.py &&
    PYTHONPATH=\$PYTHONPATH:./ poetry run python examples/example.py && 
    PYTHONPATH=./ poetry run pytest --exitfirst examples/test_example.py |}
  in
  template ~script

let job ~(analysis : Tezos_repository.t Current.t) ~builder
    (protocol : Tezos_repository.Active_protocol.t Current.t) =
  let open Current.Syntax in
  let slow_tests =
    let+ protocol = protocol in
    protocol.slow_tests
  in

  let slow_tests =
    Task.list_iter ~collapse_key:"slow-test"
      (module struct
        type t = string

        let pp = Fmt.string
        let compare = String.compare
      end)
      (fun name ->
        let spec =
          let+ name = name and+ protocol = protocol and+ analysis = analysis in
          slow_test ~protocol_id:protocol.id name analysis
        in
        let name =
          let+ protocol = protocol and+ name = name in
          "integration:test_" ^ protocol.id ^ "_" ^ name
        in
        Lib.Builder.build builder ~label:"integration:test" spec
        |> Task.single_c ~name)
      slow_tests
  in
  let batch_test =
    let+ protocol = protocol and+ analysis = analysis in
    fast_test ~protocol_id:protocol.id analysis
  in
  let name =
    let+ protocol = protocol in
    protocol.name
  in
  Task.all ~name
    [
      slow_tests;
      (let name =
         let+ protocol = protocol in
         protocol.id ^ "_batch"
       in
       Lib.Builder.build builder ~label:"integration:batch" batch_test
       |> Task.single_c ~name);
    ]

let all ~builder (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let active_protocols =
    let+ analysis = analysis in
    analysis.active_protocols
  in
  let protocol_tests =
    Task.list_iter ~collapse_key:"active-protocols"
      (module Tezos_repository.Active_protocol)
      (job ~analysis ~builder) active_protocols
  in
  let examples =
    let examples = Current.map examples analysis in
    Lib.Builder.build ~label:"integration:examples" builder examples
    |> Task.single ~name:"integration:examples"
  in
  Task.all ~name:(Current.return "intgeration") [ protocol_tests; examples ]
