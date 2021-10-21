val job :
  build:(label:string -> Obuilder_spec.t Current.t -> unit Current.t) ->
  Tezos_repository.t Current.t ->
  unit Current.t
(** [job ~build repository] Perform integration tests for the [repository] using
    [build] to execute the test specifications. *)
