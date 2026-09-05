# frozen_string_literal: true

module ProviderIntegrator
  # Immutable IR models (Data.define). ProviderSpec is the root of the JSON-serializable
  # intermediate representation produced by the parser and consumed by the generator; every model
  # round-trips through to_h/from_h and canonical JSON byte-for-byte (see docs/IR_CONTRACT.md).
  module Models
  end
end
