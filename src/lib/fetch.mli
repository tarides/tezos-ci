val spec : Analysis.Tezos_repository.t -> Obuilder_spec.t
(** [spec repo] is the spec to create an image containing [repo] inside the
    /tezos folder. This image can be used for child builds. *)
