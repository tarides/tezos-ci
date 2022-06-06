val cmdliner : unit Cmdliner.Term.t

(** [run job] runs [job] with logs. *)
val run :
  (unit, [< `Msg of string ]) result Lwt.t -> (unit, [> `Msg of string ]) result
