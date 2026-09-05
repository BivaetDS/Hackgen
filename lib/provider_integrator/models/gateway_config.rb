# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # ProviderGateway configuration derived from currency constant, default request method and
    # operation direction ("withdraw" | "deposit") through the templates in canonical_contract.yml.
    # `method` is the IR key for the HTTP verb (docs/IR_CONTRACT.md). Shadowing Object#method on IR
    # values is accepted: nothing introspects them through #method.
    # rubocop:disable-next Lint/DataDefineOverride
    GatewayConfig = Data.define(:external_method, :gateway, :direction, :currency, :method, :confidence, :evidence) do
      include Base
    end
  end
end
