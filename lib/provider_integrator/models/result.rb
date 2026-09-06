# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Outcome of a module boundary call: a value plus the events emitted while producing it.
    Result = Data.define(:value, :events) do
      include ResultPredicates
    end
  end
end
