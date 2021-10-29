type t

val make_docker : t
val make_ocluster : [ `Docker | `Obuilder ] -> Current_ocluster.t -> t

type pool = Arm64 | X86_64

val build :
  ?pool:pool -> label:string -> t -> Obuilder_spec.t Current.t -> unit Current.t
