# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Resolves local "$ref" pointers against the document root. External references are refused
    # (E008), missing targets reported (E005) and chains longer than MAX_HOPS treated as a cycle
    # (E006): a spec is untrusted input, so a self-referencing document must not hang the parser.
    class RefResolver
      MAX_HOPS = 32
      COMPONENT_ROOTS = %w[components definitions].freeze
      # A dereferenced node: +node+ is nil when the reference could not be resolved.
      Resolved = Struct.new(:node, :pointer, :schema_name, keyword_init: true)

      def initialize(root:, log:)
        @root = root
        @log = log
      end

      # True when +node+ is a "$ref" wrapper.
      def self.ref?(node) = node.is_a?(Hash) && node["$ref"].is_a?(String)

      # Follows every "$ref" starting at +node+ (addressed by +pointer+) and returns a Resolved.
      def resolve(node, pointer)
        name = nil
        seen = []
        hops = 0
        while self.class.ref?(node)
          reference = node["$ref"]
          unless hop_allowed?(reference, seen, hops, pointer)
            return Resolved.new(node: nil, pointer:, schema_name: name)
          end

          seen << reference
          hops += 1
          node = dig(reference, pointer) or return Resolved.new(node: nil, pointer: reference, schema_name: name)
          name = component_name(reference) || name
          pointer = reference
        end
        Resolved.new(node:, pointer:, schema_name: name)
      end

      # Convenience: the resolved node only (nil when unresolvable).
      def node(node, pointer) = resolve(node, pointer).node

      private

      attr_reader :root, :log

      def hop_allowed?(reference, seen, hops, pointer)
        unless Pointer.local?(reference)
          log.add("E008", ref: reference, location: pointer)
          return false
        end
        return true unless seen.include?(reference) || hops >= MAX_HOPS

        log.add("E006", ref: reference, limit: MAX_HOPS, location: pointer)
        false
      end

      def dig(reference, location)
        segments = Pointer.parse(reference)
        target = segments.reduce(root) do |node, segment|
          break nil unless node.is_a?(Hash) && node.key?(segment)

          node[segment]
        end
        return target unless target.nil?

        log.add("E005", ref: reference, location:)
        nil
      end

      def component_name(reference)
        segments = Pointer.parse(reference)
        return nil unless segments.size >= 2 && COMPONENT_ROOTS.include?(segments.first)

        segments.last
      end
    end
  end
end
