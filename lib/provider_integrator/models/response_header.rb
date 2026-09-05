# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # A declared response header; `canonical` is "retry_after" for Retry-After, else nil.
    ResponseHeader = Data.define(:name, :type, :description, :canonical) do
      include Base
    end
  end
end
