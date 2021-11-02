let build_release ~builder:_ _ =
  Task.empty ~name:"build_release"

let publish_release ~builder:_ _ =
  Task.empty ~name:"publish_release"

let documentation ~builder:_ _ =
  Task.empty ~name:"documentation"
