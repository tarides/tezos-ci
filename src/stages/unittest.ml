open Analysis
open Lib

let template ?(extra_script = []) ~targets analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      ([
         user ~uid:100 ~gid:100;
         workdir "/home/tezos/src";
         copy ~from:(`Build "src") [ "/tezos/" ] ~dst:".";
         copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
         run ". ./scripts/version.sh";
         (* hmmmmm *)
         env "ARCH" "x86_64";
         run "opam exec -- make %s" (String.concat " " targets);
       ]
      @ extra_script))

let targets =
  [
    ( "unit:010_PtGRANAD",
      [
        "src/proto_010_PtGRANAD/lib_client.test_proto";
        "src/proto_010_PtGRANAD/lib_protocol.test_proto";
      ],
      None );
    ( "unit:011_PtHangz2",
      [
        "src/proto_011_PtHangz2/lib_benchmark/lib_benchmark_type_inference.test_proto";
        "src/proto_011_PtHangz2/lib_benchmark.test_proto";
        "src/proto_011_PtHangz2/lib_client.test_proto";
        "src/proto_011_PtHangz2/lib_protocol.test_proto";
      ],
      None );
    ( "unit:alpha",
      [
        "src/proto_alpha/lib_benchmark/lib_benchmark_type_inference.test_proto";
        "src/proto_alpha/lib_benchmark.test_proto";
        "src/proto_alpha/lib_client.test_proto";
        "src/proto_alpha/lib_protocol.test_proto";
      ],
      None );
    ("unit:non-proto", [ "test-nonproto-unit" ], None);
    ( "unit:js_components",
      [],
      Some [ Obuilder_spec.run "opam exec -- dune build @runtest_js" ] );
    ( "unit:protocol_compiles",
      [],
      Some
        [
          Obuilder_spec.run "opam exec -- dune build @runtest_compile_protocol";
        ] );
  ]

let all ~builder (analysis : Analysis.Tezos_repository.t Current.t) =
  Task.all
    ~name:(Current.return "unittest")
    (List.map
       (fun (name, targets, extra_script) ->
         let spec =
           let open Current.Syntax in
           let+ analysis = analysis in
           template ?extra_script ~targets analysis
         in
         Lib.Builder.build ~label:name builder spec)
       targets)
