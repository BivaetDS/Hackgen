# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Request body summary: media type, schema component name, the first example and all named examples.
    RequestBody = Data.define(:content_type, :required, :schema_name, :example, :examples) do
      include Base
    end
  end
end
