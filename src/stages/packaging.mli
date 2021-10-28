open Analysis

val job :
  build:(label:string -> Obuilder_spec.t Current.t -> unit Current.t) ->
  Tezos_repository.t Current.t ->
  unit Current.t
(** [job ~build repository] tests the tezos packaging for repository
    [repository]*)

val all : unit Current.t
