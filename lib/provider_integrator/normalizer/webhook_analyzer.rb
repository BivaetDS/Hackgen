# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Describes the inbound notification endpoint: where it is, what its payload means and how it is
    # signed (docs/IR_CONTRACT.md 2.9). A spec may declare it properly through "callbacks" or only
    # hint at it with a path like /webhooks/payout; the IR records which, because a heuristic find
    # deserves less trust than a declaration.
    class WebhookAnalyzer
      HEURISTICS = { "path token" => "path_heuristic", "tag " => "tag_heuristic",
                     "operationId token" => "operation_id_heuristic" }.freeze
      MIN_EVIDENCE = 2

      def initialize(context:)
        @context = context
      end

      # Builds Models::Webhook from the built +operation+ and its raw +ref+. +source+ overrides the
      # heuristic label ("callbacks" when the spec declared the callback properly).
      def call(operation:, ref:, source: nil, confidence: nil)
        signature = signature_for(operation)
        report(operation, ref, source, signature)
        Models::Webhook.new(
          path: operation.path, method: operation.method, operation_id: operation.operation_id,
          summary: operation.summary, source: source || heuristic(operation), confidence: confidence ||
            operation.confidence, evidence: operation.classification.evidence, signature:,
          **payload_roles(operation), payload_fields: operation.request_fields,
          examples: examples(operation), response: response(operation)
        )
      end

      private

      attr_reader :context

      def log = context.log
      def webhook_dictionary = Dictionaries.fields.fetch("webhook")

      # Which signal found the endpoint; the strongest one that actually fired.
      def heuristic(operation)
        evidence = operation.classification.evidence
        HEURISTICS.each do |prefix, label|
          return label if evidence.any? { |line| line.start_with?(prefix) }
        end
        "path_heuristic"
      end

      def report(operation, ref, source, signature)
        report_weak_evidence(operation, ref, source)
        return unless signature

        where = signature_location(operation, ref, signature)
        log.add("I301", name: signature.name, placement: signature.location, algorithm: signature.algorithm,
                        encoding: signature.encoding, message: signature.message, secret: signature.secret,
                        location: where)
        report_unspecified(signature, where)
      end

      # A header signature is declared by a parameter, so the event points at that parameter.
      def signature_location(operation, ref, signature)
        index = operation.parameters.index { |item| item.name == signature.name }
        index ? Parser::Pointer.join(ref.pointer, "parameters", index.to_s) : ref.pointer
      end

      def report_weak_evidence(operation, ref, source)
        return if source
        return if operation.classification.evidence.size >= MIN_EVIDENCE

        log.add("W302", method: operation.method, path: operation.path, heuristic: heuristic(operation),
                        location: ref.pointer)
      end

      def report_unspecified(signature, where)
        return unless signature.encoding == "unknown" || signature.message == "unknown"

        defaults = context.signature_analyzer.defaults
        log.add("W301", name: signature.name, encoding: signature.encoding, message: signature.message,
                        default_encoding: defaults.fetch("encoding"), default_message: defaults.fetch("message"),
                        location: where)
      end

      # ---- signature ---------------------------------------------------------------------------

      def signature_for(operation)
        source = signature_source(operation)
        context.signature_analyzer.call(source:, summary: operation.summary, description: operation.description,
                                        override: context.overrides.signature)
      end

      def signature_source(operation)
        parameter = operation.parameters.find { |item| item.canonical == "signature" }
        return parameter_source(parameter) if parameter

        field = operation.request_fields.find { |item| signature_field?(item) }
        field && field_source(field)
      end

      def parameter_source(parameter)
        SignatureAnalyzer::Source.new(location: parameter.in, name: parameter.name,
                                      label: "parameter #{parameter.name} (#{parameter.in})",
                                      description: parameter.description, source: "parameter")
      end

      def field_source(field)
        SignatureAnalyzer::Source.new(location: "body", name: field.provider_path,
                                      label: "field #{field.provider_path}", description: field.description,
                                      source: "field")
      end

      def signature_field?(field)
        return false if field.provider_path.include?(".")

        patterns = webhook_dictionary.fetch("signature_field")
        tokens = Tokens.identifier(field.provider_path)
        snake = Inflector.snake_case(field.provider_path)
        patterns.any? do |pattern|
          if pattern.include?("_")
            snake == pattern
          else
            tokens.any? do |t|
              t.start_with?(pattern)
            end
          end
        end
      end

      # ---- payload roles -----------------------------------------------------------------------

      def payload_roles(operation)
        fields = operation.request_fields
        event = role_field(fields, webhook_dictionary.fetch("event_field"))
        { event_field: event&.provider_path, events: events(event),
          status_field: role_field(fields, webhook_dictionary.fetch("status_field"), exclude: status_exclusions)
                        &.provider_path,
          id_field: canonical_field(fields, "provider_operation_id"),
          external_id_field: canonical_field(fields, "external_id"),
          error_code_path: canonical_field(fields, "error.code"),
          error_message_path: canonical_field(fields, "error.message") }
      end

      def status_exclusions = Array(Dictionaries.fields.dig("canonical", "status", "exclude"))

      # The best candidate for a role: dictionary order first, then top-level before nested.
      def role_field(fields, names, exclude: [])
        ranked = fields.filter_map do |field|
          name = Inflector.snake_case(field.provider_path.split(".").last)
          next if exclude.include?(name)

          index = names.index(name)
          [index, field.provider_path.count("."), field] if index
        end
        ranked.min_by { |index, depth, _| [index, depth] }&.last
      end

      def canonical_field(fields, canonical)
        fields.select { |field| field.canonical == canonical }
              .min_by { |field| field.provider_path.count(".") }&.provider_path
      end

      def events(field)
        return [] unless field&.enum

        field.enum.map { |value| event(value) }
      end

      def event(value)
        verdict = context.status_mapper.for_event(value)
        unless verdict
          log.add("W203", value:)
          return Models::WebhookEvent.new(value: value.to_s, canonical_status: nil, confidence: 0.0, source: "none")
        end

        Models::WebhookEvent.new(value: value.to_s, canonical_status: verdict.canonical,
                                 confidence: verdict.confidence, source: verdict.source)
      end

      # ---- payload examples and the answer -----------------------------------------------------

      def examples(operation)
        body = operation.request_body
        return {} unless body
        return body.examples unless body.examples.empty?

        body.example.nil? ? {} : { "default" => body.example }
      end

      def response(operation)
        success = operation.responses.find { |item| item.kind == "success" }
        return nil unless success

        Models::WebhookResponse.new(http: success.http, example: success.example)
      end
    end
  end
end
