# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Outcome of a module boundary call: a value plus the events emitted while producing it.
    # Success means "no error-level events"; warnings and infos never block a result.
    Result = Data.define(:value, :events) do
      def success? = events.none?(&:error?)
      def failure? = !success?
      def errors = events.select(&:error?)
      def warnings = events.select(&:warning?)
      def infos = events.select(&:info?)
    end
  end
end
