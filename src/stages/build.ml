open Analysis
open Lib

let cache =
  [ Obuilder_spec.Cache.v ~target:"/home/tezos/.cache/dune" "tezos-dune-build" ]

(** Build tezos binaries. paths:

    - tezos-*
    - src/proto_*/parameters/*.json
    - _build/default/src/lib_protocol_compiler/main_native.exe *)
let v (tezos_repository : Analysis.Tezos_repository.t) =
  let from =
    Variables.docker_image_runtime_build_test_dependencies
      tezos_repository.version
  in
  let build =
    Obuilder_spec.(
      stage ~from
        ~child_builds:[ ("build_src", Lib.Fetch.spec tezos_repository) ]
        [
          user ~uid:100 ~gid:100;
          env "HOME" "/home/tezos";
          workdir "/tezos/";
          run "sudo chown 100:100 /tezos/";
          copy ~from:(`Build "build_src")
            [ "/tezos/scripts/version.sh" ]
            ~dst:"./scripts/version.sh";
          run ". ./scripts/version.sh";
          (* Load the environment poetry previously created in the docker image.
             Give access to the Python dependencies/executables *)
          run ". $HOME/.venv/bin/activate";
          copy ~from:(`Build "build_src")
            [
              "/tezos/active_testing_protocol_versions";
              "/tezos/active_protocol_versions";
              "/tezos/poetry.lock";
              "/tezos/pyproject.toml";
              "/tezos/Makefile";
              "/tezos/dune";
              "/tezos/dune-project";
            ]
            ~dst:"./";
          (* TODO: copy the subset of /src that is actually useful *)
          copy ~from:(`Build "build_src") [ "/tezos/src" ] ~dst:"src";
          copy ~from:(`Build "build_src") [ "/tezos/vendors" ] ~dst:"vendors";
          copy ~from:(`Build "build_src") [ "/tezos/.git" ] ~dst:".git";
          copy ~from:(`Build "build_src")
            [ "/tezos/scripts/remove-old-protocols.sh" ]
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

let arm64 ~builder (analysis : Analysis.Tezos_repository.t Current.t) =
  Current.map v analysis
  |> Lib.Builder.build ~pool:Arm64 ~label:"build:arm64" builder

let x86_64 ~builder (analysis : Analysis.Tezos_repository.t Current.t) =
  Current.map v analysis
  |> Lib.Builder.build ~pool:X86_64 ~label:"build:x86_64" builder
