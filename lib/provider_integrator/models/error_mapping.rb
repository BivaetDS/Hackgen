# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One error response mapped to the Space Payments canon: canonical code, action
    # (terminal_reject, retry_with_backoff, ...) and where Retry-After comes from ("header" | "body" | nil).
    ErrorMapping = Data.define(:http, :provider_code, :canonical, :action, :retry_after, :description, :example,
                               :confidence, :evidence, :source) do
      include Base
    end
  end
end
