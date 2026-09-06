# frozen_string_literal: true

module ProviderIntegrator
  # Turns strings that come from an untrusted spec (slugs, enum values, operationIds, property names)
  # into safe Ruby identifiers and literals. Every identifier that reaches generated code goes
  # through here: reserved words get a suffix, leading digits a prefix, non-ASCII characters are
  # dropped, and an empty result falls back to a caller-supplied name so output is always valid Ruby.
  module Inflector
    RESERVED = %w[
      __ENCODING__ __FILE__ __LINE__ BEGIN END alias and begin break case class def defined? do else elsif end
      ensure false for if in module next nil not or redo rescue retry return self super then true undef unless
      until when while yield
    ].freeze
    # Methods every Object responds to; a generated method with one of these names would shadow them.
    OBJECT_METHODS = %w[
      send method hash freeze display inspect to_s class object_id instance_variable_get instance_variable_set
      public_send extend tap then dup clone itself
    ].freeze
    SLUG = /\A[a-z][a-z0-9_]{0,63}\z/
    IDENTIFIER = /\A[a-z_][a-z0-9_]*\z/

    module_function

    # "createPayout" -> "create_payout", "X-Acme-Signature" -> "x_acme_signature", "SBP" -> "sbp".
    def snake_case(value)
      value.to_s
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .gsub(/[^A-Za-z0-9]+/, "_")
           .gsub(/\A_+|_+\z/, "")
           .squeeze("_")
           .downcase
    end

    # "acme_pay" -> "AcmePay", "acmepay" -> "Acmepay".
    def camel_case(value)
      snake_case(value).split("_").map(&:capitalize).join
    end

    # "acme_pay" -> "ACME_PAY".
    def constant_case(value)
      snake_case(value).upcase
    end

    # A safe lower-case identifier for methods and locals. Non-ASCII is dropped, a leading digit gets
    # "_", reserved words and Object methods get "_field". +fallback+ is used when nothing is left.
    def identifier(value, fallback: "value")
      name = snake_case(value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(/[^\x00-\x7F]/, ""))
      name = fallback.to_s if name.empty?
      name = "_#{name}" if name.match?(/\A\d/)
      name = "#{name}_field" if RESERVED.include?(name) || OBJECT_METHODS.include?(name)
      raise ArgumentError, "cannot derive an identifier from #{value.inspect}" unless name.match?(IDENTIFIER)

      name
    end

    # Class-name-safe version of +value+ ("acme pay" -> "AcmePay"); +fallback+ when empty.
    def class_name(value, fallback: "Provider")
      name = camel_case(value.to_s.gsub(/[^\x00-\x7F]/, ""))
      name = fallback if name.empty?
      name = "N#{name}" if name.match?(/\A\d/)
      name
    end

    # True when +value+ is an acceptable provider slug (also the whitelist for CLI/web input).
    def slug?(value)
      value.is_a?(String) && value.match?(SLUG)
    end

    # Ruby String literal for +value+: single quotes when no escaping is needed (the reference service
    # style), otherwise the double-quoted form from String#inspect.
    def ruby_string(value)
      text = value.to_s
      return "'#{text}'" unless text.match?(/['\\\p{Cntrl}]/)

      text.inspect
    end

    # Ruby literal for a JSON-like value (String, Integer, Float, true/false/nil, Array, Hash).
    # Hashes keep insertion order and use string keys; nested values recurse.
    def ruby_literal(value)
      case value
      when String then ruby_string(value)
      when Integer, Float, true, false then value.to_s
      when nil then "nil"
      when Array then "[#{value.map { |item| ruby_literal(item) }.join(", ")}]"
      when Hash then ruby_hash_literal(value)
      else raise ArgumentError, "cannot render #{value.class} as a Ruby literal"
      end
    end

    # "{ 'key' => value, ... }" with string keys in insertion order; "{}" when empty.
    def ruby_hash_literal(hash)
      return "{}" if hash.empty?

      pairs = hash.map { |key, item| "#{ruby_string(key)} => #{ruby_literal(item)}" }
      "{ #{pairs.join(", ")} }"
    end
  end
end
