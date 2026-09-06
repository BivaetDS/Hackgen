# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Builds the webhook from an OpenAPI "callbacks" section when no operation looks like a webhook.
    # A callback is a declaration, not a hint, so the result carries full confidence - unlike a
    # webhook found because a path happens to contain "webhook".
    class CallbackReader
      SOURCE = "callbacks"

      def initialize(context:)
        @context = context
      end

      # Models::Webhook from the first declared callback, or nil when the spec declares none.
      def call
        context.document.operations.each do |owner|
          found = from_owner(owner)
          return found if found
        end
        nil
      end

      private

      attr_reader :context

      def document = context.document

      def from_owner(owner)
        callbacks = owner.node["callbacks"]
        return nil unless callbacks.is_a?(Hash)

        callbacks.each do |name, entry|
          found = from_entry(owner, name, entry)
          return found if found
        end
        nil
      end

      def from_entry(owner, name, entry)
        pointer = Parser::Pointer.join(owner.pointer, "callbacks", name.to_s)
        resolved = document.deref(entry, pointer)
        return nil unless resolved.node.is_a?(Hash)

        resolved.node.each do |expression, item|
          ref = operation_ref(expression, item, Parser::Pointer.join(resolved.pointer, expression.to_s))
          return build(ref, name, expression) if ref
        end
        nil
      end

      def operation_ref(expression, item, pointer)
        path_item = document.deref(item, pointer).node
        return nil unless path_item.is_a?(Hash)

        method = Parser::Document::HTTP_METHODS.find { |verb| path_item[verb].is_a?(Hash) }
        return nil unless method

        Parser::Document::OperationRef.new(path: expression.to_s, http_method: method, node: path_item[method],
                                           pointer: Parser::Pointer.join(pointer, method), path_item:)
      end

      def build(ref, name, expression)
        verdict = OperationClassifier::Verdict.new(
          kind: "webhook", confidence: 1.0, source: SOURCE, structural_only: false,
          scores: Dictionaries.operations.fetch("kinds").to_h { |kind| [kind, kind == "webhook" ? 1 : 0] },
          evidence: ["callbacks.#{name}: #{expression}"]
        )
        operation = OperationBuilder.new(context:, operation: ref, verdict:).call(kind: "webhook", source: SOURCE,
                                                                                  confidence: 1.0)
        WebhookAnalyzer.new(context:).call(operation:, ref:, source: SOURCE, confidence: 1.0)
      end
    end
  end
end
