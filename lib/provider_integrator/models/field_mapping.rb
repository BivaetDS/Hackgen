# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One flattened schema field (`provider_path` such as "recipient.bank_code" or "items[]")
    # with its canonical name (fields.yml) or nil, schema facts, and the inferred conversion,
    # conditional requirement and oneOf branch. `required` is relative to the enclosing object.
    FieldMapping = Data.define(:provider_path, :canonical, :type, :format, :required, :nullable, :enum, :constant,
                               :pattern, :minimum, :maximum, :min_length, :max_length, :description, :example,
                               :default, :conversion, :conditional_required, :branch, :confidence, :evidence,
                               :source) do
      include Base

      nested :conversion, Conversion
      nested :conditional_required, ConditionalRequired
      nested :branch, Branch
    end
  end
end
