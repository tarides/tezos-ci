let cache =
  [ Obuilder_spec.Cache.v ~target:"/home/tezos/.cache/dune" "tezos-dune-build" ]

(**
  Build tezos binaries.
  paths:
    - tezos-*
    - src/proto_*/parameters/*.json
    - _build/default/src/lib_protocol_compiler/main_native.exe
 *)
let v version =
  let from = Variables.docker_image_runtime_build_test_dependencies version in
  let build =
    Obuilder_spec.(
      stage ~from
        [
          user ~uid:100 ~gid:100;
          env "HOME" "/home/tezos";
          workdir "/tezos/";
          run "sudo chown 100:100 /tezos/";
          copy [ "scripts/version.sh" ] ~dst:"./scripts/version.sh";
          run ". ./scripts/version.sh";
          (* Load the environment poetry previously created in the docker image.
             Give access to the Python dependencies/executables *)
          run ". $HOME/.venv/bin/activate";
          (* TODO: analysis step to figure out active protocols and step caching *)
          copy
            [
              "active_testing_protocol_versions";
              "active_protocol_versions";
              "poetry.lock";
              "pyproject.toml";
              "Makefile";
              "dune";
              "dune-project";
            ]
            ~dst:"./";
          copy [ "src" ] ~dst:"src/";
          copy [ "vendors" ] ~dst:"vendors/";
          copy
            [ "scripts/remove-old-protocols.sh" ]
            ~dst:"scripts/remove-old-protocols.sh";
          run "./scripts/remove-old-protocols.sh";
          (* 1. Some basic, fast sanity checks *)
          (* TODO: sanity check for the version *)
          run "diff poetry.lock /home/tezos/poetry.lock";
          run "diff pyproject.toml /home/tezos/pyproject.toml";
          env "DUNE_CACHE" "enabled";
          env "DUNE_CACHE_TRANSPORT" "direct";
          run ~cache "opam exec -- dune build @runtest_dune_template";
          (* 2. Actually build and extract _build/default/src/lib_protocol_compiler/main_native.exe from the cached folder *)
          run ~cache
            "opam exec -- make all build-test && mkdir dist && cp --parents \
             tezos-* src/proto_*/parameters/*.json \
             _build/default/src/lib_protocol_compiler/main_native.exe dist";
        ])
  in
  Obuilder_spec.(
    stage ~child_builds:[ ("tzbuild", build) ] ~from:"alpine"
      [ copy ~from:(`Build "tzbuild") [ "/tezos/dist" ] ~dst:"/dist" ])
