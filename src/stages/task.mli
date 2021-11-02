type 'a status =
  ( 'a,
    [ `Active of [ `Running | `Ready ]
    | `Msg of string
    | `Cancelled
    | `Blocked
    | `Skipped of string ] )
  result

type subtask_value =
  | Item of (unit status * Current.Metadata.t option)
  | Stage of subtask_node list

and subtask_node = { name : string; value : subtask_value }

val item :
  name:string -> ?metadata:Current.Metadata.t -> unit status -> subtask_node

val group : name:string -> subtask_node list -> subtask_node

type t = { current : unit Current.t; subtasks_status : subtask_node Current.t }

val v : unit Current.t -> subtask_node Current.t -> t
val single : name:string -> unit Current.t -> t
val single_c : name:string Current.t -> unit Current.t -> t

type maker = builder:Lib.Builder.t -> Analysis.Tezos_repository.t Current.t -> t

val status : subtask_node -> unit status

val list_iter :
  collapse_key:string ->
  (module Current_term.S.ORDERED with type t = 'a) ->
  ('a Current.t -> t) ->
  'a list Current.t ->
  t

val all : name:string Current.t -> t list -> t
val skip : name:string -> string -> t
