# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # How an operation's kind was decided: `source` is override | extension | callbacks | scoring,
    # `scores` holds the weighted score per kind, `evidence` the human-readable signals.
    Classification = Data.define(:confidence, :source, :scores, :evidence) do
      include Base
    end
  end
end
