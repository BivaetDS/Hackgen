# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Checks that a loaded document is usable before any analyzer touches it: the sections the
    # pipeline needs exist, every local $ref resolves, and the structure matches the OpenAPI subset
    # schema. For 3.0 documents openapi3_parser cross-checks the full grammar. Every failure is an
    # E-event with the JSON pointer of the offending node, never a stack trace.
    class Validator
      MAX_REPORTED = 5

      def self.call(loaded:, log:) = new(loaded:, log:).call

      def initialize(loaded:, log:)
        @loaded = loaded
        @log = log
        @root = loaded.document
      end

      # True when the document can be analysed.
      def call
        return false unless sections?

        refs_ok = refs?
        structure_ok = structure?
        refs_ok && structure_ok && cross_check
      end

      private

      attr_reader :loaded, :log, :root

      def sections? = info? & paths?

      def info?
        return true unless root.dig("info", "title").to_s.strip.empty?

        log.add("E004")
        false
      end

      def paths?
        return true if root["paths"].is_a?(Hash) && !root["paths"].empty?

        log.add("E003")
        false
      end

      # Every "$ref" in the document, checked once, so a broken reference is reported at its own
      # location instead of surfacing later as a missing field.
      def refs?
        resolver = RefResolver.new(root:, log:)
        references(root, "#").all? do |node, pointer|
          !resolver.resolve(node, pointer).node.nil?
        end
      end

      def references(node, pointer, found = [])
        case node
        when Hash
          return found << [node, pointer] if node["$ref"].is_a?(String)

          node.each { |key, value| references(value, Pointer.join(pointer, key.to_s), found) }
        when Array
          node.each_with_index { |value, index| references(value, Pointer.join(pointer, index.to_s), found) }
        end
        found
      end

      def structure?
        errors = Schemas.errors(:openapi_document, root)
        return true if errors.empty?

        log.add("E009", reason: errors.first(MAX_REPORTED).join("; "))
        false
      end

      # openapi3_parser understands 3.0 in full; 3.1 support in 0.10 is partial, so it is not asked.
      def cross_check
        return true unless loaded.openapi.to_s.start_with?("3.0")

        cross_check_ok?(Openapi3Parser.load(root).errors)
      rescue StandardError => e
        log.add("E009", reason: one_line("#{e.class}: #{e.message}"))
        false
      end

      def cross_check_ok?(errors)
        return true if errors.empty?

        log.add("E009", reason: errors.errors.first(MAX_REPORTED).join("; "))
        false
      end

      def one_line(text) = text.to_s.tr("\n", " ")
    end
  end
end
