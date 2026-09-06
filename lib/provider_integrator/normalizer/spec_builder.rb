# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Assembles the whole ProviderSpec: classify every operation, hand out the contract roles, then
    # run the cross-cutting analyzers (authentication, statuses, webhook, gateway config) that need
    # to see the operations together. This is the only place that knows the order of the pipeline.
    class SpecBuilder
      ENVIRONMENTS = { "sandbox" => %w[sandbox test stag dev uat], "production" => %w[prod live] }.freeze

      def initialize(document:, log:, overrides:, loaded:)
        @document = document
        @log = log
        @overrides = overrides
        @loaded = loaded
        @context = Context.new(document:, log:, overrides:)
      end

      # The finished Models::ProviderSpec.
      def call
        roles = ContractRoles.new(log:)
        operations = roles.call(build_operations, refs)
        webhook = webhook_for(operations)
        roles.report_gaps(operations, webhook:)
        assemble(operations, webhook)
      end

      private

      attr_reader :document, :log, :overrides, :loaded, :context

      def refs = @refs ||= document.operations

      def builders
        @builders ||= refs.map do |ref|
          OperationBuilder.new(context:, operation: ref, verdict: verdict_for(ref))
        end
      end

      def verdict_for(ref)
        context.classifier.call(operation: ref, operation_id: declared_id(ref), has_body: body?(ref))
      end

      def declared_id(ref)
        value = ref.node["operationId"]
        value.is_a?(String) && !value.strip.empty? ? value.strip : nil
      end

      def body?(ref)
        content = document.deref(ref.node["requestBody"], Parser::Pointer.join(ref.pointer, "requestBody")).node
        content.is_a?(Hash) && content["content"].is_a?(Hash) && !content["content"].empty?
      end

      # An explicit statement in the spec beats the score; an override beats both.
      def build_operations
        builders.each_with_index.map do |builder, index|
          forced = forced_kind(refs[index], builder)
          forced ? builder.call(**forced) : builder.call
        end
      end

      def forced_kind(ref, builder)
        id = builder.declared_operation_id
        from_override = id && overrides.kind_for(id)
        return { kind: from_override, source: "override", confidence: 1.0 } if from_override

        extension = ref.node[Dictionaries.operations.fetch("extension_key")]
        return { kind: extension.to_s, source: "extension", confidence: 1.0 } if extension.is_a?(String)

        nil
      end

      def assemble(operations, webhook)
        statuses = status_mappings(operations, webhook)
        report_public_operations(operations)
        Models::ProviderSpec.new(
          ir_version: 1, provider:, spec_format:, servers:, authentication: authentication(operations),
          operations:, statuses:, webhook:, gateway_config: gateway_config(operations), events: log.sorted,
          overrides_applied: overrides.applied, extensions: document.extensions
        )
      end

      # ---- identity ----------------------------------------------------------------------------

      def provider
        Models::Provider.new(title: document.title.to_s, slug: slug, version: document.version.to_s,
                             description: document.description)
      end

      def slug
        token = document.title.to_s.split(/\s+/).first.to_s.downcase.gsub(/[^a-z0-9]/, "")
        token.empty? ? "provider" : token
      end

      def spec_format
        Models::SpecFormat.new(openapi: loaded.openapi.to_s, converted_from: loaded.swagger)
      end

      def servers
        declared = document.servers
        log.add("W104") if declared.empty?
        declared.map do |entry|
          Models::Server.new(url: entry["url"].to_s, description: entry["description"],
                             environment: environment_of(entry))
        end
      end

      def environment_of(entry)
        text = "#{entry["url"]} #{entry["description"]}".downcase
        ENVIRONMENTS.find { |_, stems| stems.any? { |stem| text.include?(stem) } }&.first || "unknown"
      end

      # ---- cross-cutting analyzers -------------------------------------------------------------

      def authentication(operations)
        usage = Hash.new(0)
        operations.each { |operation| operation.security.each { |scheme| usage[scheme] += 1 } }
        context.authentication.call(usage:, operation_count: operations.size)
      end

      def report_public_operations(operations)
        return unless operations.any? { |operation| !operation.security.empty? }

        operations.each do |operation|
          next unless operation.public && operation.kind != "webhook"

          log.add("W502", operation_id: operation.operation_id, method: operation.method, path: operation.path)
        end
      end

      def status_mappings(operations, webhook)
        values = status_values(operations, webhook)
        mappings = values.map { |value, description| mapping_for(value, description) }
        report_statuses(mappings)
        mappings
      end

      # { value => description of the enum it came from }, in order of first appearance.
      def status_values(operations, webhook)
        status_fields(operations, webhook).each_with_object({}) do |field, acc|
          field.enum.each { |value| acc[value.to_s] ||= field.description }
        end
      end

      def status_fields(operations, webhook)
        fields = operations.flat_map { |operation| operation.request_fields + operation.response_fields }
        fields += webhook.payload_fields if webhook
        fields.select { |field| field.canonical == "status" && field.enum }
      end

      def mapping_for(value, description)
        verdict = context.status_mapper.call(value, description:, override: overrides.status_for(value))
        report_status(verdict)
        Models::StatusMapping.new(provider: verdict.provider, canonical: verdict.canonical,
                                  confidence: verdict.confidence, source: verdict.source, evidence: verdict.evidence)
      end

      def report_status(verdict)
        case verdict.source
        when "default" then log.add("W201", status: verdict.provider, default: verdict.canonical)
        when "numeric_default" then log.add("W204", status: verdict.provider, canonical: verdict.canonical)
        end
      end

      def report_statuses(mappings)
        return if mappings.empty?

        log.add("I201", count: mappings.size, mapping: mappings.to_h { |m| [m.provider, m.canonical] })
      end

      def webhook_for(operations)
        index = operations.index { |operation| operation.kind == "webhook" && operation.in_contract }
        return declared_webhook(operations, index) if index

        CallbackReader.new(context:).call
      end

      def declared_webhook(operations, index)
        WebhookAnalyzer.new(context:).call(operation: operations[index], ref: refs[index])
      end

      def gateway_config(operations)
        create = operations.find { |operation| operation.kind == "create" && operation.in_contract }
        return nil unless create

        config = context.gateway.call(operation: create, fields: create.request_fields, title: document.title)
        report_gateway(config, create)
        config
      end

      def report_gateway(config, create)
        if config.evidence.last.end_with?("(default)")
          log.add("W405", operation_id: create.operation_id, direction: config.direction)
        end
        log.add("I403", external_method: config.external_method, gateway: config.gateway,
                        confidence: config.confidence, evidence: config.evidence)
      end
    end
  end
end
