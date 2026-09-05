# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Result of Parser.call: `spec` is the ProviderSpec (nil when the spec was unusable).
    class ParseResult < Result
      def spec = value
    end
  end
end
