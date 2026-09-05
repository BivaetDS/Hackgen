# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # The idempotency key of a create operation (`location` header | query | body).
    Idempotency = Data.define(:location, :name, :required, :format) do
      include Base
    end
  end
end
