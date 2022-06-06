open Analysis

let spec analysis =
  let build = Build.v analysis in
  let from =
    Variables.docker_image_runtime_build_test_dependencies analysis.version
  in
  Obuilder_spec.(
    stage ~from
      ~child_builds:[ ("build", build); ("src", Lib.Fetch.spec analysis) ]
      [ user ~uid:100 ~gid:100
      ; workdir "/home/tezos/src"
      ; copy ~from:(`Build "src") [ "/tezos/" ] ~dst:"."
      ; copy ~from:(`Build "build") [ "/dist/" ] ~dst:"."
      ; run ". ./scripts/version.sh"
      ; run
          "scripts/check-liquidity-baking-scripts.sh \
           d98643881fe14996803997f1283e84ebd2067e35 src/proto_010_PtGRANAD"
      ; run
          "scripts/check-liquidity-baking-scripts.sh \
           d98643881fe14996803997f1283e84ebd2067e35 src/proto_alpha"
      ])

let test ~builder analysis =
  let spec = Current.map spec analysis in
  Lib.Builder.build builder ~label:"test-liquidity-baking-scripts" spec
