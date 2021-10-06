let build_deps_image_version = "575231db53bcfa44c5c55020a1aabaae745a1e59"

let build_deps_image_name = "registry.gitlab.com/tezos/opam-repository"

let public_docker_image_name = "docker.io/tezos/tezos-"

let image_template__runtime_build_test_dependencies_template =
  Fmt.str "%s:runtime-build-test-dependencies--%s" build_deps_image_name
    build_deps_image_version

let image_template__runtime_build_dependencies_template =
  Fmt.str "%s:runtime-build-dependencies--%s" build_deps_image_name
    build_deps_image_version
