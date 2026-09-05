# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Primary authentication of the provider API. `type` is one of api_key | http_bearer |
    # http_basic | oauth2_client_credentials | oauth2 | none | unknown; `credentials_key` names
    # the entry of the platform credentials hash the generated service reads.
    Authentication = Data.define(:type, :scheme_name, :location, :name, :bearer_format, :token_url, :scopes,
                                 :credentials_key, :confidence, :evidence, :source, :alternatives) do
      include Base

      nested_list :alternatives, AuthAlternative
    end
  end
end
