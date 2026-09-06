# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Read-only view of dictionaries/canonical_contract.yml as Ruby source fragments: the names
    # of the platform side (helpers, accessors, credentials, codes) never appear in templates or
    # generators as literals, they are looked up here.
    class Canon
      def initialize(data = Dictionaries.canonical_contract)
        @data = data
      end

      # "Provider" and "BaseService" from base_service.class_name.
      def namespace = class_name_parts.first
      def base_service = class_name_parts.last
      def base_service_class = @data.dig("base_service", "class_name")
      def contract_methods = @data.dig("base_service", "methods")
      def contract_role(kind) = @data.dig("contract_roles", kind)
      def extra_method(kind) = @data.dig("extra_methods", kind)
      def statuses = @data.fetch("statuses")
      def default_status = @data.fetch("default_status")
      def success = @data.dig("helpers", "result", "success")
      def failure = @data.dig("helpers", "result", "failure")
      def failed_predicate = @data.dig("helpers", "result", "failed_predicate")
      def approve = @data.dig("helpers", "callbacks", "approve")
      def reject = @data.dig("helpers", "callbacks", "reject")
      def credentials = @data.dig("helpers", "credentials")
      def exception(canonical) = @data.dig("helpers", "exceptions", canonical)
      def exceptions = @data.dig("helpers", "exceptions")
      def client_argument(content_type) = @data.dig("helpers", "client", "content_types", content_type)
      def client_helpers = @data.dig("helpers", "client")
      def amount_unit = @data.dig("operation", "amount_unit")
      def accessor(canonical) = @data.dig("operation", "accessors", canonical)
      def accessors = @data.dig("operation", "accessors")
      def action_label(action) = @data.dig("actions", action, "label")
      def action_retry?(action) = @data.dig("actions", action, "retry")
      def callback_key(name) = @data.dig("callback_payload", "#{name}_key")
      def signature_default(name) = @data.dig("signature_defaults", name)
      def gateway_template(direction) = @data.dig("gateway_config", direction)
      def env_template(key) = @data.dig("env", key.to_s)

      # "create_request(operation, request_method = 'sbp')" from the canon signature template.
      def signature(method_name, default_request_method: nil)
        template = @data.dig("base_service", "signatures", method_name)
        raise GenerationError, "no signature for #{method_name} in canonical_contract.yml" unless template

        format(template, default_request_method: default_request_method.to_s)
      end

      # "operation.payout_requisite.dig('sbp', 'phone')" with already-rendered Ruby arguments.
      def requisite_access(method_expression, field_expression)
        format(@data.dig("operation", "requisite_access"), method: method_expression, field: field_expression)
      end

      # "credentials[:api_key]" for a credentials key.
      def credential(key) = "#{credentials}[:#{key}]"

      # Credentials keys the authentication type needs (["api_key"], ["login", "password"], ...).
      def credential_keys(auth_type) = Array(@data.dig("credentials", auth_type))
      def callback_secret_key = @data.dig("credentials", "callback_secret")
      def merchant_account_key = @data.dig("credentials", "merchant_account")

      # "failure(:too_many_requests, 'provider.rate_limit')" for a canonical error code; +details+
      # is optional already-rendered keyword source appended as the third argument.
      def failure_for_error(canonical, details = nil)
        entry = @data.dig("error_codes", canonical) or raise GenerationError, "unknown canonical error #{canonical}"
        failure_call(entry, details)
      end

      # "failure(:unprocessable_entity, 'unknown_event')" for a code the service returns itself.
      def failure_for_service_code(code, details = nil)
        entry = @data.dig("service_codes", code) or raise GenerationError, "unknown service code #{code}"
        failure_call(entry, details)
      end

      # [":too_many_requests", "'provider.rate_limit'"] - the two arguments of failure for a canonical
      # error code, as Ruby source, for callers that assert on them (the generated spec).
      def failure_parts(canonical)
        entry = @data.dig("error_codes", canonical) or raise GenerationError, "unknown canonical error #{canonical}"
        failure_arguments(entry)
      end

      # The same for a code the service returns itself ([":unprocessable_entity", "'unknown_event'"]).
      def service_failure_parts(code)
        entry = @data.dig("service_codes", code) or raise GenerationError, "unknown service code #{code}"
        failure_arguments(entry)
      end

      # Canonical error codes known to the platform, in dictionary order.
      def error_codes = @data.fetch("error_codes").keys
      def service_codes = @data.fetch("service_codes")
      def actions = @data.fetch("actions")

      private

      def failure_call(entry, details)
        "#{failure}(#{[*failure_arguments(entry), details].compact.join(", ")})"
      end

      def failure_arguments(entry)
        [":#{entry.fetch("failure")}", Inflector.ruby_string(entry.fetch("i18n"))]
      end

      def class_name_parts = @data.dig("base_service", "class_name").split("::")
    end
  end
end
