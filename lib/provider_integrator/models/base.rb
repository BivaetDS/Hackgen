# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Shared behaviour of every IR model: a deep `to_h` with String keys and a strict `from_h` that
    # accepts String or Symbol keys, rejects unknown or missing keys (the canonical form always
    # carries every documented key) and rebuilds nested models declared with `nested`/`nested_list`.
    module Base
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Converts a member value into plain JSON-ready data (models -> Hashes, keys -> Strings).
      def self.plain(value)
        case value
        when Base then value.to_h
        when Array then value.map { |item| plain(item) }
        when Hash then value.to_h { |key, item| [JsonCanon.key_string(key), plain(item)] }
        else value
        end
      end

      # Class-level declarations of nested model members and the strict constructor.
      module ClassMethods
        # Declares that member +name+ holds one +klass+ instance or nil.
        def nested(name, klass)
          nested_members[name] = [klass, :one]
        end

        # Declares that member +name+ holds an Array of +klass+ instances.
        def nested_list(name, klass)
          nested_members[name] = [klass, :list]
        end

        # { member => [klass, :one | :list] } for this model.
        def nested_members
          @nested_members ||= {}
        end

        # Builds an instance from a Hash with String or Symbol keys; nested Hashes become models.
        # Raises ArgumentError on unknown or missing keys so contract drift fails loudly.
        def from_h(hash)
          raise ArgumentError, "#{name}.from_h expects a Hash, got #{hash.class}" unless hash.is_a?(Hash)

          attrs = hash.to_h { |key, value| [key.to_sym, value] }
          check_keys!(attrs)
          nested_members.each do |member, (klass, arity)|
            attrs[member] = build_nested(member, attrs[member], klass, arity)
          end
          new(**attrs)
        end

        # Parses JSON text (canonical or not) into a model.
        def from_json(text)
          from_h(JsonCanon.parse(text))
        end

        private

        def check_keys!(attrs)
          unknown = attrs.keys - members
          missing = members - attrs.keys
          return if unknown.empty? && missing.empty?

          raise ArgumentError,
                "#{name}: unknown keys [#{unknown.join(", ")}], missing keys [#{missing.join(", ")}]"
        end

        def build_nested(member, value, klass, arity)
          if arity == :one
            value.nil? ? nil : klass.from_h(value)
          else
            raise ArgumentError, "#{name}.#{member} must be an Array, got #{value.class}" unless value.is_a?(Array)

            value.map { |item| klass.from_h(item) }
          end
        end
      end

      # Deep, JSON-ready Hash with String keys (member order; JsonCanon sorts when serializing).
      def to_h
        self.class.members.to_h do |member|
          [member.to_s, Base.plain(public_send(member))]
        end
      end

      # Canonical JSON text of this model.
      def to_canonical_json
        JsonCanon.generate(to_h)
      end
    end
  end
end
