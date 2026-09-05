# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Semantic value conversion for a money field (never Ruby code): `type` multiply | divide |
    # to_decimal_string | identity between `unit_from` and `unit_to` (major | minor).
    Conversion = Data.define(:type, :value, :unit_from, :unit_to, :confidence, :evidence, :source) do
      include Base
    end
  end
end
