# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Shared predicates of every result object: success means "no error-level events"; warnings
    # and infos never block a result.
    module ResultPredicates
      def success? = events.none?(&:error?)
      def failure? = !success?
      def errors = events.select(&:error?)
      def warnings = events.select(&:warning?)
      def infos = events.select(&:info?)
    end
  end
end
