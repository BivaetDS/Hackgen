# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Version of the analysed document: `openapi` is the effective OpenAPI version string and
    # `converted_from` is "2.0" when a Swagger document was converted first, else nil.
    SpecFormat = Data.define(:openapi, :converted_from) do
      include Base
    end
  end
end
