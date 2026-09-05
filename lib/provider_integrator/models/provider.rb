# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Identity of the provider: info.title, the slug used for class/file names, info.version and
    # the stripped info.description (nil when absent).
    Provider = Data.define(:title, :slug, :version, :description) do
      include Base
    end
  end
end
