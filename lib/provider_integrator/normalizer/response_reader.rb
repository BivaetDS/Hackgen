# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Reads the "responses" object of one operation into the IR: the declared HTTP codes, what kind
    # of answer each is (success, idempotent duplicate, error, other), the example the fixtures will
    # use, the declared headers and, for error responses, the canonical error mapping.
    class ResponseReader
      DUPLICATE_CODE = 409
      # One response together with the flattened schema behind it (the error classifier needs both).
      Read = Struct.new(:model, :fields, :mappings, :pointer, keyword_init: true)

      def initialize(context:, operation:)
        @context = context
        @operation = operation
      end

      # [Read] in document order.
      def call
        @call ||= raw_entries.map { |entry| build(entry) }
      end

      # Models::Response list in document order.
      def responses = call.map(&:model)

      # The first success response, or nil.
      def first_success = call.find { |read| read.model.kind == "success" }

      # Codes that mean the request worked, ascending.
      def success_codes
        call.map(&:model).select { |model| %w[success idempotent_duplicate].include?(model.kind) }
            .map(&:http).sort
      end

      # Codes that mean "you already sent this", ascending.
      def duplicate_codes
        call.map(&:model).select { |model| model.kind == "idempotent_duplicate" }.map(&:http).sort
      end

      # Models::ErrorMapping for every error response, in document order.
      def errors
        call.select { |read| read.model.kind == "error" }.map { |read| error_mapping(read) }
      end

      private

      attr_reader :context, :operation

      def document = context.document
      def log = context.log

      def raw_entries
        node = operation.node["responses"]
        return [] unless node.is_a?(Hash)

        node.filter_map { |code, value| entry(code, value) }
      end

      def entry(code, value)
        resolved = document.deref(value, Parser::Pointer.join(operation.pointer, "responses", code.to_s))
        return nil unless resolved.node.is_a?(Hash)

        media_type, media = first_media(resolved.node)
        { code: code.to_s, http: http_of(code), node: resolved.node, pointer: resolved.pointer, media:, media_type:,
          kind: kind_of(code, media, resolved.pointer) }
      end

      def http_of(code) = code.to_s == "default" ? 0 : code.to_s.to_i

      def first_media(node)
        content = node["content"]
        return [nil, nil] unless content.is_a?(Hash) && !content.empty?

        content.first
      end

      # A response is only an idempotent duplicate if it answers with the same shape as the success.
      def kind_of(code, media, pointer)
        http = http_of(code)
        return "other" if code.to_s == "default" || http < 200
        return "success" if http < 300
        return "idempotent_duplicate" if http == DUPLICATE_CODE && duplicate?(media, pointer)

        http >= 400 ? "error" : "other"
      end

      def duplicate?(media, pointer)
        key = schema_key(media, pointer)
        !key.nil? && key == success_schema_key
      end

      def success_schema_key
        @success_schema_key ||= raw_success_entry&.then { |media, pointer| schema_key(media, pointer) }
      end

      # The first 2xx response as [media, pointer], computed without the duplicate check.
      def raw_success_entry
        node = operation.node["responses"]
        return nil unless node.is_a?(Hash)

        node.filter_map { |code, value| success_media(code, value) }.first
      end

      def success_media(code, value)
        return nil unless http_of(code).between?(200, 299)

        resolved = document.deref(value, Parser::Pointer.join(operation.pointer, "responses", code.to_s))
        [first_media(resolved.node).last, resolved.pointer] if resolved.node.is_a?(Hash)
      end

      def schema_key(media, pointer)
        schema = media.is_a?(Hash) ? media["schema"] : nil
        return nil unless schema

        name = context.extractor.schema_name(schema, Parser::Pointer.join(pointer, "schema"))
        name || JsonCanon.generate(document.deref(schema, pointer).node)
      end

      def build(entry)
        fields, mappings = schema_of(entry)
        model = Models::Response.new(
          http: entry[:http], description: text(entry[:node]["description"]), kind: entry[:kind],
          schema_name: schema_name(entry), content_type: entry[:media_type], example: example_of(entry),
          headers: headers_of(entry)
        )
        Read.new(model:, fields:, mappings:, pointer: entry[:pointer])
      end

      def schema_of(entry)
        schema = entry[:media].is_a?(Hash) ? entry[:media]["schema"] : nil
        return [[], {}] unless schema

        pointer = Parser::Pointer.join(media_pointer(entry), "schema")
        fields = context.extractor.call(schema, pointer)
        [fields, context.field_mapper.call(fields, context: "response", error_context: entry[:kind] == "error")]
      end

      def media_pointer(entry) = Parser::Pointer.join(entry[:pointer], "content", entry[:media_type].to_s)

      def schema_name(entry)
        schema = entry[:media].is_a?(Hash) ? entry[:media]["schema"] : nil
        schema && context.extractor.schema_name(schema, Parser::Pointer.join(media_pointer(entry), "schema"))
      end

      def example_of(entry)
        return nil unless entry[:media]

        context.composer.for_media(entry[:media], media_pointer(entry))
      end

      def headers_of(entry)
        headers = entry[:node]["headers"]
        return [] unless headers.is_a?(Hash)

        headers.filter_map { |name, value| header(name, value, entry[:pointer]) }
      end

      def header(name, value, pointer)
        resolved = document.deref(value, Parser::Pointer.join(pointer, "headers", name.to_s))
        return nil unless resolved.node.is_a?(Hash)

        Models::ResponseHeader.new(name: name.to_s, type: Parser::SchemaFacts.type(resolved.node["schema"] || {}),
                                   description: text(resolved.node["description"]), canonical: header_role(name))
      end

      def header_role(name)
        known = Dictionaries.errors.fetch("retry_after").fetch("headers")
        known.include?(Inflector.snake_case(name)) ? "retry_after" : nil
      end

      def error_mapping(read)
        verdict = classify(read)
        report_unknown(verdict, read.model.http, read)
        mapping(verdict, read)
      end

      def classify(read)
        body = ErrorClassifier::Body.of(example: read.model.example, fields: read.fields, mappings: read.mappings,
                                        headers: read.model.headers)
        context.error_classifier.call(http: read.model.http, response: body,
                                      override_actions: context.overrides.error_actions)
      end

      def mapping(verdict, read)
        Models::ErrorMapping.new(
          http: read.model.http, provider_code: verdict.provider_code, canonical: verdict.canonical,
          action: verdict.action, retry_after: verdict.retry_after, description: read.model.description,
          example: read.model.example, confidence: verdict.confidence, evidence: verdict.evidence,
          source: verdict.source
        )
      end

      def report_unknown(verdict, http, read)
        context.overrides.record_error_action(verdict.provider_code) if verdict.source == "override"
        return unless verdict.unknown_code

        log.add("W202", provider_code: verdict.provider_code, http:, canonical: verdict.canonical,
                        location: read.pointer)
      end

      def text(value)
        stripped = value.is_a?(String) ? value.strip : nil
        stripped unless stripped.nil? || stripped.empty?
      end
    end
  end
end
