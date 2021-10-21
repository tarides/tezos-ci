let build_deps_image_name = "registry.gitlab.com/tezos/opam-repository"

let docker_image_runtime_build_test_dependencies version =
  Fmt.str "%s:runtime-build-test-dependencies--%s" build_deps_image_name
    version.Tezos_repository.Version.build_deps_image_version
