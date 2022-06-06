type task_metadata =
  { name : string
  ; skippable : bool
  }

type t =
  ( unit
  , ( Current_ocluster.Artifacts.t option
    , task_metadata )
    Current_web_pipelines.State.job_tree )
  Current_web_pipelines.Task.t

val all : name:string Current.t -> t list -> t

val skip : name:string -> string -> t

val list_iter :
     collapse_key:string
  -> (module Current_term.S.ORDERED with type t = 'a)
  -> ('a Current.t -> t)
  -> 'a list Current.t
  -> t

val allow_failures : t -> t

val single : name:string -> Current_ocluster.Artifacts.t option Current.t -> t

val single_c :
  name:string Current.t -> Current_ocluster.Artifacts.t option Current.t -> t
