module Op = struct
  let id = "tz-creation-date"

  type t = No_context

  module Key = Current.String

  module Value = struct
    type t = float

    let marshal = Float.to_string
    let unmarshal = Float.of_string
  end

  let pp f = Fmt.pf f "%s"
  let auto_cancel = false

  let build No_context job _ =
    let open Lwt.Syntax in
    let+ () = Current.Job.start job ~level:Harmless in
    Ok (Unix.gettimeofday ())
end

module Cache = Current_cache.Make (Op)

let get key =
  let open Current.Syntax in
  Current.component "creation date"
  |> let> key = key in
     Cache.get No_context key
