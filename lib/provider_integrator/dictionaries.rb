# frozen_string_literal: true

module ProviderIntegrator
  # Loads the YAML dictionaries shipped in lib/provider_integrator/dictionaries/ once per process
  # and deep-freezes them. Dictionaries are the only home of provider-agnostic domain knowledge
  # (synonyms, weights, the Space Payments canon); code never hardcodes those values.
  module Dictionaries
    NAMES = %i[canonical_contract operations fields statuses errors].freeze
    DIR = File.join(LIB_ROOT, "dictionaries")

    class << self
      # Absolute path of the yml file for +name+.
      def path(name)
        File.join(DIR, "#{validate_name(name)}.yml")
      end

      # Deep-frozen Hash for the dictionary +name+ (one of NAMES); loaded once.
      def load(name)
        name = validate_name(name)
        cache[name] ||= deep_freeze(Psych.safe_load_file(path(name), permitted_classes: [Symbol]))
      end

      # Space Payments canon: contract methods, statuses, error codes/actions, gateway templates.
      def canonical_contract = load(:canonical_contract)

      # Operation-kind synonyms, scoring weights, structural rules, direction keywords.
      def operations = load(:operations)

      # Canonical field names with synonyms, money-unit signals, conditional-required patterns.
      def fields = load(:fields)

      # Provider status synonyms (string and numeric) and webhook event suffixes.
      def statuses = load(:statuses)

      # HTTP -> canonical error/action table and provider error-code synonyms.
      def errors = load(:errors)

      # Drops memoized dictionaries (specs that edit yml files call this).
      def reset!
        cache.clear
      end

      # Recursively freezes Hashes, Arrays and scalars so a dictionary cannot be mutated at runtime.
      def deep_freeze(value)
        case value
        when Hash then value.each_value { |item| deep_freeze(item) }
        when Array then value.each { |item| deep_freeze(item) }
        end
        value.freeze
      end

      private

      def cache
        @cache ||= {}
      end

      def validate_name(name)
        symbol = name.to_sym
        return symbol if NAMES.include?(symbol)

        raise ArgumentError, "unknown dictionary #{name.inspect}; known: #{NAMES.join(", ")}"
      end
    end
  end
end
