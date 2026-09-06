# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # How an inference's confidence shows up in generated code (docs/PLAN.md 5, docs/ASSUMPTIONS.md 15):
    # at or above CONFIDENT the code carries only its evidence comment; below it a TODO(confidence)
    # marker is added; below STUB_BELOW the method body is a NotImplementedError stub.
    module Confidence
      CONFIDENT = 0.75
      STUB_BELOW = 0.4
      # A signature whose encoding or message the spec leaves open is never more certain than this.
      SIGNATURE_DEFAULTED = 0.6
      # Marker prefix every reviewer greps for; the report collects the lines that carry it.
      MARKER = "TODO(confidence"

      module_function

      def todo?(confidence) = confidence.to_f < CONFIDENT
      def stub?(confidence) = confidence.to_f < STUB_BELOW

      # "TODO(confidence 0.6): text" - the marker every reviewer greps for.
      def todo(confidence, text) = "#{MARKER} #{format_value(confidence)}): #{text}"

      # The marker only when the confidence asks for one, else nil.
      def todo_if_needed(confidence, text) = todo?(confidence) ? todo(confidence, text) : nil

      # 0.6 -> "0.6", 1.0 -> "1.0", 0.895 -> "0.9" (two decimals, trailing zero dropped except x.0).
      def format_value(confidence)
        text = format("%.2f", confidence.to_f)
        text.sub(/0\z/, "").sub(/\.\z/, ".0")
      end
    end
  end
end
