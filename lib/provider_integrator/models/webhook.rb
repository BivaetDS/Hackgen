# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # The inbound notification endpoint: how it was found (`source` override | extension | callbacks |
    # path_heuristic | tag_heuristic | operation_id_heuristic), its signature, event/status/id field paths,
    # payload fields and examples.
    # `method` is the IR key for the HTTP verb (docs/IR_CONTRACT.md). Shadowing Object#method on IR
    # values is accepted: nothing introspects them through #method.
    # rubocop:disable-next Lint/DataDefineOverride
    Webhook = Data.define(:path, :method, :operation_id, :summary, :source, :confidence, :evidence, :signature,
                          :event_field, :events, :status_field, :id_field, :external_id_field, :error_code_path,
                          :error_message_path, :payload_fields, :examples, :response) do
      include Base

      nested :signature, Signature
      nested_list :events, WebhookEvent
      nested_list :payload_fields, FieldMapping
      nested :response, WebhookResponse
    end
  end
end
