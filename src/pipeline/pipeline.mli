type source =
  | Schedule of Current_cache.Schedule.t
  | Branch of string
  | Tag of string
  | Merge_request of { from_branch : string; to_branch : string }

type t

val v : source -> Current_git.Commit_id.t Current.t -> t
val pipeline : builder:Lib.Builder.t -> t -> Stages.Task.t
