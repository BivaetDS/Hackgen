# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Finds well-known keys inside response examples when the IR carries no field for them: the
    # error code of an error response and the body field holding Retry-After (docs/IR_CONTRACT.md 4).
    module ExamplePaths
      CODE_KEYS = %w[code error_code error].freeze

      module_function

      # Dotted path of the first String-valued code key in any error example, or nil.
      def error_code(errors)
        errors.each do |error|
          path = find(error.example, CODE_KEYS)
          return path if path
        end
        nil
      end

      # Name of the Retry-After body field: the first example key listed in errors.yml, else the
      # first dictionary name (the spec only says the value is in the body, not where).
      def retry_after_field(errors)
        names = Dictionaries.errors.dig("retry_after", "body_fields")
        errors.each do |error|
          next unless error.retry_after == "body" && error.example.is_a?(Hash)

          key = error.example.keys.find { |name| names.include?(Inflector.snake_case(name)) }
          return key if key
        end
        names.first
      end

      # Depth-first search for a key in +names+ with a scalar value; nested Hashes are descended.
      def find(value, names, prefix = [])
        return nil unless value.is_a?(Hash)

        value.each do |key, item|
          return (prefix + [key]).join(".") if names.include?(key.to_s) && item.is_a?(String)

          nested = find(item, names, prefix + [key])
          return nested if nested
        end
        nil
      end
    end
  end
end
