# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Works out how a provider signs its callbacks (docs/IR_CONTRACT.md 2.9). Specs name the header
    # and usually the algorithm, but almost never the encoding or what exactly is hashed - so those
    # stay "unknown" in the IR, the generator applies the documented canon defaults, and W301 tells
    # the integrator to confirm them. Nothing here is guessed silently.
    class SignatureAnalyzer
      # Algorithm patterns in order: the most specific name wins.
      ALGORITHMS = [
        [/hmac.?sha.?512/, "hmac-sha512"], [/hmac.?sha.?256|hmac.?256/, "hmac-sha256"],
        [/hmac.?sha.?1\b/, "hmac-sha1"], [/hmac.?md5/, "hmac-md5"], [/hmac/, "hmac-sha256"],
        [/sha.?512/, "sha512"], [/sha.?256/, "sha256"], [/sha.?1\b/, "sha1"], [/md5/, "md5"],
        [/rsa/, "rsa-sha256"], [/ed25519/, "ed25519"]
      ].freeze
      ENCODINGS = { "hex" => %w[hex hexdigest шестнадцат], "base64" => %w[base64] }.freeze
      CONCATENATED = %w[concat sorted fields конкатен полей склеен].freeze
      RAW_BODY = %w[raw сыр bytes body тела payload].freeze
      RAW_ONLY = %w[raw сыр bytes].freeze
      SENTENCE = /[.\n]/
      # Where the signature travels and how it is described.
      Source = Struct.new(:location, :name, :label, :description, :source, keyword_init: true)

      def initialize(canon: Dictionaries.canonical_contract)
        @canon = canon
      end

      # Builds Models::Signature for +source+ (a Source) using the operation's +summary+ and
      # +description+ as extra evidence, or nil when the spec declares no signature at all.
      def call(source:, summary: nil, description: nil, override: nil)
        return nil if source.nil? && override.nil?

        texts = texts_for(source, summary, description)
        algorithm = detect(texts) { |text| match_algorithm(text) }
        build(source, texts, algorithm, override)
      end

      # The defaults the generator applies where the spec is silent.
      def defaults = canon.fetch("signature_defaults")

      private

      attr_reader :canon

      def build(source, texts, algorithm, override)
        forced = override || {}
        place = placement(forced, source)
        found = forced[:algorithm] || algorithm&.fetch(:value) || "unknown"
        Models::Signature.new(
          **place, algorithm: found, encoding: encoding_of(forced, texts),
                   message: message_of(forced, texts, place[:location]),
                   secret: canon.fetch("credentials").fetch("callback_secret"),
                   confidence: found == "unknown" ? 0.5 : 0.9, evidence: evidence(source, texts, algorithm, override),
                   source: override ? "override" : source.source
        )
      end

      # Where the signature is carried, with an override winning over the declaration.
      def placement(forced, source)
        { location: forced[:location] || source.location, name: forced[:name] || source.name }
      end

      def encoding_of(forced, texts)
        forced[:encoding] || detect(texts) { |text| match_encoding(text) } || "unknown"
      end

      def message_of(forced, texts, location)
        forced[:message] || detect_message(texts, location) || "unknown"
      end

      # [[prefix, text], ...] in search order: the declaration itself, then the operation prose.
      def texts_for(source, summary, description)
        { source.label => source.description, "operation description" => description,
          "operation summary" => summary }.reject { |_, text| text.nil? || text.to_s.strip.empty? }
      end

      def detect(texts)
        texts.each_value do |text|
          found = yield(text.to_s.downcase)
          return found if found
        end
        nil
      end

      def match_algorithm(text)
        ALGORITHMS.each do |pattern, value|
          match = pattern.match(text)
          return { value:, pattern: } if match
        end
        nil
      end

      def match_encoding(text)
        ENCODINGS.find { |_, stems| stems.any? { |stem| text.include?(stem) } }&.first
      end

      # What is hashed: a canonical concatenation of fields, or the body as it arrived.
      def detect_message(texts, location)
        detect(texts) { |text| CONCATENATED.any? { |stem| text.include?(stem) } ? "concatenated_fields" : nil } ||
          detect(texts) { |text| body_message(text, location) }
      end

      def body_message(text, location)
        return "raw_body" if RAW_BODY.any? { |stem| text.include?(stem) } && location != "body"

        "raw_body" if location == "body" && RAW_ONLY.any? { |stem| text.include?(stem) }
      end

      # One line per text that actually mentions the algorithm; when nothing does, just the place.
      def evidence(source, texts, algorithm, override)
        return ["overrides.yml: signature #{override[:name]} (#{override[:location]})"] if override
        return [source.label.to_s] unless algorithm

        lines = texts.filter_map do |prefix, text|
          fragment = mentioning(text.to_s, algorithm[:pattern])
          "#{prefix}: #{fragment}" if fragment
        end
        lines.empty? ? [source.label.to_s] : lines
      end

      # The sentence of +text+ that carries the algorithm, or the whole text when it is one line.
      def mentioning(text, pattern)
        return nil unless pattern.match?(text.downcase)

        sentences = text.split(SENTENCE).map(&:strip).reject(&:empty?)
        sentences.find { |sentence| pattern.match?(sentence.downcase) } || text.strip
      end
    end
  end
end
