let all ~builder:_ (_analysis : Analysis.Tezos_repository.t Current.t) =
  Task.empty ~name:"unittest:build_all"
