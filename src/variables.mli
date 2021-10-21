val docker_image_runtime_build_test_dependencies :
  Tezos_repository.Version.t -> string
(** [docker_image_runtime_build_test_dependencies repo_version] is the docker
    image to pull to build Tezos' repository test for version [repo_version]*)
