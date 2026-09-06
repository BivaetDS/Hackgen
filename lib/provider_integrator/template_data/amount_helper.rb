# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The private amount helper a Conversion needs in the generated service: its name, the Ruby
    # body and the wording for INTEGRATION.md. `nil` for identity conversions (no helper).
    AmountHelper = Data.define(:name, :lines, :doc, :comment)

    # Reopened so the factory lives outside the Data.define block.
    class AmountHelper
      DECIMAL_PLACES = 2

      # The helper for +conversion+ (a Models::Conversion), or nil when the amount is passed as is.
      def self.for(conversion)
        case conversion.type
        when "multiply" then multiply(conversion.value)
        when "divide" then divide(conversion.value)
        when "to_decimal_string" then decimal_string
        end
      end

      def self.multiply(value)
        new(name: "amount_in_minor_units", lines: ["(amount * #{value}).round"],
            doc: "x #{value} (minor units)",
            comment: ["operation.amount is in major units; the provider expects minor units (x #{value}).",
                      "round (not to_i) keeps 10.15 * 100 from truncating to 1014 with Float amounts."])
      end

      def self.divide(value)
        new(name: "amount_in_major_units", lines: ["(amount / #{value}.to_r).round(#{DECIMAL_PLACES}).to_f"],
            doc: "/ #{value} (major units)",
            comment: ["operation.amount is in minor units; the provider expects major units (/ #{value})."])
      end

      def self.decimal_string
        new(name: "amount_as_decimal_string", lines: ["format('%.#{DECIMAL_PLACES}f', amount)"],
            doc: "as a decimal string with #{DECIMAL_PLACES} places",
            comment: ["The provider expects the amount as a decimal string with #{DECIMAL_PLACES} places."])
      end
    end
  end
end
