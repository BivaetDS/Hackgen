# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One HTTP operation of the spec with its classified `kind` (create | status | cancel | balance |
    # webhook | refund | list | unknown), contract role, parameters, flattened request/response
    # fields, declared responses and the canonical error table.
    # `method` is the IR key for the HTTP verb (docs/IR_CONTRACT.md). Shadowing Object#method on IR
    # values is accepted: nothing introspects them through #method.
    # rubocop:disable-next Lint/DataDefineOverride
    Operation = Data.define(:kind, :in_contract, :canonical_method, :operation_id, :method, :path, :summary,
                            :description, :tags, :security, :public, :classification, :idempotency, :parameters,
                            :request_body, :request_fields, :response_fields, :responses, :success_codes,
                            :idempotent_duplicate_codes, :errors, :request_methods, :confidence) do
      include Base

      nested :classification, Classification
      nested :idempotency, Idempotency
      nested_list :parameters, Parameter
      nested :request_body, RequestBody
      nested_list :request_fields, FieldMapping
      nested_list :response_fields, FieldMapping
      nested_list :responses, Response
      nested_list :errors, ErrorMapping
      nested :request_methods, RequestMethods
    end
  end
end
