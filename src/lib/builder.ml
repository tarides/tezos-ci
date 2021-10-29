module Git = Current_git
module Docker = Current_docker.Default

module Docker_builder = struct
  let pool = Current.Pool.create ~label:"docker build" 1

  let build ~label spec =
    let open Current.Syntax in
    let dockerfile =
      let _ = Bos.OS.Dir.create (Fpath.v "/tmp/tezos-ci") in
      let dockerfile =
        let+ spec = spec in
        Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
      in
      let path =
        let+ dockerfile = dockerfile in
        let hash = Digest.string dockerfile |> Digest.to_hex in
        Fpath.v (Fmt.str "/tmp/tezos-ci/Dockerfile.%s.tez" hash)
      in
      let+ () = Current_fs.save path dockerfile and+ path = path in
      `File path
    in
    Docker.build ~label ~pool ~pull:true ~dockerfile `No_context
end

module Ocluster_builder = struct
  let obuilder_build ~pool ~ocluster ~label spec =
    let open Current.Syntax in
    let spec =
      let+ spec = spec in
      let spec_str = Fmt.to_to_string Obuilder_spec.pp spec in
      { Cluster_api.Obuilder_job.Spec.spec = `Contents spec_str }
    in
    let src = Current.return [] in
    Current_ocluster.build_obuilder ocluster ~cache_hint:"tezos-ci" ~label ~src
      ~pool spec

  let docker_build ~pool ~ocluster ~label spec =
    let open Current.Syntax in
    let options =
      {
        Cluster_api.Docker.Spec.build_args = [];
        squash = false;
        buildkit = true;
        include_git = true;
      }
    in
    let spec =
      let+ spec = spec in
      Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
    in
    let src = Current.return [] in
    Current_ocluster.build ocluster ~cache_hint:"tezos-ci" ~options ~label ~src
      ~pool (`Contents spec)
end

type mode =
  | Host_docker
  | Ocluster_docker of Current_ocluster.t
  | Ocluster_obuilder of Current_ocluster.t

type t = mode

let make_docker = Host_docker

let make_ocluster mode ocluster =
  match mode with
  | `Docker -> Ocluster_docker ocluster
  | `Obuilder -> Ocluster_obuilder ocluster

type pool = Arm64 | X86_64

let pool_to_string = function
  | Arm64 -> "linux-arm64"
  | X86_64 -> "linux-x86_64"

(* TODO: default to host's pool *)
let build ?(pool = X86_64) ~label t spec =
  match t with
  | Host_docker -> Docker_builder.build ~label spec |> Current.ignore_value
  | Ocluster_docker ocluster ->
      Ocluster_builder.docker_build ~pool:(pool_to_string pool) ~ocluster ~label
        spec
  | Ocluster_obuilder ocluster ->
      Ocluster_builder.obuilder_build ~pool:(pool_to_string pool) ~ocluster
        ~label spec
