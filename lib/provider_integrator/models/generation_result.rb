# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Result of Generator.call: `files` are GeneratedFile objects in output order, `events` the
    # generator's and validator's diagnostics, `validation` the OutputValidator summary (a
    # String-keyed Hash also embedded in generation_report.json).
    GenerationResult = Data.define(:value, :events, :validation) do
      include ResultPredicates

      def files = value

      # The generated file of +kind+ ("service", "fixtures", ...), or nil.
      def file(kind) = files.find { |file| file.kind == kind.to_s }
    end
  end
end
