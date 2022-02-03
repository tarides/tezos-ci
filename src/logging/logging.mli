val cmdliner : unit Cmdliner.Term.t

val run :
  (unit, [< `Msg of string ]) result Lwt.t -> (unit, [> `Msg of string ]) result
(** [run job] runs [job] with logs. *)
