let cache = [ Obuilder_spec.Cache.v ~target:"_build" "tezos-dune-build" ]

(**
  Build tezos binaries.
  paths:
    - tezos-*
    - src/proto_*/parameters/*.json
    - _build/default/src/lib_protocol_compiler/main_native.exe
 *)
let v =
  let from =
    Variables.image_template__runtime_build_test_dependencies_template
  in
  let build =
    Obuilder_spec.(
      stage ~from
        [
          user ~uid:100 ~gid:100;
          env "HOME" "/home/tezos";
          workdir "/tezos/";
          copy [ "scripts/version.sh" ] ~dst:"./scripts/version.sh";
          run ". ./scripts/version.sh";
          (* Load the environment poetry previously created in the docker image.
             Give access to the Python dependencies/executables *)
          run ". $HOME/.venv/bin/activate";
          (* TODO: analysis step to figure out active protocols and step caching *)
          copy [ "." ] ~dst:".";
          run "./scripts/remove-old-protocols.sh";
          (* 1. Some basic, fast sanity checks *)
          (* TODO: sanity check for the version *)
          run "diff poetry.lock /home/tezos/poetry.lock";
          run "diff pyproject.toml /home/tezos/pyproject.toml";
          run ~cache "opam exec -- dune build @runtest_dune_template";
          (* 2. Actually build and extract _build/default/src/lib_protocol_compiler/main_native.exe from the cached folder *)
          run ~cache
            "opam exec -- make all build-test && mkdir dist && cp --parents \
             tezos-* src/proto_*/parameters/*.json \
             _build/default/src/lib_protocol_compiler/main_native.exe dist";
        ])
  in
  Obuilder_spec.(
    stage ~child_builds:[ ("build", build) ] ~from:"scratch"
      [ copy ~from:(`Build "build") [ "/tezos/dist" ] ~dst:"/" ])
