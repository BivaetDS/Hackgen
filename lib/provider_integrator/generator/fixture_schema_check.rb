# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Validates the fixture examples against JSON Schemas rebuilt from the IR fields
    # (TemplateData::FieldSchema): the create request, the successful responses and the webhook
    # payloads. Returns human-readable problems; an empty list means every example fits.
    class FixtureSchemaCheck
      SYNTHETIC_KEYS = %w[_synthetic _synthetic_fields].freeze

      def initialize(context, data)
        @context = context
        @data = data
      end

      def problems
        [*request_problems, *response_problems, *callback_problems]
      end

      private

      attr_reader :context, :data

      def request_problems
        operation = context.create_operation
        example = data.dig("create_request", "request")
        return [] unless operation && example

        validate("create_request.request", example, operation.request_fields)
      end

      def response_problems
        contract_entries.flat_map do |name, operation|
          operation.success_codes.flat_map do |code|
            example = data.dig(name, "response_#{code}")
            example ? validate("#{name}.response_#{code}", example, operation.response_fields) : []
          end
        end
      end

      def contract_entries
        [["create_request", context.create_operation], ["fetch_status", context.status_operation]]
          .select { |name, operation| operation && data[name] }
      end

      def callback_problems
        webhook = context.webhook
        return [] unless webhook

        data.select { |key, _| key.start_with?("callback") }.flat_map do |key, entry|
          validate("#{key}.payload", entry["payload"], webhook.payload_fields)
        end
      end

      def validate(name, example, fields)
        return [] if fields.empty? || !example.is_a?(Hash)

        schema = JSONSchemer.schema(TemplateData::FieldSchema.for(fields))
        schema.validate(example.except(*SYNTHETIC_KEYS)).map { |error| "#{name}: #{error["error"]}" }
      end
    end
  end
end
