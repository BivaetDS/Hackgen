# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Assembles one Models::Operation: identity, parameters, request and response fields, responses
    # and the canonical error table. The classification arrives already decided (OperationClassifier)
    # and the contract role is assigned afterwards by SpecBuilder, because that choice needs to see
    # every operation at once.
    class OperationBuilder
      def initialize(context:, operation:, verdict:)
        @context = context
        @operation = operation
        @verdict = verdict
      end

      # Builds the IR operation. +kind+ overrides the scored verdict when an override or extension
      # named it; +source+ is where that decision came from.
      def call(kind: verdict.kind, source: verdict.source, confidence: verdict.confidence)
        @kind = kind
        Models::Operation.new(
          kind:, in_contract: false, canonical_method: nil, confidence:,
          classification: classification(kind, source, confidence), **identity, **payload, **answers
        )
      end

      # What the operation is: where it lives and who may call it.
      def identity
        { operation_id:, method: operation.verb, path: operation.path, tags:, security:, public: public?,
          summary: text(operation.node["summary"]), description: text(operation.node["description"]) }
      end

      # What the caller sends.
      def payload
        { idempotency:, parameters:, request_body:, request_fields:, request_methods: request_methods(@kind) }
      end

      # What the provider sends back.
      def answers
        { response_fields:, responses: reader.responses, success_codes: reader.success_codes,
          idempotent_duplicate_codes: reader.duplicate_codes, errors: reader.errors }
      end

      # The operationId as declared, or nil when the spec omitted it (never the synthesized one).
      def declared_operation_id = text(operation.node["operationId"])

      # True when the operation declares a request body with content.
      def body? = !body_media.nil?

      private

      attr_reader :context, :operation, :verdict

      def document = context.document
      def log = context.log

      def operation_id
        @operation_id ||= declared_operation_id || synthesize_id
      end

      def synthesize_id
        synthesized = Inflector.snake_case("#{operation.http_method}_#{operation.path.gsub(/[{}]/, "")}")
        log.add("I102", method: operation.verb, path: operation.path, operation_id: synthesized,
                        location: operation.pointer)
        synthesized
      end

      def tags = operation.node["tags"].is_a?(Array) ? operation.node["tags"].map(&:to_s) : []
      def security = context.authentication.requirements_for(operation)
      def public? = context.authentication.public?(operation)

      def classification(_kind, source, confidence)
        Models::Classification.new(confidence:, source:, scores: verdict.scores, evidence: verdict.evidence)
      end

      # ---- parameters --------------------------------------------------------------------------

      def parameters
        @parameters ||= document.parameters_for(operation).map { |node, pointer| parameter(node, pointer) }
      end

      def parameter(node, _pointer)
        schema = node["schema"].is_a?(Hash) ? node["schema"] : {}
        Models::Parameter.new(
          name: node["name"].to_s, in: node["in"].to_s, description: text(node["description"]),
          required: node["in"].to_s == "path" || node["required"] == true,
          canonical: parameter_canonical(node), **parameter_schema(node, schema)
        )
      end

      def parameter_schema(node, schema)
        { type: Parser::SchemaFacts.type(schema), format: schema["format"], enum: Parser::SchemaFacts.enum(schema),
          example: node.key?("example") ? node["example"] : Parser::SchemaFacts.example(schema) }
      end

      def parameter_canonical(node)
        return context.field_mapper.path_parameter_canonical(node["name"]) if node["in"].to_s == "path"

        context.field_mapper.parameter_role(node["name"])
      end

      def idempotency
        key = parameters.find { |parameter| parameter.canonical == "idempotency_key" }
        return nil unless key

        Models::Idempotency.new(location: key.in, name: key.name, required: key.required, format: key.format)
      end

      # ---- request body ------------------------------------------------------------------------

      def body_media
        @body_media ||= begin
          content = document.deref(operation.node["requestBody"], body_pointer).node&.fetch("content", nil)
          content.is_a?(Hash) && !content.empty? ? content.first : nil
        end
      end

      def body_pointer = Parser::Pointer.join(operation.pointer, "requestBody")

      def body_node = @body_node ||= document.deref(operation.node["requestBody"], body_pointer).node

      def media_pointer = Parser::Pointer.join(body_pointer, "content", body_media.first.to_s)

      def body_schema = body_media&.last.is_a?(Hash) ? body_media.last["schema"] : nil

      def schema_pointer = Parser::Pointer.join(media_pointer, "schema")

      def request_body
        return nil unless body_media

        Models::RequestBody.new(
          content_type: body_media.first.to_s, required: body_node["required"] == true,
          schema_name: body_schema && context.extractor.schema_name(body_schema, schema_pointer), **body_examples
        )
      end

      def body_examples
        media = body_media.last
        { example: context.composer.for_media(media, media_pointer),
          examples: context.composer.named_examples(media, media_pointer) }
      end

      # ---- fields ------------------------------------------------------------------------------

      def raw_request_fields
        @raw_request_fields ||= body_schema ? context.extractor.call(body_schema, schema_pointer) : []
      end

      # A callback body is not a request: "payout_id" there is the provider's id, not our reference.
      def request_mappings
        @request_mappings ||= context.field_mapper.call(raw_request_fields, context: body_context)
      end

      def body_context = @kind == "webhook" ? "webhook" : "request"

      def request_fields
        @request_fields ||= raw_request_fields.map { |field| request_field(field) }
      end

      def request_field(field)
        mapping = request_mappings.fetch(field.path)
        report_unmapped(field, mapping)
        FieldBuilder.new(context:, operation_id:, field:, mapping:).call(
          conversion: conversion_for(field, mapping), conditional: conditional_for(field)
        )
      end

      def report_unmapped(field, mapping)
        return if mapping.mapped? || !field.required

        log.add("W403", field: field.path, operation_id:, location: field.pointer)
      end

      def response_fields
        success = reader.first_success
        return [] unless success

        success.fields.map do |field|
          FieldBuilder.new(context:, operation_id:, field:, mapping: success.mappings.fetch(field.path)).call
        end
      end

      # ---- inferences --------------------------------------------------------------------------

      # Money units are decided only for the create operation: that is the request that moves money.
      def conversion_for(field, mapping)
        return nil unless @kind == "create" && mapping.canonical && context.field_mapper.money?(mapping.canonical)

        money_builder.call(field:, currency: currency_constant)
      end

      def money_builder
        @money_builder ||= MoneyBuilder.new(context:, operation_id:, error_examples:,
                                            schema_name: request_body&.schema_name)
      end

      # [[http, example], ...] for the error responses, in document order.
      def error_examples
        reader.responses.select { |response| response.kind == "error" }.map { |r| [r.http, r.example] }
      end

      def currency_constant
        field = raw_request_fields.find { |item| request_mappings[item.path]&.canonical == "currency" }
        field && Parser::SchemaFacts.constant(field.schema)
      end

      def conditional_for(field)
        verdict_conditional = context.conditional.call(
          field:, paths: raw_request_fields.map(&:path), if_then: if_then_for(field.path),
          override: context.overrides.required_if(field.path)
        )
        return nil unless verdict_conditional

        report_conditional(field, verdict_conditional)
        Models::ConditionalRequired.new(**verdict_conditional.to_h)
      end

      def if_then_for(path)
        @if_then ||= (body_schema ? context.extractor.if_then_rules(body_schema, schema_pointer) : [])
                     .to_h { |rule| [rule[:path], rule] }
        @if_then[path]
      end

      def report_conditional(field, found)
        details = { field: field.path, when: found.when, equals: found.equals, operation_id: }
        return log.add("W402", **details, location: field.pointer) if found.source == "description"

        log.add("I402", source: found.source, **details, location: field.pointer)
      end

      def request_methods(kind)
        return nil unless kind == "create"

        RequestMethodsBuilder.new(context:, fields: raw_request_fields, mappings: request_mappings,
                                  schema: body_schema, pointer: schema_pointer).call
      end

      def reader = @reader ||= ResponseReader.new(context:, operation:)

      def text(value)
        stripped = value.is_a?(String) ? value.strip : nil
        stripped unless stripped.nil? || stripped.empty?
      end
    end
  end
end
