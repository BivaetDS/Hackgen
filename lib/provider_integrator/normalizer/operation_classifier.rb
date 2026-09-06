# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Decides what an operation is (create, status, webhook, cancel, ...) by weighted scoring over
    # four independent signals - operationId, path or request shape, tag, free text - as described in
    # docs/IR_CONTRACT.md 2.1. No signal alone decides: the confidence is the margin over the
    # runner-up, and everything the scorer looked at is kept as evidence.
    class OperationClassifier
      STRUCTURE_EVIDENCE = {
        "create" => "structure POST with body and no path id -> create",
        "status" => "structure GET with path id -> status",
        "cancel" => "structure DELETE with path id -> cancel",
        "list" => "structure GET without path id -> list"
      }.freeze

      # Result of scoring one operation.
      Verdict = Struct.new(:kind, :confidence, :source, :scores, :evidence, :structural_only, keyword_init: true)

      def initialize(dictionary: Dictionaries.operations)
        @dictionary = dictionary
      end

      # Scores +operation+ (a Parser::Document::OperationRef) and returns a Verdict.
      # +operation_id+ is nil when the spec did not declare one (a synthesized id never scores).
      def call(operation:, operation_id:, has_body:)
        state = State.new(kinds:, weights:, synonyms:)
        score_identifier(state, operation_id)
        score_path(state, operation, has_body)
        score_tags(state, operation)
        score_weak_identifier(state, operation_id)
        score_text(state, operation)
        verdict(state)
      end

      private

      attr_reader :dictionary

      def kinds = dictionary.fetch("kinds")
      def weights = dictionary.fetch("weights")
      def synonyms = dictionary.fetch("synonyms")
      def structural_rules = dictionary.fetch("structural")

      def score_identifier(state, operation_id)
        return if operation_id.nil?

        tokens = Tokens.identifier(operation_id)
        state.webhook_blocked = webhook_blocked?(tokens)
        points = weights.fetch("operation_id_strong")
        state.each_kind do |kind, config|
          token = Tokens.match(tokens, config["strong"] || [], exclude: config["exclude_tokens"] || [])
          next unless token

          state.award(kind, :identifier, points, "operationId token #{quote(token)} -> #{kind} (+#{points})")
        end
      end

      def score_weak_identifier(state, operation_id)
        return if operation_id.nil? || state.strong_hit?

        tokens = Tokens.identifier(operation_id)
        points = weights.fetch("operation_id_weak")
        state.each_kind do |kind, config|
          next unless state.structural_or_path?(kind)

          token = Tokens.match(tokens, config["weak"] || [], exclude: config["exclude_tokens"] || [])
          next unless token

          state.award(kind, :identifier, points, "operationId token #{quote(token)} -> #{kind} (+#{points})")
        end
      end

      def score_path(state, operation, has_body)
        tokens = Tokens.path(operation.path)
        points = weights.fetch("path")
        state.each_kind do |kind, config|
          token = Tokens.match(tokens, config["path"] || [], exclude: config["exclude_tokens"] || [])
          if token
            state.award(kind, :path, points, "path token #{quote(token)} -> #{kind} (+#{points})")
          elsif structural?(kind, operation, has_body, tokens)
            state.award(kind, :structure, points, "#{STRUCTURE_EVIDENCE.fetch(kind)} (+#{points})")
          end
        end
      end

      def score_tags(state, operation)
        tags = operation.node["tags"]
        return unless tags.is_a?(Array)

        points = weights.fetch("tag")
        tags.each do |tag|
          tokens = Tokens.tag(tag)
          state.each_kind do |kind, config|
            next if state.awarded?(kind, :tag)

            token = Tokens.match(tokens, config["path"] || [], exclude: config["exclude_tokens"] || [])
            next unless token

            state.award(kind, :tag, points, "tag #{quote(tag)} -> #{kind} (+#{points})")
          end
        end
      end

      def score_text(state, operation)
        points = weights.fetch("text")
        %w[summary description].each do |key|
          tokens = Tokens.words(operation.node[key])
          state.each_kind do |kind, config|
            next unless state.scored?(kind)
            next if state.awarded?(kind, :text)

            token = Tokens.match(tokens, config["text"] || [], exclude: config["exclude_tokens"] || [])
            next unless token

            state.award(kind, :text, points, "text #{quote(token)} -> #{kind} (+#{points})")
          end
        end
      end

      # A structural rule stands in for a name: the request shape alone suggests the kind.
      def structural?(kind, operation, has_body, path_tokens)
        rule = structural_rules[kind]
        return false unless rule

        facts = { "method" => operation.http_method, "requires_body" => has_body,
                  "path_has_id" => Tokens.path_id?(operation.path) }
        rule.all? { |key, expected| structural_key?(key, expected, facts, path_tokens) }
      end

      def structural_key?(key, expected, facts, path_tokens)
        return facts.fetch(key) == expected if facts.key?(key)
        return true unless key == "excluded_path_stems"

        path_tokens.none? { |token| expected.any? { |stem| Tokens.stem?(token, stem) } }
      end

      def webhook_blocked?(tokens)
        blockers = synonyms.dig("webhook", "exclude_operation_id_tokens") || []
        tokens.any? { |token| blockers.any? { |stem| Tokens.stem?(token, stem) } }
      end

      def verdict(state)
        scores = state.scores
        kind = winner(scores)
        structural_only = kind != "unknown" && state.structural_only?(kind)
        Verdict.new(kind:, confidence: capped(Confidence.from_scores(scores), structural_only), source: "scoring",
                    scores:, evidence: state.evidence(kind), structural_only:)
      end

      # argmax over the scores; a tie for the lead is not a decision.
      def winner(scores)
        best = scores.values.max
        leaders = scores.select { |_, value| value == best }.keys
        best.positive? && leaders.one? ? leaders.first : "unknown"
      end

      def capped(confidence, structural_only)
        return confidence unless structural_only

        [confidence, Confidence.thresholds.fetch("structural_only_cap")].min
      end

      def quote(value) = "'#{value}'"

      # Mutable scoring board for one operation: points and evidence per kind and source.
      class State
        EVIDENCE_ORDER = %i[identifier path structure tag text].freeze

        attr_accessor :webhook_blocked

        def initialize(kinds:, weights:, synonyms:)
          @kinds = kinds
          @weights = weights
          @synonyms = synonyms
          @points = kinds.to_h { |kind| [kind, {}] }
          @notes = kinds.to_h { |kind| [kind, {}] }
          @webhook_blocked = false
        end

        # Yields [kind, synonym config] for every kind; webhook is skipped when its id tokens forbid it.
        def each_kind
          @kinds.each do |kind|
            next if kind == "webhook" && webhook_blocked

            yield(kind, @synonyms.fetch(kind, {}))
          end
        end

        # Records +points+ for +kind+ from +source+ together with the human-readable reason.
        def award(kind, source, points, note)
          @points[kind][source] = points
          @notes[kind][source] = note
        end

        def awarded?(kind, source) = @points.fetch(kind).key?(source)
        def scored?(kind) = @points.fetch(kind).values.sum.positive?
        def structural_or_path?(kind) = awarded?(kind, :path) || awarded?(kind, :structure)

        # True when any kind matched a strong operationId stem (weak stems then stay silent).
        def strong_hit?
          strong = @weights.fetch("operation_id_strong")
          @points.any? { |_, sources| sources[:identifier].to_i >= strong }
        end

        # Only the structural rule fired for this kind: the request shape without a name.
        def structural_only?(kind) = @points.fetch(kind).keys == [:structure]

        def scores = @kinds.to_h { |kind| [kind, @points.fetch(kind).values.sum] }

        # Evidence for the winning kind, ordered by source; an unknown verdict reports every signal.
        def evidence(kind)
          selected = kind == "unknown" ? @kinds : [kind]
          EVIDENCE_ORDER.flat_map do |source|
            selected.filter_map { |candidate| @notes.dig(candidate, source) }
          end
        end
      end
    end
  end
end
