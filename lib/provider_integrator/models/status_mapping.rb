# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Provider status (always a String, even for numeric statuses) -> canonical
    # in_progress | approved | rejected.
    StatusMapping = Data.define(:provider, :canonical, :confidence, :source, :evidence) do
      include Base
    end
  end
end
