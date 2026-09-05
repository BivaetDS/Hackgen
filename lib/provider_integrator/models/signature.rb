# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Webhook signature convention as far as the spec states it; `encoding`/`message` stay
    # "unknown" when not specified (the generator applies the canon defaults and reports W301).
    Signature = Data.define(:location, :name, :algorithm, :encoding, :message, :secret, :confidence, :evidence,
                            :source) do
      include Base
    end
  end
end
