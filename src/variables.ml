let build_deps_image_version = "cc92c90ff41b9dfb7cbbce981d3b16b5dc77be68"

let build_deps_image_name = "registry.gitlab.com/tezos/opam-repository"

let public_docker_image_name = "docker.io/tezos/tezos-"

let image_template__runtime_build_test_dependencies_template =
  Fmt.str "%s:runtime-build-test-dependencies--%s" build_deps_image_name
    build_deps_image_version

let image_template__runtime_build_dependencies_template =
  Fmt.str "%s:runtime-build-dependencies--%s" build_deps_image_name
    build_deps_image_version
