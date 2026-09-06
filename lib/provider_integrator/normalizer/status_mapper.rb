# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Maps provider status values onto the three Space Payments statuses using statuses.yml
    # (docs/IR_CONTRACT.md 2.7). Four sources in decreasing trust: the synonym table, the enum
    # description ("1 - успешно"), the numeric convention (0/1/2) and, last, the default - each with
    # its own confidence so the generated code and the report can show how sure the mapping is.
    class StatusMapper
      SEPARATORS = /[-. ]/
      # A value containing one of these does not mean what its other words mean.
      NEGATIONS = %w[not non un no не].freeze
      EVENT_SEPARATORS = /[._-]/
      # One provider status resolved to the canon.
      Verdict = Struct.new(:provider, :canonical, :confidence, :source, :evidence, keyword_init: true)

      def initialize(dictionary: Dictionaries.statuses)
        @dictionary = dictionary
      end

      # Maps one status value; +description+ is the description of the enum field it came from.
      def call(value, description: nil, override: nil)
        provider = value.to_s
        return overridden(provider, override) if override

        from_dictionary(provider) || from_description(provider, description) || from_token(provider) ||
          from_numeric(provider) || fallback(provider)
      end

      # Maps a webhook event value ("payout.completed"): the last token decides, an earlier one is
      # accepted with less confidence.
      def for_event(value)
        tokens = value.to_s.split(EVENT_SEPARATORS).reject(&:empty?)
        tokens.reverse.each_with_index do |token, index|
          canonical = lookup(normalize(token))
          next unless canonical

          source = index.zero? ? "dictionary" : "token"
          return Verdict.new(provider: value.to_s, canonical:, confidence: confidences.fetch(source), source:,
                             evidence: ["statuses.yml: #{token} -> #{canonical}"])
        end
        nil
      end

      # The canonical statuses in canon order.
      def canonical_statuses = dictionary.fetch("canonical")

      # The status assumed when nothing matches.
      def default_status = dictionary.fetch("default")

      private

      attr_reader :dictionary

      def confidences = dictionary.fetch("confidence")
      def synonyms = dictionary.fetch("synonyms")

      # "IN_PROGRESS", "in-progress" and "in progress" are the same provider status.
      def normalize(value) = value.to_s.downcase.gsub(SEPARATORS, "_")

      def lookup(normalized) = synonyms.find { |_, values| values.include?(normalized) }&.first

      def overridden(provider, canonical)
        Verdict.new(provider:, canonical:, confidence: confidences.fetch("override"), source: "override",
                    evidence: ["overrides.yml: #{provider} -> #{canonical}"])
      end

      def from_dictionary(provider)
        canonical = lookup(normalize(provider))
        return nil unless canonical

        Verdict.new(provider:, canonical:, confidence: confidences.fetch("dictionary"), source: "dictionary",
                    evidence: ["statuses.yml: #{normalize(provider)} -> #{canonical}"])
      end

      # "rejected_by_bank" is a rejection even though no dictionary lists it verbatim. Negations
      # ("not_completed") are excluded: there the meaningful word says the opposite of the whole.
      def from_token(provider)
        tokens = normalize(provider).split("_")
        return nil if tokens.one? || tokens.any? { |token| NEGATIONS.include?(token) }

        canonical = canonical_statuses.reverse.find do |candidate|
          tokens.any? { |token| synonyms.fetch(candidate, []).include?(token) }
        end
        return nil unless canonical

        Verdict.new(provider:, canonical:, confidence: confidences.fetch("token"), source: "token",
                    evidence: ["statuses.yml token: #{provider} -> #{canonical}"])
      end

      # "0 - в обработке, 1 - успешно": the enum description explains its own values.
      def from_description(provider, description)
        text = described(provider, description)
        return nil unless text

        canonical = word_match(text)
        return nil unless canonical

        Verdict.new(provider:, canonical:, confidence: confidences.fetch("description"), source: "description",
                    evidence: ["description: #{provider} - #{text}"])
      end

      def described(provider, description)
        return nil if description.nil?

        dictionary.fetch("description_patterns").each do |pattern|
          description.to_s.scan(Regexp.new(pattern)) do
            match = Regexp.last_match
            return match[:text].strip if match[:value].to_s == provider.to_s
          end
        end
        nil
      end

      # Negations are longer and more specific, so rejected is tried first.
      def word_match(text)
        tokens = Tokens.words(text)
        words = dictionary.fetch("description_words")
        %w[rejected approved in_progress].find do |canonical|
          tokens.any? { |token| words.fetch(canonical).any? { |stem| Tokens.stem?(token, stem) } }
        end
      end

      def from_numeric(provider)
        canonical = dictionary.fetch("numeric")[provider.to_s]
        return nil unless canonical

        Verdict.new(provider:, canonical:, confidence: confidences.fetch("numeric_default"),
                    source: "numeric_default", evidence: ["statuses.yml numeric: #{provider} -> #{canonical}"])
      end

      def fallback(provider)
        canonical = default_status
        Verdict.new(provider:, canonical:, confidence: confidences.fetch("default"), source: "default",
                    evidence: ["default: #{canonical}"])
      end
    end
  end
end
