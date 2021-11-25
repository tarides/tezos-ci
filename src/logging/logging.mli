val init : ?level:Logs.level -> unit -> unit
(** [init ~level ()] setups logs with given [level] *)

val run :
  (unit, [< `Msg of string ]) result Lwt.t -> (unit, [> `Msg of string ]) result
(** [run job] runs [job] with logs. *)
