# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Finds fields that are only required in some cases ("bank_code is required for type=sbp")
    # (docs/IR_CONTRACT.md 2.6). Structure states it plainly - if/then or a oneOf discriminator -
    # and prose only hints at it, so a rule read from a description keeps a lower confidence and
    # raises W402 while a structural one is merely recorded (I402).
    class ConditionalRequired
      # One conditional requirement of one field.
      Verdict = Struct.new(:when, :equals, :source, :confidence, :evidence, keyword_init: true)

      def initialize(dictionary: Dictionaries.fields)
        @config = dictionary.fetch("conditional_required")
      end

      # Resolves the requirement of one +field+ (Parser::SchemaExtractor::Field). +if_then+ is the
      # matching rule from the schema, +paths+ every field path of the same schema (to resolve the
      # condition name to a real sibling), +override+ an entry of overrides.yml.
      def call(field:, paths:, if_then: nil, override: nil)
        from_override(override) || from_if_then(if_then) || from_branch(field) || from_description(field, paths)
      end

      private

      attr_reader :config

      def confidences = config.fetch("confidence")

      def from_override(override)
        return nil unless override

        verdict(override[:when], override[:equals], "override",
                ["overrides.yml: required when #{override[:when]} = #{override[:equals]}"])
      end

      def from_if_then(rule)
        return nil unless rule

        verdict(rule[:when], rule[:equals], "if_then", ["if/then: #{rule[:when]} = #{rule[:equals]}"])
      end

      def from_branch(field)
        branch = field.branch
        return nil unless branch && field.required

        verdict(branch.discriminator_path, branch.value, "discriminator",
                ["discriminator #{branch.discriminator_path} = #{branch.value}"])
      end

      # The last resort: the provider wrote the rule in prose and nowhere else.
      def from_description(field, paths)
        text = Parser::SchemaFacts.description(field.schema)
        return nil if text.nil?

        match = first_match(text)
        return nil unless match

        verdict(resolve_when(match[:when], field.path, paths), match[:equals], "description",
                ["description: #{match[0]}"])
      end

      def first_match(text)
        config.fetch("description_patterns").each do |pattern|
          match = Regexp.new(pattern, Regexp::IGNORECASE).match(text)
          return match if match
        end
        nil
      end

      # "type" in "required for type=sbp" means the sibling field, not a top-level one; when the
      # schema has no such sibling the name stays exactly as the description wrote it (2.6), because
      # an invented path would be no more real than the name and harder to trace back to the prose.
      def resolve_when(name, path, paths)
        sibling = (path.split(".")[0..-2] + [name]).join(".")
        paths.include?(sibling) ? sibling : name
      end

      def verdict(condition, equals, source, evidence)
        Verdict.new(when: condition, equals: equals.to_s, source:, confidence: confidences.fetch(source), evidence:)
      end
    end
  end
end
