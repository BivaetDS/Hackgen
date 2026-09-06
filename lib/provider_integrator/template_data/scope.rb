# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # What a payload is being built for: the payout method (+branch+, nil for a single-method
    # service), the Ruby expression that holds the payout method at run time, and the create
    # operation's amount conversion that other operations borrow when the spec says nothing.
    Scope = Data.define(:branch, :method_expression, :fallback_conversion)

    # Reopened so the defaults live outside the Data.define block.
    class Scope
      def self.build(branch: nil, method_expression: "request_method", fallback_conversion: nil)
        new(branch:, method_expression:, fallback_conversion:)
      end

      # The Ruby expression naming the payout method: a String literal for a branch, else the variable.
      def method_source = branch ? Code.str(branch) : method_expression
    end
  end
end
