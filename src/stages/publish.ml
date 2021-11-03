open Lib

let build_release ~builder:_ _ =
  Task.skip ~name:"build_release" "not implemented"

let publish_release ~builder:_ _ =
  Task.skip ~name:"publish_release" "not implemented"

let documentation ~builder:_ _ =
  Task.skip ~name:"documentation" "not implemented"
