# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Turns one error response into a canonical code plus the action the platform should take
    # (docs/IR_CONTRACT.md 2.8). Two levels of knowledge: the HTTP status always yields a default,
    # and the provider's own code - read from an example, else from the enum of the error schema -
    # refines it. A provider code never turns a transport failure (429, 5xx) into a terminal reject.
    class ErrorClassifier
      FALLBACK_CODE_KEYS = %w[code error_code error].freeze
      # One classified error response.
      Verdict = Struct.new(:provider_code, :canonical, :action, :retry_after, :confidence, :evidence, :source,
                           :unknown_code, keyword_init: true)

      def initialize(dictionary: Dictionaries.errors)
        @dictionary = dictionary
      end

      # Classifies the response +http+ using its +example+, its flattened schema +fields+ with their
      # +mappings+, and its declared +headers+ (Models::ResponseHeader).
      def call(http:, response:, override_actions: {})
        code_field = code_field(response.fields, response.mappings)
        retry_after = retry_after_source(response.fields, response.headers)
        from_example(http, response.example, code_field, retry_after, override_actions) ||
          from_enum(http, code_field, retry_after) ||
          from_http(http, retry_after)
      end

      # The response facts the classifier reads: its example, its flattened schema with the field
      # mappings, and the headers it declares.
      Body = Struct.new(:example, :fields, :mappings, :headers, keyword_init: true) do
        def self.of(example: nil, fields: [], mappings: {}, headers: []) = new(example:, fields:, mappings:, headers:)
      end

      # The canonical code and action the HTTP status alone implies.
      def http_default(http)
        table = dictionary.fetch("http")
        table[http.to_s] || table.fetch(http.to_i >= 500 ? "default_5xx" : "default_4xx")
      end

      private

      attr_reader :dictionary

      def confidences = dictionary.fetch("confidence")
      def provider_codes = dictionary.fetch("provider_codes")

      def code_field(fields, mappings)
        fields.find { |field| mappings[field.path]&.canonical == "error.code" }
      end

      # ---- source: example -------------------------------------------------------------------

      def from_example(http, example, code_field, retry_after, override_actions)
        code = example_code(example, code_field)
        return nil unless code

        entry = entry_for(code)
        decision = decide(http, code, entry, override_actions)
        Verdict.new(provider_code: code, canonical: decision[:canonical], action: decision[:action], retry_after:,
                    confidence: confidences.fetch("example"), source: decision[:source],
                    evidence: ["example (#{http}): code #{code}"] + decision[:evidence],
                    unknown_code: decision[:unknown] == true)
      end

      def example_code(example, code_field)
        return nil unless example.is_a?(Hash)

        by_path = code_field && dig_path(example, code_field.path)
        return by_path if by_path.is_a?(String) && !by_path.empty?

        found = deep_find(example)
        found if found.is_a?(String) && !found.empty?
      end

      def dig_path(example, path)
        path.split(".").reduce(example) do |node, segment|
          node = node.first if segment.end_with?("[]") && node.is_a?(Array)
          break nil unless node.is_a?(Hash)

          node.fetch(segment.delete_suffix("[]"), nil)
        end
      end

      def deep_find(node)
        return deep_find_in_hash(node) if node.is_a?(Hash)
        return node.filter_map { |value| deep_find(value) }.first if node.is_a?(Array)

        nil
      end

      def deep_find_in_hash(node)
        hit = node.find { |key, value| FALLBACK_CODE_KEYS.include?(key.to_s) && value.is_a?(String) }
        return hit.last if hit

        node.values.filter_map { |value| deep_find(value) }.first
      end

      # The provider code decides, unless the HTTP status says the failure is transient and the
      # code would end the operation for good.
      def decide(http, code, entry, override_actions)
        default = http_default(http)
        forced = override_actions[code]
        return overridden(entry, default, forced) if forced
        return unknown_code(default, http) unless entry
        return guarded(entry, default, http) if guard?(http, entry)

        { canonical: entry.fetch("canonical"), action: entry.fetch("action"), source: "example",
          evidence: [rule_line(code, entry.fetch("canonical"), entry.fetch("action"))] + note_of(entry) }
      end

      def overridden(entry, default, action)
        canonical = entry ? entry.fetch("canonical") : default.fetch("canonical")
        { canonical:, action:, source: "override",
          evidence: ["overrides.yml: error action #{action}"] + note_of(entry) }
      end

      def unknown_code(default, http)
        { canonical: default.fetch("canonical"), action: default.fetch("action"), source: "example",
          evidence: [rule_line_http(http, default)], unknown: true }
      end

      def guarded(entry, default, http)
        evidence = [rule_line_http(http, default),
                    "http #{http} overrides terminal action #{entry.fetch("action")}"]
        { canonical: default.fetch("canonical"), action: default.fetch("action"), source: "example",
          evidence: evidence + note_of(entry) }
      end

      def guard?(http, entry)
        guard = dictionary.fetch("http_guard")
        guard.fetch("statuses").include?(http.to_s) && guard.fetch("terminal_actions").include?(entry.fetch("action"))
      end

      # ---- source: enum ----------------------------------------------------------------------

      def from_enum(http, code_field, retry_after)
        return nil unless code_field

        values = Parser::SchemaFacts.enum(code_field.schema)
        return nil unless values

        default = http_default(http)
        code = enum_code(values, default)
        return nil unless code

        Verdict.new(provider_code: code, canonical: default.fetch("canonical"), action: default.fetch("action"),
                    retry_after:, confidence: confidences.fetch("enum"), source: "enum",
                    evidence: ["enum #{owner(code_field)}: #{code}", rule_line_http(http, default)])
      end

      # The enum value that means what the HTTP status means: the canonical name itself, else the
      # first value whose dictionary entry agrees with the HTTP default on both code and action.
      def enum_code(values, default)
        strings = values.grep(String)
        exact = strings.find { |value| value == default.fetch("canonical") }
        return exact if exact

        strings.find do |value|
          entry = entry_for(value)
          entry && entry["canonical"] == default.fetch("canonical") && entry["action"] == default.fetch("action")
        end
      end

      def owner(field)
        segments = Parser::Pointer.parse(field.pointer) || []
        index = segments.rindex("properties")
        component = index && index >= 1 ? segments[index - 1] : "inline"
        "#{component}.#{field.name}"
      end

      # ---- source: http default --------------------------------------------------------------

      def from_http(http, retry_after)
        default = http_default(http)
        Verdict.new(provider_code: nil, canonical: default.fetch("canonical"), action: default.fetch("action"),
                    retry_after:, confidence: confidences.fetch("http_default"), source: "http_default",
                    evidence: [rule_line_http(http, default)])
      end

      # ---- shared ----------------------------------------------------------------------------

      # The first dictionary entry one of whose stems occurs in the normalized provider code.
      def entry_for(code)
        normalized = Inflector.snake_case(code)
        provider_codes.find { |entry| entry.fetch("stems").any? { |stem| normalized.include?(stem) } }
      end

      def note_of(entry)
        note = entry && entry["note"]
        note ? ["note: #{note}"] : []
      end

      def rule_line(code, canonical, action) = "errors.yml: #{code} -> #{canonical} (#{action})"

      def rule_line_http(http, default)
        "errors.yml: HTTP #{http} -> #{default.fetch("canonical")} (#{default.fetch("action")})"
      end

      def retry_after_source(fields, headers)
        return "header" if headers.any? { |header| header.canonical == "retry_after" }

        body = dictionary.fetch("retry_after").fetch("body_fields")
        fields.any? { |field| body.include?(Inflector.snake_case(field.name)) } ? "body" : nil
      end
    end
  end
end
