# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Reads the plain facts of a JSON-Schema node the way the IR records them, hiding the 3.0/3.1
    # differences: "nullable: true" versus a type list containing "null", "enum" of one value versus
    # "const", "example" versus "examples: []".
    module SchemaFacts
      NULL = "null"

      module_function

      # The effective type ("string", "integer", ...); for a 3.1 type list, the first non-null entry.
      def type(schema)
        value = schema["type"]
        case value
        when String then value == NULL ? nil : value
        when Array then value.map(&:to_s).find { |item| item != NULL }
        end
      end

      # True when the schema allows null (3.0 "nullable", 3.1 type list).
      def nullable?(schema)
        return true if schema["nullable"] == true

        schema["type"].is_a?(Array) && schema["type"].map(&:to_s).include?(NULL)
      end

      # The enum values as declared, or nil.
      def enum(schema)
        values = schema["enum"]
        values if values.is_a?(Array) && !values.empty?
      end

      # The single value this schema can take ("const", or an enum of exactly one), else nil.
      def constant(schema)
        return schema["const"] if schema.key?("const")

        values = enum(schema)
        values.first if values&.one?
      end

      # The declared example: "example" (3.0) or the first entry of "examples" (3.1), else nil.
      def example(schema)
        return schema["example"] if schema.key?("example")

        values = schema["examples"]
        values.first if values.is_a?(Array) && !values.empty?
      end

      # description, stripped, or nil.
      def description(schema)
        text = schema["description"]
        return nil unless text.is_a?(String)

        stripped = text.strip
        stripped.empty? ? nil : stripped
      end

      # True when the node describes an object (properties, explicit type or a composition).
      def object?(schema)
        return true if type(schema) == "object" || schema.key?("properties")

        %w[oneOf anyOf allOf].any? { |key| schema[key].is_a?(Array) }
      end

      # True when the node describes an array with items.
      def array?(schema) = type(schema) == "array" || schema.key?("items")
    end
  end
end
