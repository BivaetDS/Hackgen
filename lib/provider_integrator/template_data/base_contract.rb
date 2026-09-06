# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Names for base_contract.rb.erb, all taken from canonical_contract.yml: the stub of the
    # platform contract (BaseService, Result, Operation, Response, exceptions) that lets a generated
    # service load and run its specs without Space Payments' real code.
    class BaseContract
      def initialize(context)
        @context = context
        @canon = Canon.new
      end

      def namespace = canon.namespace
      def base_service = canon.base_service
      def statuses_literal = "#{Code.word_array(canon.statuses)}.freeze"
      def success = canon.success
      def failure = canon.failure
      def failed_predicate = canon.failed_predicate
      def approve = canon.approve
      def reject = canon.reject
      def credentials = canon.credentials
      def default_status = Code.str(canon.default_status)
      def approved = Code.str(canon.statuses.fetch(1))
      def rejected = Code.str(canon.statuses.fetch(2))

      # ["RateLimitError", "UnauthorizedError"] - the exception classes without the namespace.
      def exception_names
        canon.exceptions.values.map { |name| name.delete_prefix("#{namespace}::") }
      end

      # Members of the platform Operation, from the accessors the canon declares (operation.id -> :id).
      def operation_members
        canon.accessors.values.map { |accessor| accessor.split(".", 2).last }.uniq
      end

      # Contract method signatures with unused parameters underscored, in canon order.
      def contract_signatures
        canon.contract_methods.map do |name|
          canon.signature(name, default_request_method: "nil").gsub(/\b(operation|request_method|payload)\b/, '_\1')
        end
      end

      # Credentials keys this provider needs, for the header comment.
      def credential_keys
        auth = context.spec.authentication
        keys = canon.credential_keys(auth.type)
        keys += [canon.callback_secret_key] if context.spec.webhook&.signature
        keys.uniq
      end

      def client_methods = canon.client_helpers.values_at("get", "post", "post_form").compact
      def response_members = canon.client_helpers.fetch("response")

      private

      attr_reader :context, :canon
    end
  end
end
