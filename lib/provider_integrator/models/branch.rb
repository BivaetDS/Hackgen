# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # The oneOf/anyOf variant a field belongs to, keyed by discriminator path and value.
    Branch = Data.define(:discriminator_path, :value) do
      include Base
    end
  end
end
