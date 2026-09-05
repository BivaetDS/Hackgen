# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Payout methods of a create operation (enum of the requisite type, a discriminator or oneOf);
    # drives the request_method branching of the generated service.
    RequestMethods = Data.define(:discriminator_path, :values, :default, :source, :confidence) do
      include Base
    end
  end
end
