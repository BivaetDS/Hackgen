# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One value of the webhook event field with its canonical status (nil when unmapped).
    WebhookEvent = Data.define(:value, :canonical_status, :confidence, :source) do
      include Base
    end
  end
end
