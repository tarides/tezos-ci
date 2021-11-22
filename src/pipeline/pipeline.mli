module Source : sig
  type t =
    | Schedule of Current_cache.Schedule.t
    | Branch of string
    | Tag of string
    | Merge_request of { from_branch : string; to_branch : string }

  val pp : t Fmt.t
  val compare : t -> t -> int
  val to_string : t -> string
  val of_string : string -> t
  val link_to : t -> string

  module Map : Map.S with type key = t
end

type t

val v : Source.t -> Current_git.Commit_id.t Current.t -> t
val pipeline : builder:Lib.Builder.t -> t -> Lib.Task.t
