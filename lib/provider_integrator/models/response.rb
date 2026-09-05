# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One declared response: `kind` is success | idempotent_duplicate | error | other, `example`
    # the media-type example (or one composed from property examples) or nil.
    Response = Data.define(:http, :description, :schema_name, :kind, :content_type, :example, :headers) do
      include Base

      nested_list :headers, ResponseHeader
    end
  end
end
