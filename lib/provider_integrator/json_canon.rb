# frozen_string_literal: true

module ProviderIntegrator
  # Canonical JSON: deep-sorted object keys, arrays in their original order, JSON.pretty_generate
  # formatting and a trailing newline. Every JSON artefact (IR, fixtures, report) goes through
  # this module so byte-identical output is a property of the serializer, not of each caller.
  module JsonCanon
    module_function

    # Serializes +value+ canonically. Keys must be Strings or Symbols (Symbols become Strings).
    def generate(value)
      "#{JSON.pretty_generate(canonicalize(value))}\n"
    end

    # Parses JSON text into plain Hashes/Arrays with String keys.
    def parse(text)
      JSON.parse(text)
    end

    # Returns a deep copy with String keys sorted bytewise at every level and Symbol values
    # turned into Strings. Arrays keep their order; scalars pass through untouched.
    def canonicalize(value)
      case value
      when Hash then value.map { |key, item| [key_string(key), canonicalize(item)] }.sort_by(&:first).to_h
      when Array then value.map { |item| canonicalize(item) }
      when Symbol then value.to_s
      else value
      end
    end

    # Deep copy with String keys, preserving key order (used where order carries meaning).
    def stringify_keys(value)
      case value
      when Hash then value.to_h { |key, item| [key_string(key), stringify_keys(item)] }
      when Array then value.map { |item| stringify_keys(item) }
      else value
      end
    end

    # SHA-256 hex digest of +text+ (bytes, independent of the String encoding).
    def sha256(text)
      Digest::SHA256.hexdigest(text.b)
    end

    # Converts a Hash key to a String; anything but String/Symbol is a programming error.
    def key_string(key)
      case key
      when String then key
      when Symbol then key.to_s
      else raise ArgumentError, "JSON object keys must be Strings or Symbols, got #{key.class}"
      end
    end
  end
end
