# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Finds the payout methods a create operation supports (docs/IR_CONTRACT.md 2.5). Experts
    # confirmed that request_method is the payment method, not the HTTP verb, so this list is what
    # the generated create_request branches on. Three shapes cover real specs: an enum on the
    # requisite type, a oneOf discriminator, or a bare oneOf of named variants.
    class RequestMethodsBuilder
      def initialize(context:, fields:, mappings:, schema:, pointer:)
        @context = context
        @fields = fields
        @mappings = mappings
        @schema = schema
        @pointer = pointer
      end

      # Models::RequestMethods, or nil when the spec offers only one way to pay out.
      def call
        found = from_enum || from_variants
        return nil unless found && !found[:values].empty?

        Models::RequestMethods.new(discriminator_path: found[:discriminator_path], values: found[:values],
                                   default: found[:values].first, source: found[:source],
                                   confidence: confidences.fetch(found[:source]))
      end

      private

      attr_reader :context, :fields, :mappings, :schema, :pointer

      def confidences = Dictionaries.fields.fetch("request_methods").fetch("confidence")

      def from_enum
        field = fields.find { |item| mappings[item.path]&.canonical == "requisite.type" }
        values = field && Parser::SchemaFacts.enum(field.schema)
        return nil unless values

        { discriminator_path: field.path, values: values.map(&:to_s), source: "enum" }
      end

      def from_variants
        return nil unless schema

        found = context.extractor.variants(schema, pointer)
        return nil unless found

        { discriminator_path: found[:discriminator_path], values: found[:values].map(&:to_s),
          source: found[:source] }
      end
    end
  end
end
