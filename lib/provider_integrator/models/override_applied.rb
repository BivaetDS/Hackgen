# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Record of one overrides.yml entry that changed the IR (`key` is the overrides section).
    OverrideApplied = Data.define(:key, :target, :value, :note) do
      include Base
    end
  end
end
