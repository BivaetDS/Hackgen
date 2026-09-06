# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # MIN_AMOUNT / MAX_AMOUNT of the generated service: the minimum/maximum of the create amount
    # field converted back into operation.amount units (the reference service compares
    # `operation.amount < 1000` for a minimum of 100000 kopecks).
    module AmountLimits
      Limit = Data.define(:name, :value, :comment, :evidence)
      LIMITS = [["MIN_AMOUNT", :minimum], ["MAX_AMOUNT", :maximum]].freeze

      module_function

      # Limits declared by the spec for the create +operation+, in constant order (empty when none).
      def for(operation, canon)
        field = operation&.request_fields&.find { |item| item.canonical == "amount" }
        return [] unless field

        LIMITS.filter_map do |name, key|
          raw = field.public_send(key)
          next if raw.nil?

          value = convert(raw, field.conversion)
          Limit.new(name:, value:, comment: comment(raw, value, key, field, canon), evidence: evidence(field, key))
        end
      end

      # Provider units -> operation.amount units through the inferred conversion.
      def convert(raw, conversion)
        return raw unless conversion&.value && conversion.value != 1

        case conversion.type
        when "multiply" then whole(Rational(raw, conversion.value))
        when "divide" then whole(Rational(raw) * conversion.value)
        else raw
        end
      end

      def whole(rational) = rational.denominator == 1 ? rational.numerator : rational.to_f

      def comment(raw, value, key, field, canon)
        unit = field.conversion&.unit_to || canon.amount_unit
        return "#{key} of #{field.provider_path}: #{raw} (#{unit} units)." if raw == value

        "#{key} of #{field.provider_path}: #{raw} in #{unit} units of the provider = #{value} in " \
          "#{canon.amount_unit} units of #{canon.accessor("amount")}."
      end

      # "Evidence: description: копейках; ..." for the check in check_conditions.
      def evidence(field, key)
        signals = field.conversion ? field.conversion.evidence : ["#{key}: #{field.public_send(key)}"]
        "Evidence: #{signals.join("; ")}"
      end
    end
  end
end
