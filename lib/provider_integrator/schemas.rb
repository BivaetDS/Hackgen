# frozen_string_literal: true

module ProviderIntegrator
  # JSON Schemas (draft 2020-12) for the five dictionaries, for overrides.yml and for the
  # ProviderSpec IR. Validation goes through json_schemer; results are plain error strings so
  # callers can put them into events or CLI output without knowing the library.
  module Schemas
    NAMES = %i[canonical_contract operations fields statuses errors overrides provider_spec].freeze
    DIR = File.join(LIB_ROOT, "schemas")

    class << self
      # Absolute path of the schema file for +name+.
      def path(name)
        File.join(DIR, "#{validate_name(name)}.schema.json")
      end

      # Raw schema Hash (String keys) for +name+; loaded once.
      def load(name)
        name = validate_name(name)
        raw_cache[name] ||= JSON.parse(Files.read(path(name)))
      end

      # Compiled JSONSchemer schema for +name+; compiled once.
      def schema(name)
        name = validate_name(name)
        schema_cache[name] ||= JSONSchemer.schema(load(name))
      end

      # True when +data+ (String-keyed Hash) satisfies the schema +name+.
      def valid?(name, data)
        schema(name).valid?(data)
      end

      # Human-readable validation errors for +data+ against schema +name+ (empty when valid).
      def errors(name, data)
        schema(name).validate(data).map { |error| error["error"] }
      end

      # Validates every shipped dictionary against its schema: { name => [error, ...] }.
      def dictionary_errors
        Dictionaries::NAMES.to_h { |name| [name, errors(name, Dictionaries.load(name))] }
      end

      private

      def raw_cache
        @raw_cache ||= {}
      end

      def schema_cache
        @schema_cache ||= {}
      end

      def validate_name(name)
        symbol = name.to_sym
        return symbol if NAMES.include?(symbol)

        raise ArgumentError, "unknown schema #{name.inspect}; known: #{NAMES.join(", ")}"
      end
    end
  end
end
