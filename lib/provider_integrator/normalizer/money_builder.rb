# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Runs the money-unit analyzer for one field and reports what it decided. The unit is a critical
    # inference (a wrong one moves 100x the money), so it is reported every time (I401) and warned
    # about whenever the signals did not settle it (W401).
    class MoneyBuilder
      def initialize(context:, operation_id:, error_examples:, schema_name:)
        @context = context
        @operation_id = operation_id
        @error_examples = error_examples
        @schema_name = schema_name
      end

      # Models::Conversion for +field+, or nil when the caller should not convert at all.
      def call(field:, currency: nil)
        forced = context.overrides.amount_unit(schema_name, field.path)
        verdict = context.money_units.call(field:, error_examples:, currency:)
        verdict = force(verdict, forced, currency) if forced
        report(field, verdict, forced)
        conversion(verdict, forced)
      end

      private

      attr_reader :context, :operation_id, :error_examples, :schema_name

      def force(verdict, unit, currency)
        multiplier = unit == "minor" ? context.money_units.exponent_for(currency) : nil
        type = if unit == "minor"
                 "multiply"
               else
                 (verdict.type == "to_decimal_string" ? "to_decimal_string" : "identity")
               end
        MoneyUnits::Verdict.new(unit:, type:, value: multiplier, confidence: 1.0,
                                evidence: ["overrides.yml: amount_unit #{schema_name}.#{unit}"],
                                scores: verdict.scores)
      end

      def conversion(verdict, forced)
        Models::Conversion.new(type: verdict.type, value: verdict.value, unit_from: "major", unit_to: unit_to(verdict),
                               confidence: verdict.confidence, evidence: verdict.evidence,
                               source: forced ? "override" : "scoring")
      end

      def unit_to(verdict) = verdict.unit == "minor" ? "minor" : "major"

      def report(field, verdict, forced)
        score = verdict.scores.values.max
        context.log.add("I401", **decision(verdict), field: field.path, operation_id:, score:,
                                location: field.pointer)
        return if forced || verdict.unit != "unknown"

        context.log.add("W401", field: field.path, operation_id:, score:, location: field.pointer)
      end

      def decision(verdict)
        { unit: verdict.unit, multiplier: verdict.multiplier, signals: verdict.evidence }
      end
    end
  end
end
