# frozen_string_literal: true

module ProviderIntegrator
  # Maintenance of spec/golden/<spec>/ (byte-exact expected outputs). Driven by `rake golden:update`.
  module Golden
    # Regenerates every golden directory from the current generator output.
    def self.update!
      raise NotImplementedError, "golden regeneration arrives with the generator in wave 1/2"
    end
  end
end
