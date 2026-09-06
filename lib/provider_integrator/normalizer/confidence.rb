# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # The one confidence formula of the project (docs/IR_CONTRACT.md 2): how far the winning score is
    # ahead of the runner-up, normalized so a wide margin over small numbers does not read as certainty.
    module Confidence
      module_function

      # (best - second) / (best + 1), rounded to two decimals; 0.0 when nothing scored.
      def from_scores(scores)
        ranked = scores.values.map(&:to_f).sort.reverse
        best = ranked.first || 0.0
        return 0.0 if best <= 0

        round((best - (ranked[1] || 0.0)) / (best + 1))
      end

      # Two-decimal rounding, the IR's storage format for every confidence.
      def round(value) = value.to_f.round(2)

      # Thresholds from operations.yml (unknown_below, low_confidence_below, structural_only_cap).
      def thresholds = Dictionaries.operations.fetch("thresholds")
    end
  end
end
