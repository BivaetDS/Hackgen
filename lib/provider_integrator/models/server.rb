# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One `servers[]` entry; `environment` is "sandbox" | "production" | "unknown", inferred from
    # keywords in the url and description.
    Server = Data.define(:url, :description, :environment) do
      include Base
    end
  end
end
