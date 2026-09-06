# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Outcome of Pipeline.call. `status` says how far the run got: :ok (files written, or the
    # analysis finished under analyze_only), :spec (the document is unusable), :generation (the
    # output failed validation; nothing was written), :write (the files could not be written),
    # :spec_failed (the generated RSpec failed after files were written), :internal (a bug; `error`
    # holds the exception). `events` merges analysis and generation diagnostics; `files` are the
    # GeneratedFile objects actually written, and `spec_run` is the optional --run-spec result.
    PipelineResult = Data.define(:status, :spec, :events, :files, :output_dir, :spec_run, :error)

    # Reopened so the constant and the predicates live outside the Data.define block.
    class PipelineResult
      include ResultPredicates

      STATUSES = %i[ok spec generation spec_failed write internal].freeze

      def initialize(**)
        super
        raise ArgumentError, "unknown pipeline status #{status.inspect}" unless STATUSES.include?(status)
      end

      # Unlike the parse and generation results, success is the status, not the absence of error
      # events: a write failure has no event of its own, and warnings never block a run.
      def success? = status == :ok
      def failure? = !success?
    end
  end
end
