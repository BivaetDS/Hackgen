# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Ruby expression for an operation URL: "#{BASE_URL}/payouts/#{operation.provider_operation_id}".
    # Path parameters are resolved through their canonical role; anything else becomes nil with a
    # TODO so the gap is visible in the generated code and in the report.
    class Url
      PARAM = /\{([^}]+)\}/
      MERCHANT_STEMS = %w[merchant shop terminal account project].freeze

      def initialize(operation, canon:)
        @operation = operation
        @canon = canon
        @comments = []
      end

      # The interpolated URL literal (double-quoted Ruby String).
      def expression
        path = @operation.path.gsub(PARAM) { "\#{#{param_expression(Regexp.last_match(1))}}" }
        "\"\#{BASE_URL}#{path}\""
      end

      # Comment lines for parameters that have no platform source (filled by #expression).
      def comments
        expression
        @comments.uniq
      end

      # True when the URL needs the operation object.
      def operation?
        expression.include?("operation.")
      end

      private

      def param_expression(name)
        parameter = @operation.parameters.find { |item| item.in == "path" && item.name == name }
        case parameter&.canonical
        when "provider_operation_id", "external_id" then @canon.accessor(parameter.canonical)
        else unresolved(name)
        end
      end

      def unresolved(name)
        tokens = Inflector.snake_case(name).split("_")
        if tokens.intersect?(MERCHANT_STEMS)
          @canon.credential(@canon.merchant_account_key)
        else
          @comments << Generator::Confidence.todo(0.0, "path parameter {#{name}} has no platform source")
          "nil"
        end
      end
    end
  end
end
