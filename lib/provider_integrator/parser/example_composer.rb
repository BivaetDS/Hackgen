# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Picks the example the IR stores for a request body or a response (docs/IR_CONTRACT.md 2.12):
    # the media example, else the first named example, else the schema example, else a value composed
    # from the property examples. It never invents a value from a type - that is the fixtures
    # generator's job, and it marks what it invented.
    class ExampleComposer
      MAX_DEPTH = 8

      def initialize(document)
        @document = document
      end

      # The example for one media-type object ({"schema" =>, "example" =>, "examples" =>}), or nil.
      def for_media(media, pointer)
        return nil unless media.is_a?(Hash)

        return media["example"] if media.key?("example")

        named = named_examples(media, pointer)
        return named.values.first unless named.empty?

        schema = media["schema"]
        schema.nil? ? nil : for_schema(schema, Pointer.join(pointer, "schema"))
      end

      # { name => value } for every entry of "examples", in document order.
      def named_examples(media, pointer)
        examples = media.is_a?(Hash) ? media["examples"] : nil
        return {} unless examples.is_a?(Hash)

        examples.filter_map { |name, node| named_example(name, node, pointer) }.to_h
      end

      # The schema's own example, else a value composed from its properties, else nil.
      def for_schema(schema, pointer, depth = 0)
        resolved = document.deref(schema, pointer)
        node = resolved.node
        return nil unless node.is_a?(Hash) && depth <= MAX_DEPTH

        declared = SchemaFacts.example(node)
        return declared unless declared.nil?

        compose(node, resolved.pointer, depth)
      end

      private

      attr_reader :document

      def named_example(name, node, pointer)
        resolved = document.deref(node, Pointer.join(pointer, "examples", name.to_s))
        return nil unless resolved.node.is_a?(Hash) && resolved.node.key?("value")

        [name.to_s, resolved.node["value"]]
      end

      def compose(node, pointer, depth)
        merged = extractor.flatten(node, pointer)
        return compose_object(merged, pointer, depth) if merged["properties"].is_a?(Hash)
        return compose_array(merged, pointer, depth) if SchemaFacts.array?(merged)

        scalar(merged)
      end

      def compose_object(node, pointer, depth)
        composed = node["properties"].filter_map do |name, child|
          value = for_schema(child, Pointer.join(pointer, "properties", name.to_s), depth + 1)
          [name.to_s, value] unless value.nil?
        end.to_h
        composed.empty? ? nil : composed
      end

      def compose_array(node, pointer, depth)
        items = node["items"]
        return nil unless items.is_a?(Hash)

        value = for_schema(items, Pointer.join(pointer, "items"), depth + 1)
        value.nil? ? nil : [value]
      end

      def scalar(node)
        constant = SchemaFacts.constant(node)
        return constant unless constant.nil?

        node["default"]
      end

      def extractor = @extractor ||= SchemaExtractor.new(document)
    end
  end
end
