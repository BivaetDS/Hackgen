# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # A declared OpenAPI parameter (`in` path | query | header | cookie) with its optional
    # canonical role (provider_operation_id, idempotency_key, signature, ...).
    Parameter = Data.define(:name, :in, :required, :type, :format, :description, :example, :enum, :canonical) do
      include Base
    end
  end
end
