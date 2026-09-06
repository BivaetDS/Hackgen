# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Structured, read-only view of a loaded OpenAPI document. Everything downstream reads the spec
    # through this object: it keeps the document order (which the IR contract makes part of the
    # output), resolves $ref through RefResolver and hands out JSON pointers for event locations.
    class Document
      HTTP_METHODS = %w[get put post delete options head patch trace].freeze
      # One operation in document order: +node+ is the operation object, +pointer+ its JSON pointer.
      OperationRef = Struct.new(:path, :http_method, :node, :pointer, :path_item, keyword_init: true) do
        # "POST" for the IR.
        def verb = http_method.upcase
      end

      attr_reader :root, :resolver, :spec_format

      def initialize(root:, log:, spec_format:)
        @root = root
        @log = log
        @spec_format = spec_format
        @resolver = RefResolver.new(root:, log:)
      end

      # info.title, or nil.
      def title = info["title"]

      # info.version as a String ("1.0.0"), or nil.
      def version = info["version"]&.to_s

      # info.description, stripped, or nil.
      def description = presence(info["description"])

      # The info object ({} when absent).
      def info = root["info"].is_a?(Hash) ? root["info"] : {}

      # servers[] as declared ([] when absent).
      def servers = root["servers"].is_a?(Array) ? root["servers"].grep(Hash) : []

      # components.securitySchemes, dereferenced: { name => node }.
      def security_schemes
        @security_schemes ||= (components["securitySchemes"] || {}).filter_map do |name, node|
          resolved = deref(node, Pointer.build("components", "securitySchemes", name)).node
          [name, resolved] if resolved.is_a?(Hash)
        end.to_h
      end

      # The document-level security requirement ([] when absent).
      def global_security = root["security"].is_a?(Array) ? root["security"] : []

      # The components object ({} when absent).
      def components = root["components"].is_a?(Hash) ? root["components"] : {}

      # Root-level "x-..." keys, unchanged.
      def extensions = root.select { |key, _| key.is_a?(String) && key.start_with?("x-") }

      # Every operation in document order (paths, then the methods of each path item).
      def operations
        @operations ||= path_items.flat_map do |path, item|
          item.filter_map do |key, node|
            next unless HTTP_METHODS.include?(key.to_s.downcase) && node.is_a?(Hash)

            OperationRef.new(path:, http_method: key.to_s.downcase, node:,
                             pointer: Pointer.build("paths", path, key), path_item: item)
          end
        end
      end

      # [[path, path_item]] in document order, with $ref path items resolved.
      def path_items
        @path_items ||= (root["paths"].is_a?(Hash) ? root["paths"] : {}).filter_map do |path, node|
          next unless path.is_a?(String) && path.start_with?("/")

          item = deref(node, Pointer.build("paths", path)).node
          [path, item] if item.is_a?(Hash)
        end
      end

      # Follows $ref chains; returns RefResolver::Resolved (node nil when unresolvable).
      def deref(node, pointer) = resolver.resolve(node, pointer)

      # The resolved node only, or nil.
      def node_at(node, pointer) = deref(node, pointer).node

      # Parameters of an operation and its path item, deduplicated by (name, in), path item first
      # (an operation-level parameter of the same identity overrides the path-level one).
      def parameters_for(operation)
        declared = list_of(operation.path_item["parameters"], parameters_pointer(operation.path)) +
                   list_of(operation.node["parameters"], Pointer.join(operation.pointer, "parameters"))
        declared.to_h { |node, pointer| [[node["name"], node["in"]], [node, pointer]] }.values
      end

      private

      attr_reader :log

      def parameters_pointer(path) = Pointer.join(Pointer.build("paths", path), "parameters")

      # [[node, pointer]] for an array of possibly-$ref'd items.
      def list_of(array, pointer)
        return [] unless array.is_a?(Array)

        array.each_with_index.filter_map do |node, index|
          item_pointer = Pointer.join(pointer, index.to_s)
          resolved = deref(node, item_pointer)
          [resolved.node, resolved.pointer] if resolved.node.is_a?(Hash)
        end
      end

      def presence(value)
        text = value.is_a?(String) ? value.strip : nil
        text unless text.nil? || text.empty?
      end
    end
  end
end
