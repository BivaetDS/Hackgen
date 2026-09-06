# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Maps provider field names onto the Space Payments canon using fields.yml only
    # (docs/IR_CONTRACT.md 2.3). Resolution order: override, child of an already mapped container,
    # exact synonym, flat-schema conventions, "*_id" suffix; anything left over stays unmapped
    # rather than being guessed, and a required request field that stays unmapped raises W403.
    class FieldMapper
      CONTAINER_CANONICALS = %w[requisite error customer].freeze
      # What one field resolved to; +canonical+ is nil when nothing matched.
      Mapping = Struct.new(:canonical, :confidence, :evidence, :source, keyword_init: true) do
        def mapped? = !canonical.nil?
      end

      def initialize(dictionary: Dictionaries.fields)
        @dictionary = dictionary
      end

      # Maps a whole flattened schema at once and returns { provider_path => Mapping }.
      # +context+ is "request", "response" or "webhook"; +error_context+ marks an error response body.
      def call(fields, context:, error_context: false, overrides: {})
        fields.each_with_object({}) do |field, mapped|
          mapped[field.path] = map_field(field, context:, error_context:, overrides:, mapped:)
        end
      end

      # The canonical role of a header/query/cookie parameter ("idempotency_key", "signature",
      # "auth"), or nil. Entries without "_" match any token of the name, entries with "_" match
      # the whole snake_case name.
      def parameter_role(name)
        tokens = Tokens.identifier(name)
        snake = Inflector.snake_case(name)
        parameters.each do |role, patterns|
          return role if patterns.any? { |pattern| parameter_hit?(pattern, snake, tokens) }
        end
        nil
      end

      # The canonical name of a path parameter (provider_operation_id, external_id) or nil.
      def path_parameter_canonical(name)
        snake = Inflector.snake_case(name)
        return "external_id" if synonym?("external_id", snake)

        rules = Dictionaries.operations.fetch("path_parameters")
        tokens = snake.split("_")
        return nil if tokens.any? { |token| stem_any?(token, rules.fetch("not_provider_id_stems")) }

        "provider_operation_id" if rules.fetch("id_stems").include?(tokens.last)
      end

      # True when +canonical+ names a container entry of fields.yml (requisite, error, customer).
      def container?(canonical) = CONTAINER_CANONICALS.include?(canonical)

      # True when the canonical field carries money and therefore needs a unit decision.
      def money?(canonical) = canonical_entry(canonical)&.fetch("money", false) == true

      private

      attr_reader :dictionary

      def canonicals = dictionary.fetch("canonical")
      def confidences = dictionary.fetch("confidence")
      def flat = dictionary.fetch("flat")
      def parameters = dictionary.fetch("parameters")

      def canonical_entry(canonical) = canonicals[canonical.to_s]

      def map_field(field, context:, error_context:, overrides:, mapped:)
        from_override(field, overrides) ||
          from_container(field, mapped) ||
          from_synonym(field, context) ||
          from_flat(field, context, error_context) ||
          from_suffix(field, context) ||
          Mapping.new(canonical: nil, confidence: 0.0, evidence: [], source: "none")
      end

      def from_override(field, overrides)
        canonical = overrides[field.path]
        return nil unless canonical

        Mapping.new(canonical:, confidence: confidences.fetch("override"), source: "override",
                    evidence: ["overrides.yml: #{field.path} -> #{canonical}"])
      end

      # A field whose nearest mapped ancestor is a container belongs to that container, full stop:
      # "recipient.bank_code" is the requisite's bank code even though "bank_code" is generic.
      def from_container(field, mapped)
        container = nearest_container(field.path, mapped)
        return nil unless container

        name = Inflector.snake_case(field.name)
        child = children_of(container).find { |_, synonyms| synonyms.include?(name) }&.first
        return container_child(container, name, child) if child

        Mapping.new(canonical: "#{container}.#{name}", confidence: confidences.fetch("container_child"),
                    source: "container", evidence: ["container #{container}: #{field.name} -> #{container}.#{name}"])
      end

      def container_child(container, name, child)
        Mapping.new(canonical: "#{container}.#{child}", confidence: confidences.fetch("exact"), source: "dictionary",
                    evidence: ["fields.yml: #{container} child #{name} -> #{container}.#{child}"])
      end

      def nearest_container(path, mapped)
        segments = path.split(".")
        (segments.size - 1).downto(1) do |size|
          canonical = mapped[segments.take(size).join(".")]&.canonical
          next if canonical.nil?

          return container?(canonical) ? canonical : nil
        end
        nil
      end

      def from_synonym(field, context)
        name = Inflector.snake_case(field.name)
        canonical = canonicals.keys.find { |candidate| synonym_in_context?(candidate, name, field, context) }
        return nil unless canonical

        Mapping.new(canonical:, confidence: confidences.fetch("exact"), source: "dictionary",
                    evidence: ["fields.yml: #{field.name} -> #{canonical}"])
      end

      def synonym_in_context?(canonical, name, field, context)
        entry = canonicals.fetch(canonical)
        return false unless entry_applies?(entry, name, field, context)
        return true if Array(entry["synonyms"]).include?(name)

        context == "request" && Array(entry["request_synonyms"]).include?(name)
      end

      # A dictionary entry only applies in its declared scope, never to a name it excludes, and a
      # container entry only to a field that really is an object.
      def entry_applies?(entry, name, field, context)
        return false if Array(entry["exclude"]).include?(name)
        return false unless scope_allows?(entry, context)

        entry["container"] != true || Parser::SchemaFacts.object?(field.schema)
      end

      def scope_allows?(entry, context)
        scope = entry["scope"]
        scope.nil? || Array(scope).include?(context)
      end

      # Providers that keep requisites and errors flat on the top level instead of nesting them.
      def from_flat(field, context, error_context)
        name = Inflector.snake_case(field.name)
        flat_requisite(name) || flat_error(name) || flat_error_context(name, context, error_context) ||
          scalar_error(field, name)
      end

      def flat_requisite(name)
        return exact_flat(name, "requisite.type") if Array(flat.dig("requisite", "type")).include?(name)

        child = children_of("requisite").find { |_, synonyms| synonyms.include?(name) }&.first
        return nil unless child

        Mapping.new(canonical: "requisite.#{child}", confidence: confidences.fetch("flat_requisite"),
                    source: "dictionary", evidence: ["fields.yml: flat #{name} -> requisite.#{child}"])
      end

      def flat_error(name)
        key = %w[code message].find { |candidate| Array(flat.dig("error", candidate)).include?(name) }
        key && exact_flat(name, "error.#{key}")
      end

      def flat_error_context(name, context, error_context)
        return nil unless context == "webhook" || error_context

        key = %w[code message].find { |candidate| Array(flat.dig("error_context", candidate)).include?(name) }
        return nil unless key

        Mapping.new(canonical: "error.#{key}", confidence: confidences.fetch("context"), source: "dictionary",
                    evidence: ["fields.yml: flat #{name} -> error.#{key}"])
      end

      # A scalar named "error" is the code itself, not a container.
      def scalar_error(field, name)
        return nil unless flat["scalar_error_is_code"] == true
        return nil if Parser::SchemaFacts.object?(field.schema)
        return nil unless Array(canonicals.dig("error", "synonyms")).include?(name)

        exact_flat(name, "error.code")
      end

      def exact_flat(name, canonical)
        Mapping.new(canonical:, confidence: confidences.fetch("exact"), source: "dictionary",
                    evidence: ["fields.yml: flat #{name} -> #{canonical}"])
      end

      # In a response or a callback body, "<something>_id" is the provider's own identifier.
      def from_suffix(field, context)
        return nil unless %w[response webhook].include?(context)

        name = Inflector.snake_case(field.name)
        suffix = Array(canonicals.dig("provider_operation_id", "suffixes")).find { |item| name.end_with?(item) }
        return nil unless suffix

        Mapping.new(canonical: "provider_operation_id", confidence: confidences.fetch("suffix"),
                    source: "dictionary", evidence: ["fields.yml: suffix #{suffix} -> provider_operation_id"])
      end

      def children_of(container) = canonicals.dig(container, "children") || {}

      def synonym?(canonical, name) = Array(canonicals.dig(canonical, "synonyms")).include?(name)

      def stem_any?(token, stems) = stems.any? { |stem| Tokens.stem?(token, stem) }

      def parameter_hit?(pattern, snake, tokens)
        return snake == pattern if pattern.include?("_")

        tokens.any? { |token| Tokens.stem?(token, pattern) }
      end
    end
  end
end
