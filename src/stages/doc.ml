open Analysis

let build ~builder (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    let from =
      Variables.docker_image_runtime_build_test_dependencies analysis.version
    in
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("src", Lib.Fetch.spec analysis) ]
        [
          user ~uid:100 ~gid:100;
          workdir "/home/tezos";
          copy ~from:(`Build "src") [ "/tezos" ] ~dst:".";
          run "opam exec -- make -C docs html";
        ])
  in
  Lib.Builder.build ~label:"documentation:build" builder spec

let build_all ~builder (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    let from =
      Variables.docker_image_runtime_build_test_dependencies analysis.version
    in
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("src", Lib.Fetch.spec analysis) ]
        [
          user ~uid:100 ~gid:100;
          workdir "/home/tezos";
          copy ~from:(`Build "src") [ "/tezos" ] ~dst:".";
          run "opam exec -- make -C docs all";
        ])
  in
  Lib.Builder.build ~label:"documentation:build_all" builder spec

let linkcheck ~builder (analysis : Tezos_repository.t Current.t) =
  let open Current.Syntax in
  let spec =
    let+ analysis = analysis in
    let from =
      Variables.docker_image_runtime_build_test_dependencies analysis.version
    in
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("src", Lib.Fetch.spec analysis) ]
        [
          user ~uid:100 ~gid:100;
          workdir "/home/tezos";
          copy ~from:(`Build "src") [ "/tezos" ] ~dst:".";
          run "opam exec -- make -C docs all";
          run "make -C docs redirectcheck";
          run "make -C docs linkcheck";
          run "make -C docs sanitycheck";
        ])
  in
  Lib.Builder.build ~label:"documentation:linkcheck" builder spec
