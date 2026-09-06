# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The content of fixtures.json in the shape of the reference (docs/TZ.md): create_request
    # with its request and one response per declared HTTP status, fetch_status responses, one
    # callback entry per webhook example with the expected operation status, and the extra
    # methods. Examples come from the spec; whatever the spec does not give is synthesized by
    # type and marked "_synthetic": true (or "_synthetic_fields" when only some keys were added).
    class Fixtures
      SUCCESS_KINDS = %w[success idempotent_duplicate].freeze
      TYPE_DEFAULTS = { "integer" => 0, "number" => 0.0, "boolean" => false, "array" => [] }.freeze
      FORMAT_DEFAULTS = { "date-time" => "2026-01-01T00:00:00Z", "date" => "2026-01-01",
                          "uuid" => "00000000-0000-4000-8000-000000000000", "email" => "user@example.com",
                          "uri" => "https://example.com" }.freeze

      def initialize(context)
        @context = context
        @spec = context.spec
      end

      # Ordered Hash ready for JSON.pretty_generate.
      def to_h
        fixtures = contract_fixtures
        fixtures.merge!(callback_fixtures) if spec.webhook
        extra_names.each { |operation, name| fixtures[name] = operation_fixture(operation) }
        fixtures
      end

      private

      attr_reader :context, :spec

      def contract_fixtures
        [["create_request", context.create_operation], ["fetch_status", context.status_operation]]
          .select { |_, operation| operation }
          .to_h { |name, operation| [name, operation_fixture(operation)] }
      end

      def extra_names
        context.extra_operations.zip(context.service_data.extra_methods.map(&:name))
      end

      # { "request" => ..., "response_201" => ..., ... } in spec order.
      def operation_fixture(operation)
        entry = {}
        entry["request"] = request_example(operation) if operation.request_body
        operation.responses.each do |response|
          next if response.kind == "other"

          entry["response_#{response.http}"] = response_example(operation, response)
        end
        entry
      end

      # The declared example, completed with synthesized values for the required top-level fields
      # a partial example (composed from property examples) leaves out.
      def request_example(operation)
        synthesized = synthesize(operation.request_fields, branch: operation.request_methods&.default)
        example = operation.request_body.example
        return synthesized unless example.is_a?(Hash)

        complete(example, synthesized, required_top_level(operation.request_fields))
      end

      def required_top_level(fields)
        fields.select { |field| field.required && !field.provider_path.include?(".") }.map(&:provider_path)
      end

      def complete(example, synthesized, required)
        added = (required - example.keys).select { |name| synthesized.key?(name) }
        added.empty? ? example : example.merge(synthesized.slice(*added), "_synthetic_fields" => added)
      end

      def response_example(operation, response)
        return error_example(operation, response) if response.example.nil? && response.kind == "error"
        return response.example || {} unless SUCCESS_KINDS.include?(response.kind)

        with_status(operation, response.example || synthesize(operation.response_fields))
      end

      # A success example without the status field gets a status that maps to approved (fetch_status
      # fixtures must show a final state), marked as an added field.
      def with_status(operation, example)
        status = context.service_data.status_path(operation)
        return example unless status && example.is_a?(Hash) && !example.key?(status)

        field = operation.response_fields.find { |item| item.provider_path == status }
        value = approved_value(field) or return example
        example.merge(status => value, "_synthetic_fields" => [status])
      end

      def approved_value(field)
        return nil unless field&.enum

        approved = spec.statuses.find { |mapping| mapping.canonical == "approved" }
        field.enum.find { |value| value.to_s == approved&.provider } || field.enum.first
      end

      # Error body from the mapped code and the response description, shaped by the error code path.
      def error_example(operation, response)
        path = context.service_data.error_code_path || "error.code"
        body = nest(path.split("."), error_code_for(operation, response))
        message_path = path.sub(/code\z/, "message")
        body = deep_merge(body, nest(message_path.split("."), response.description.to_s)) if message_path != path
        body.merge("_synthetic" => true)
      end

      def error_code_for(operation, response)
        error = operation.errors.find { |item| item.http == response.http }
        error&.provider_code || error&.canonical || "error"
      end

      def nest(segments, value)
        segments.reverse.reduce(value) { |acc, segment| { segment => acc } }
      end

      def deep_merge(left, right)
        left.merge(right) { |_key, old, new| old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new }
      end

      # ---- callbacks -----------------------------------------------------------------------------

      def callback_fixtures
        callback_entries.each_with_object({}) do |(name, payload, synthetic), acc|
          status = callback_status(payload)
          key = callback_key(acc, name, status)
          acc[key] = { "payload" => payload, "expected_operation_status" => status || "unknown_event" }
          acc[key]["_synthetic"] = true if synthetic
        end
      end

      # [name, payload, synthetic?] per example, synthesized from the events when the spec has none.
      def callback_entries
        examples = spec.webhook.examples
        return examples.map { |name, payload| [name, payload, false] } unless examples.empty?

        synthesized_callbacks
      end

      def callback_key(acc, name, status)
        key = { "approved" => "callback", "rejected" => "callback_failed" }[status]
        key = "callback_#{Inflector.identifier(name)}" if key.nil? || acc.key?(key)
        key
      end

      # Canonical status the service will report for +payload+ (CallbackOutcome, shared with the spec).
      def callback_status(payload)
        CallbackOutcome.status(spec, payload)
      end

      # One payload per event value with a canonical status when the spec gives no examples.
      def synthesized_callbacks
        webhook = spec.webhook
        events = webhook.events.select(&:canonical_status)
        return [["notification", synthesize(webhook.payload_fields), true]] if events.empty? || !webhook.event_field

        events.map { |event| [Inflector.identifier(event.value.split(/[._-]/).last), event_payload(event), true] }
      end

      def event_payload(event)
        webhook = spec.webhook
        synthesize(webhook.payload_fields).merge(webhook.event_field => event.value)
      end

      # ---- synthesis -----------------------------------------------------------------------------

      # Nested Hash from flattened fields: example, default, constant, first enum value, then a
      # value by type; branch fields outside +branch+ are skipped; arrays get one synthesized item.
      def synthesize(fields, branch: nil)
        result = {}
        fields.each do |field|
          next if field.branch && branch && field.branch.value != branch
          next if field.type == "object" && !field.provider_path.include?("[]")

          place(result, field.provider_path.split("."), value_for(field))
        end
        result.merge("_synthetic" => true)
      end

      def place(node, segments, value)
        head, *rest = segments
        name = head.delete_suffix("[]")
        return place_leaf(node, name, value, array: head.end_with?("[]")) if rest.empty?

        child = head.end_with?("[]") ? (node[name] ||= [{}]).first : (node[name] ||= {})
        place(child, rest, value) if child.is_a?(Hash)
      end

      def place_leaf(node, name, value, array:)
        return if node.key?(name)

        node[name] = array ? [value] : value
      end

      def value_for(field)
        declared = [field.example, field.default, field.constant, field.enum&.first].find { |value| !value.nil? }
        return declared unless declared.nil?

        FORMAT_DEFAULTS[field.format] || type_default(field)
      end

      # Numbers respect the declared minimum so the value passes the schema; strings are "string".
      def type_default(field)
        return field.minimum if field.minimum && %w[integer number].include?(field.type)

        TYPE_DEFAULTS.fetch(field.type) { field.type == "object" ? {} : "string" }
      end
    end
  end
end
