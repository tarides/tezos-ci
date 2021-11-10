type 'a status =
  ( 'a,
    [ `Active of [ `Running | `Ready ]
    | `Msg of string
    | `Cancelled
    | `Blocked
    | `Skipped_failure
    | `Skipped of string ] )
  result

type subtask_value =
  | Item of
      (Current_ocluster.Artifacts.t option status * Current.Metadata.t option)
  | Stage of subtask_node list

and subtask_node =
  | Node of { name : string; value : subtask_value }
  | Failure_allowed of subtask_node

val sub_name : subtask_node -> string

val item :
  name:string ->
  ?metadata:Current.Metadata.t ->
  Current_ocluster.Artifacts.t option status ->
  subtask_node

val group : name:string -> subtask_node list -> subtask_node

type t = { current : unit Current.t; subtasks_status : subtask_node Current.t }

val v : unit Current.t -> subtask_node Current.t -> t
val single : name:string -> Current_ocluster.Artifacts.t option Current.t -> t

val single_c :
  name:string Current.t -> Current_ocluster.Artifacts.t option Current.t -> t

val status : subtask_node -> Current_ocluster.Artifacts.t option status

val list_iter :
  collapse_key:string ->
  (module Current_term.S.ORDERED with type t = 'a) ->
  ('a Current.t -> t) ->
  'a list Current.t ->
  t

val all : name:string Current.t -> t list -> t
val skip : name:string -> string -> t
val allow_failures : t -> t
