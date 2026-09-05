# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # "Field is required when <when> equals <equals>"; `source` is description | discriminator |
    # if_then | override.
    ConditionalRequired = Data.define(:when, :equals, :source, :confidence, :evidence) do
      include Base
    end
  end
end
