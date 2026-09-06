# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Turns one flattened schema field plus its canonical mapping into the IR FieldMapping: plain
    # schema facts, no interpretation. The interpreted parts (conversion, conditional requirement)
    # are computed by their own analyzers and handed in.
    class FieldBuilder
      def initialize(context:, operation_id:, field:, mapping:)
        @context = context
        @operation_id = operation_id
        @field = field
        @mapping = mapping
      end

      # Models::FieldMapping for this field.
      def call(conversion: nil, conditional: nil)
        Models::FieldMapping.new(
          provider_path: field.path, required: field.required, conversion:, conditional_required: conditional,
          branch:, **schema_facts(field.schema), **limits(field.schema), **canonical
        )
      end

      private

      attr_reader :context, :operation_id, :field, :mapping

      # What the dictionary decided and why.
      def canonical
        { canonical: mapping.canonical, confidence: mapping.confidence, evidence: mapping.evidence,
          source: mapping.source }
      end

      def schema_facts(schema)
        { type: Parser::SchemaFacts.type(schema), format: schema["format"],
          nullable: Parser::SchemaFacts.nullable?(schema), enum: Parser::SchemaFacts.enum(schema),
          constant: Parser::SchemaFacts.constant(schema), description: Parser::SchemaFacts.description(schema),
          example: Parser::SchemaFacts.example(schema), default: schema["default"] }
      end

      def limits(schema)
        { pattern: schema["pattern"], minimum: schema["minimum"], maximum: schema["maximum"],
          min_length: schema["minLength"], max_length: schema["maxLength"] }
      end

      def branch
        return nil unless field.branch

        Models::Branch.new(discriminator_path: field.branch.discriminator_path, value: field.branch.value.to_s)
      end
    end
  end
end
