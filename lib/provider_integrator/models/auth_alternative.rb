# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # A security scheme that exists in the spec but was not chosen as the primary authentication.
    AuthAlternative = Data.define(:scheme_name, :type, :location, :name) do
      include Base
    end
  end
end
