open Analysis
open Lib

let template ?(extra_script = []) ~name ~targets analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  let make =
    match targets with
    | [] -> []
    | targets ->
        [
          Obuilder_spec.run "opam exec -- scripts/test_wrapper.sh %s %s" name
            (String.concat " " targets);
        ]
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      ([
         user ~uid:1000 ~gid:1000;
         workdir "/home/tezos/src";
         copy ~from:(`Build "src") [ "/tezos/" ] ~dst:".";
         copy ~from:(`Build "build") [ "/dist/" ] ~dst:".";
         env "recommended_node_version"
           analysis.version.recommended_node_version;
         (* TODO *)
         env "ARCH" "x86_64";
       ]
      @ make
      @ extra_script))

let targets =
  [
    ( "unit:012_Psithaca",
      [
        "@@src/proto_012_Psithaca/lib_protocol/test/integration/runtest";
        "@src/proto_012_Psithaca/lib_protocol/test/integration/consensus/runtest";
        "@src/proto_012_Psithaca/lib_protocol/test/integration/gas/runtest";
        "@src/proto_012_Psithaca/lib_protocol/test/integration/michelson/runtest";
        "@src/proto_012_Psithaca/lib_protocol/test/integration/operations/runtest";
        "@src/proto_012_Psithaca/lib_protocol/test/pbt/runtest";
        "@src/proto_012_Psithaca/lib_protocol/test/unit/runtest";
        "@src/proto_012_Psithaca/lib_benchmark/runtest";
        "@src/proto_012_Psithaca/lib_client/runtest";
        "@src/proto_012_Psithaca/lib_plugin/runtest";
        "@src/proto_012_Psithaca/lib_delegate/runtest";
      ],
      None );
    ( "unit:013_PtJakart",
      [
        "@@src/proto_013_PtJakart/lib_protocol/test/integration/runtest";
        "@src/proto_013_PtJakart/lib_protocol/test/integration/consensus/runtest";
        "@src/proto_013_PtJakart/lib_protocol/test/integration/gas/runtest";
        "@src/proto_013_PtJakart/lib_protocol/test/integration/michelson/runtest";
        "@src/proto_013_PtJakart/lib_protocol/test/integration/operations/runtest";
        "@src/proto_013_PtJakart/lib_protocol/test/pbt/runtest";
        "@src/proto_013_PtJakart/lib_protocol/test/unit/runtest";
        "@src/proto_013_PtJakart/lib_benchmark/runtest";
        "@src/proto_013_PtJakart/lib_client/runtest";
        "@src/proto_013_PtJakart/lib_plugin/runtest";
        "@src/proto_013_PtJakart/lib_delegate/runtest";
      ],
      None );
    ( "unit:alpha",
      [
        "@@src/proto_alpha/lib_protocol/test/integration/runtest";
        "@src/proto_alpha/lib_protocol/test/integration/consensus/runtest";
        "@src/proto_alpha/lib_protocol/test/integration/gas/runtest";
        "@src/proto_alpha/lib_protocol/test/integration/michelson/runtest";
        "@src/proto_alpha/lib_protocol/test/integration/operations/runtest";
        "@src/proto_alpha/lib_protocol/test/pbt/runtest";
        "@src/proto_alpha/lib_protocol/test/unit/runtest";
        "@src/proto_alpha/lib_protocol/test/regression/runtest";
        "@src/proto_alpha/lib_benchmark/runtest";
        "@src/proto_alpha/lib_client/runtest";
        "@src/proto_alpha/lib_plugin/runtest";
        "@src/proto_alpha/lib_delegate/runtest";
      ],
      None );
    ( "unit:non-proto",
      [],
      Some
        Obuilder_spec.
          [ run "opam exec -- make test-nonproto-unit test-webassembly" ] );
    ( "unit:js_components",
      [],
      Some
        Obuilder_spec.
          [
            run
              "bash -c \". ./scripts/install_build_deps.js.sh && opam exec -- \
               make test-js\"";
          ] );
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
           template ?extra_script ~name ~targets analysis
         in
         Lib.Builder.build ~label:name builder spec)
       targets)
