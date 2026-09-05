# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # What the webhook receiver should answer (HTTP status and example body).
    WebhookResponse = Data.define(:http, :example) do
      include Base
    end
  end
end
