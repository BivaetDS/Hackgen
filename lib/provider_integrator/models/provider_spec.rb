# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # Root of the IR (ir_version 1). The parser produces it, the generator reads only it.
    # Serialize with #to_canonical_json; parse with .from_json / .from_h.
    ProviderSpec = Data.define(:ir_version, :provider, :spec_format, :servers, :authentication, :operations,
                               :statuses, :webhook, :gateway_config, :overrides_applied, :events, :extensions) do
      include Base

      nested :provider, Provider
      nested :spec_format, SpecFormat
      nested_list :servers, Server
      nested :authentication, Authentication
      nested_list :operations, Operation
      nested_list :statuses, StatusMapping
      nested :webhook, Webhook
      nested :gateway_config, GatewayConfig
      nested_list :overrides_applied, OverrideApplied
      nested_list :events, Event

      # Operations that back a BaseService method, in spec order.
      def contract_operations = operations.select(&:in_contract)

      # The in-contract operation behind +canonical_method+ ("create_request", ...), or nil.
      def operation_for(canonical_method)
        contract_operations.find { |operation| operation.canonical_method == canonical_method }
      end

      # Operations of the given +kind+, in spec order.
      def operations_of_kind(kind) = operations.select { |operation| operation.kind == kind }
    end
  end
end
