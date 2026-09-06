# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Decides whether a money field is in minor units (kopecks, cents) or major units, by scoring
    # independent signals from the description, the error examples and the schema facts
    # (docs/IR_CONTRACT.md 2.4). This is the inference most likely to be silently wrong by a factor
    # of 100, so it is always reported (I401) and, when the signals are thin, warned about (W401).
    class MoneyUnits
      # The unit decision for one field.
      Verdict = Struct.new(:unit, :type, :value, :confidence, :evidence, :scores, keyword_init: true) do
        # The multiplier the generated code applies (1 when no conversion is needed).
        def multiplier = value || 1
      end

      def initialize(dictionary: Dictionaries.fields)
        @config = dictionary.fetch("money_units")
      end

      # Scores one money field. +error_examples+ is [[http, example], ...] in response order,
      # +currency+ the ISO code when the spec pins it (used for the exponent).
      def call(field:, error_examples: [], currency: nil)
        signals = collect(field, error_examples)
        scores = { "minor" => sum(signals, :minor), "major" => sum(signals, :major) }
        decide(scores, signals.map { |item| item[1] }, field, currency)
      end

      # Minor units per major unit for +currency+ (ISO 4217 exponent), or the dictionary default.
      def exponent_for(currency)
        table = config.fetch("currency_exponents")
        table.fetch(currency.to_s.upcase, table.fetch("default"))
      end

      private

      attr_reader :config

      def minor = config.fetch("minor")
      def major = config.fetch("major")

      # [[unit, evidence, weight], ...] in the fixed order the IR contract prescribes.
      def collect(field, error_examples)
        schema = field.schema
        [description_signal(schema, :minor), error_example_signal(error_examples), minimum_signal(schema),
         description_signal(schema, :major), format_signal(schema), pattern_signal(schema),
         multiple_of_signal(schema), string_signal(schema)].compact
      end

      def sum(signals, unit) = signals.select { |item| item.first == unit }.sum(&:last)

      def description_signal(schema, unit)
        text = Parser::SchemaFacts.description(schema)
        settings = unit == :minor ? minor : major
        word = match_stem(text, settings.fetch("description_stems"))
        word && [unit, "description: #{word}", settings.fetch("description_weight")]
      end

      def error_example_signal(error_examples)
        error_examples.each do |http, example|
          next if example.nil?

          word = match_stem(JsonCanon.generate(example), minor.fetch("description_stems"))
          return [:minor, "error example (#{http}): #{word}", minor.fetch("error_example_weight")] if word
        end
        nil
      end

      def minimum_signal(schema)
        value = schema["minimum"]
        return nil unless value.is_a?(Numeric) && value.positive?
        return nil unless (value % minor.fetch("minimum_multiple_of")).zero? && value >= minor.fetch("minimum_at_least")

        [:minor, "minimum: #{format_number(value)}", minor.fetch("minimum_weight")]
      end

      def format_signal(schema)
        value = schema["format"]
        return nil unless value.is_a?(String) && major.fetch("format_stems").any? { |stem| value.downcase == stem }

        [:major, "format: #{value}", major.fetch("format_weight")]
      end

      def pattern_signal(schema)
        value = schema["pattern"]
        return nil unless value.is_a?(String) && major.fetch("pattern_stems").any? { |stem| value.include?(stem) }

        [:major, "pattern: #{value}", major.fetch("pattern_weight")]
      end

      def multiple_of_signal(schema)
        value = schema["multipleOf"]
        return nil unless value.is_a?(Numeric) && value < 1

        [:major, "multipleOf: #{format_number(value)}", major.fetch("multiple_of_fraction_weight")]
      end

      def string_signal(schema)
        return nil unless Parser::SchemaFacts.type(schema) == "string"

        [:major, "type: string", major.fetch("string_type_weight")]
      end

      def decide(scores, evidence, field, currency)
        confidence = Confidence.from_scores(scores)
        if minor_wins?(scores)
          minor_verdict(scores, evidence, confidence, currency)
        elsif major_wins?(scores)
          major_verdict(scores, evidence, confidence, field)
        else
          Verdict.new(unit: "unknown", type: "identity", value: 1, confidence:, evidence:, scores:)
        end
      end

      def minor_wins?(scores)
        scores["minor"] >= config.fetch("minor_threshold") && scores["minor"] > scores["major"]
      end

      def major_wins?(scores)
        scores["major"] >= config.fetch("major_threshold") && scores["major"] > scores["minor"]
      end

      def minor_verdict(scores, evidence, confidence, currency)
        Verdict.new(unit: "minor", type: "multiply", value: exponent_for(currency), confidence:, evidence:, scores:)
      end

      def major_verdict(scores, evidence, confidence, field)
        type = Parser::SchemaFacts.type(field.schema) == "string" ? "to_decimal_string" : "identity"
        Verdict.new(unit: "major", type:, value: nil, confidence:, evidence:, scores:)
      end

      def match_stem(text, stems) = Tokens.match_stem(text, stems)

      # 100000 stays "100000", 0.01 stays "0.01" (no Ruby float noise in evidence).
      def format_number(value)
        return value.to_s unless value.is_a?(Float)

        value == value.to_i ? value.to_i.to_s : value.to_s
      end
    end
  end
end
