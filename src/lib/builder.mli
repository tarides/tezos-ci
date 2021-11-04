type t

val make_docker : t
val make_ocluster : [ `Docker | `Obuilder ] -> Current_ocluster.t -> t

type pool = Arm64 | X86_64

val gate : gate:unit Current.t -> t -> t
val manual : t -> t

val build :
  ?context:Current_git.Commit_id.t Current.t ->
  ?pool:pool ->
  ?name:string Current.t ->
  label:string ->
  t ->
  Obuilder_spec.t Current.t ->
  Task.t
