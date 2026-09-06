# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The private amount helper a Conversion needs in the generated service: its name, the Ruby
    # body and the wording for INTEGRATION.md. `nil` for identity conversions (no helper).
    AmountHelper = Data.define(:name, :lines, :doc, :comment)

    # Reopened so the factory and the arithmetic live outside the Data.define block. `apply` and
    # `reverse` are the same arithmetic as `lines`, evaluated at generation time: the generated
    # spec builds operation.amount out of a provider-side fixture value with `reverse` and expects
    # the service to send `apply` of it back, so both directions live in one place.
    class AmountHelper
      DECIMAL_PLACES = 2

      class << self
        # The helper for +conversion+ (a Models::Conversion), or nil when the amount is passed as is.
        def for(conversion)
          case conversion.type
          when "multiply" then multiply(conversion.value)
          when "divide" then divide(conversion.value)
          when "to_decimal_string" then decimal_string
          end
        end

        # What the service sends for operation.amount +value+ under +conversion+ (nil = identity).
        def apply(conversion, value)
          case conversion&.type
          when "multiply" then (value * conversion.value).round
          when "divide" then (value / conversion.value.to_r).round(DECIMAL_PLACES).to_f
          when "to_decimal_string" then format("%.#{DECIMAL_PLACES}f", value)
          else value
          end
        end

        # operation.amount for a provider-side +value+ (a fixture): the inverse of #apply, an Integer
        # when the result is whole, else a Float. Non-numeric input returns nil.
        def reverse(conversion, value)
          amount = Rational(value.to_s)
          case conversion&.type
          when "multiply" then whole(amount / conversion.value)
          when "divide" then whole(amount * conversion.value)
          else whole(amount)
          end
        rescue ArgumentError, ZeroDivisionError, TypeError
          nil
        end

        def multiply(value)
          new(name: "amount_in_minor_units", lines: ["(amount * #{value}).round"],
              doc: "x #{value} (minor units)",
              comment: ["operation.amount is in major units; the provider expects minor units (x #{value}).",
                        "round (not to_i) keeps 10.15 * 100 from truncating to 1014 with Float amounts."])
        end

        def divide(value)
          new(name: "amount_in_major_units", lines: ["(amount / #{value}.to_r).round(#{DECIMAL_PLACES}).to_f"],
              doc: "/ #{value} (major units)",
              comment: ["operation.amount is in minor units; the provider expects major units (/ #{value})."])
        end

        def decimal_string
          new(name: "amount_as_decimal_string", lines: ["format('%.#{DECIMAL_PLACES}f', amount)"],
              doc: "as a decimal string with #{DECIMAL_PLACES} places",
              comment: ["The provider expects the amount as a decimal string with #{DECIMAL_PLACES} places."])
        end

        private

        def whole(rational) = rational.denominator == 1 ? rational.numerator : rational.to_f
      end
    end
  end
end
