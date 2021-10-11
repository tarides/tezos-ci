module Git = Current_git

module Op = struct
  type t = No_context

  module Key = struct
    type t = Git.Commit.t

    let digest t = t |> Git.Commit.id |> Git.Commit_id.digest
  end

  module Value = Tezos_repository

  let id = "tezos-analyse"

  let pp f = Git.Commit.pp_short f

  let auto_cancel = true

  let build No_context job git =
    let open Lwt.Syntax in
    let* () = Current.Job.start ~level:Harmless job in
    Git.with_checkout ~job git @@ fun repo_path ->
    match Tezos_repository.make repo_path with
    | Ok value ->
        Current.Job.log job "Tezos_repository: %a"
          (Yojson.Safe.pretty_print ~std:true)
          (Tezos_repository.to_yojson value);
        Lwt.return_ok value
    | e -> Lwt.return e
end

module Analyse = Current_cache.Make (Op)

let v repo =
  let open Current.Syntax in
  Current.component "analyse repository"
  |> let> repo = repo in
     Analyse.get No_context repo
