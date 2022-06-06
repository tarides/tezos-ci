module Active_protocol : sig
  type t =
    { name : string
    ; folder_name : string
    ; id : string
    ; slow_tests : string list
    }

  val pp : t Fmt.t

  val compare : t -> t -> int
end

module Version : sig
  type t =
    { build_deps_image_version : string
    ; recommended_node_version : string
    }
end

type t =
  { commit : Current_git.Commit_id.t
  ; all_protocols : string list
        (** List of /src/proto_* in the source folder *)
  ; active_protocols : Active_protocol.t list
        (** Active protocols according to the /active_protocol_versions file *)
  ; active_testing_protocol_versions : string list
        (** Active_testing_protocol_versions according to the
            /active_testing_protocol_versions file *)
  ; lib_packages : string list  (** List of library packages *)
  ; bin_packages : string list  (** List of binary packages *)
  ; version : Version.t  (** Content of /scripts/version.sh *)
  }

(** [make path] Explore the content of the repository checked out in [path] and
    gather all required metadata. *)
val make :
  commit:Current_git.Commit_id.t -> Fpath.t -> (t, [ `Msg of string ]) result

val to_yojson : t -> Yojson.Safe.t

val marshal : t -> string

val unmarshal : string -> t
