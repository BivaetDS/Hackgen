# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Result of Generator.call: `files` is an Array of { "path" => ..., "sha256" => ... } Hashes.
    class GenerationResult < Result
      def files = value
    end
  end
end
