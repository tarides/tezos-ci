module Artifacts = Artifacts
module Builder = Builder

module Task = struct
  include Task

  type maker = builder:Builder.t -> Analysis.Tezos_repository.t Current.t -> t
end

module Fetch = Fetch
