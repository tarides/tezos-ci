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
    Docker.build ~label ~pool ~pull:true ~dockerfile
end

module Ocluster_builder = struct
  let obuilder_build ~pool ~ocluster ~label spec src =
    let open Current.Syntax in
    let spec =
      let+ spec = spec in
      let spec_str = Fmt.to_to_string Obuilder_spec.pp spec in
      { Cluster_api.Obuilder_job.Spec.spec = `Contents spec_str }
    in
    let src =
      let+ src = src in
      [ Git.Commit.id src ]
    in
    Current_ocluster.build_obuilder ocluster ~label ~src ~pool spec

  let docker_build ~pool ~ocluster ~label spec src =
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
    let src =
      let+ src = src in
      [ Git.Commit.id src ]
    in
    Current_ocluster.build ocluster ~options ~label ~src ~pool (`Contents spec)
end

type mode =
  | Host_docker
  | Ocluster_docker of Current_ocluster.t
  | Ocluster_obuilder of Current_ocluster.t

type t = { source : Current_git.Commit.t Current.t; mode : mode }

let make_docker source = { source; mode = Host_docker }

let make_ocluster mode ocluster source =
  match mode with
  | `Docker -> { source; mode = Ocluster_docker ocluster }
  | `Obuilder -> { source; mode = Ocluster_obuilder ocluster }

type pool = Arm64 | X86_64

let pool_to_string = function
  | Arm64 -> "linux-arm64"
  | X86_64 -> "linux-x86_64"

(* TODO: default to host's pool *)
let build ?(pool = X86_64) ~label t spec =
  match t.mode with
  | Host_docker ->
      Docker_builder.build ~label spec (`Git t.source) |> Current.ignore_value
  | Ocluster_docker ocluster ->
      Ocluster_builder.docker_build ~pool:(pool_to_string pool) ~ocluster ~label
        spec t.source
  | Ocluster_obuilder ocluster ->
      Ocluster_builder.obuilder_build ~pool:(pool_to_string pool) ~ocluster
        ~label spec t.source
