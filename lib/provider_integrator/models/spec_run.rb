# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Result of running a generated service spec in a child process. The captured output is kept
    # for diagnostics; +error+ is reserved for runner/setup failures rather than failed examples.
    SpecRun = Data.define(:examples, :failures, :output, :exit_status, :error)

    # Reopened so behaviour lives outside the Data.define block (the repository model convention).
    class SpecRun
      def self.failed(error, output: "", exit_status: nil)
        new(examples: 0, failures: 1, output:, exit_status:, error:)
      end

      def ok? = error.nil? && !exit_status.nil? && exit_status.zero? && failures.zero?
    end
  end
end
