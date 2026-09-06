# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Reads an OpenAPI/Swagger document from disk. The spec is untrusted input: the file is size
    # limited, parsed with Psych.safe_load (no aliases, no custom classes), depth limited, and the
    # declared version is checked before anything else looks at the content.
    class Loader
      MAX_BYTES = 5 * 1024 * 1024
      MAX_DEPTH = 100
      SUPPORTED_MAJORS = %w[2.0 3.0 3.1].freeze
      # What Loader hands to the rest of the parser: the raw document plus its declared format.
      Loaded = Struct.new(:document, :openapi, :swagger, keyword_init: true) do
        # True when the document still has to be converted from Swagger 2.0.
        def swagger2? = !swagger.nil?
      end

      # Reads +path+ and returns a Loaded, or nil after recording E001/E002/E007.
      def self.call(path:, log:) = new(path:, log:).call

      def initialize(path:, log:)
        @path = path
        @log = log
      end

      # Reads, parses and version-checks the document.
      def call
        content = read or return nil
        document = parse(content) or return nil
        return nil unless shape_ok?(document) && depth_ok?(document)

        version(document)
      end

      private

      attr_reader :path, :log

      def read
        unless File.file?(path)
          log.add("E001", reason: "#{path} is not a readable file")
          return nil
        end

        size = File.size(path)
        return Files.read(path) if size <= MAX_BYTES

        log.add("E007", reason: "file is #{size} bytes, limit is #{MAX_BYTES}")
        nil
      end

      def parse(content)
        Psych.safe_load(content, permitted_classes: [], aliases: false, filename: path)
      rescue Psych::AliasesNotEnabled
        log.add("E007", reason: "YAML aliases are not supported (a spec may not reference itself)")
        nil
      rescue Psych::Exception => e
        log.add("E001", reason: e.message.to_s.tr("\n", " "))
        nil
      end

      def shape_ok?(document)
        return true if document.is_a?(Hash)

        log.add("E001", reason: "document root is #{document.class}, expected a mapping")
        false
      end

      def depth_ok?(document)
        depth = depth_of(document)
        return true if depth <= MAX_DEPTH

        log.add("E007", reason: "document nests #{depth} levels, limit is #{MAX_DEPTH}")
        false
      end

      def depth_of(node, level = 1)
        case node
        when Hash then node.values.map { |value| depth_of(value, level + 1) }.max || level
        when Array then node.map { |value| depth_of(value, level + 1) }.max || level
        else level
        end
      end

      def version(document)
        openapi = document["openapi"]
        swagger = document["swagger"]
        declared = openapi || swagger
        return unsupported(declared) unless declared.is_a?(String) && SUPPORTED_MAJORS.include?(declared[0, 3])

        Loaded.new(document:, openapi:, swagger:)
      end

      def unsupported(declared)
        log.add("E002", version: declared.nil? ? "(absent)" : declared, supported: SUPPORTED_MAJORS)
        nil
      end
    end
  end
end
