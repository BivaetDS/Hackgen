# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Tokenization shared by every dictionary lookup (docs/IR_CONTRACT.md 2.1): identifiers split on
    # camelCase boundaries and separators, paths on segments, free text on non-word characters.
    # Everything is lower-cased, so a dictionary never has to list case variants.
    module Tokens
      WORD = /[^\p{L}\p{N}]+/
      PATH_PARAMETER = /\{[^}]*\}/

      module_function

      # "createPayout2" -> ["create", "payout", "2"].
      def identifier(value)
        Inflector.snake_case(value.to_s.gsub(/(\d+)/, '_\1_')).split("_").reject(&:empty?)
      end

      # "/payouts/{id}/cancel" -> ["payouts", "cancel"] (placeholders dropped, then split further).
      def path(value)
        value.to_s.split("/").reject { |segment| segment.empty? || segment.match?(PATH_PARAMETER) }
             .flat_map { |segment| segment.downcase.split(/[_\-.]/) }.reject(&:empty?)
      end

      # "Payout Webhooks" -> ["payout", "webhooks"].
      def tag(value) = value.to_s.downcase.split(/[\s_-]+/).reject(&:empty?)

      # Free text -> lower-cased word tokens.
      def words(value) = value.to_s.downcase.split(WORD).reject(&:empty?)

      # True when +token+ starts with +stem+ (both already lower-cased).
      def stem?(token, stem) = token.start_with?(stem)

      # The first stem of +stems+ found in +text+, as it appears there: a stem without a space is a
      # token prefix ("cent" matches "cents" but not "percent") and returns the whole token; a stem
      # with a space is a plain substring and returns the stem itself. nil when nothing matches.
      def match_stem(text, stems)
        return nil if text.nil? || text.to_s.empty?

        downcased = text.to_s.downcase
        found = words(downcased)
        stems.lazy.filter_map { |stem| stem_in(downcased, found, stem) }.first
      end

      # The occurrence of one stem in the prepared text, or nil.
      def stem_in(text, found, stem)
        return found.find { |token| token.start_with?(stem) } unless stem.include?(" ")

        stem if text.include?(stem)
      end

      # The first token of +tokens+ that starts with any stem of +stems+, honouring +exclude+
      # (tokens listed there never match), or nil.
      def match(tokens, stems, exclude: [])
        tokens.find do |token|
          next false if exclude.include?(token)

          stems.any? { |stem| stem?(token, stem) }
        end
      end

      # True when the path declares a template parameter.
      def path_id?(value) = value.to_s.match?(PATH_PARAMETER)
    end
  end
end
