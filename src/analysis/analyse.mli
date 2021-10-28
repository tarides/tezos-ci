val v : Current_git.Commit.t Current.t -> Tezos_repository.t Current.t
(** [v commit] inspects the content of the repository checked out at [commit]
    and extract informations for the next stages of the pipeline. *)
