(* TODO This should be called Octez_pipeline *)

module Source : sig
  type t =
    | Schedule of Current_cache.Schedule.t
    | Branch of string
    | Tag of string
    | Merge_request of { from_branch : string; to_branch : string }

  val compare : t -> t -> int
  val to_string : t -> string
  val id : t -> string
  val marshal : t -> string
  val unmarshal : string -> t
  val link_to : t -> string

  module Map : Map.S with type key = t
end

open Current_web_pipelines

type metadata = { source : Source.t; commit : Current_git.Commit_id.t }

val v :
  builder:Lib.Builder.t ->
  Source.t ->
  Current_git.Commit_id.t Current.t ->
  ( unit,
    ( Current_ocluster.Artifacts.t option,
      Lib.Task.task_metadata,
      string,
      metadata )
    State.pipeline )
  Task.t
