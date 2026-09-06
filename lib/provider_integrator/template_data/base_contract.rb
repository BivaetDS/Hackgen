# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Names for base_contract.rb.erb, all taken from canonical_contract.yml: the stub of the
    # platform contract (BaseService, Result, Operation, Response, exceptions) plus the Net::HTTP
    # client (docs/ASSUMPTIONS.md, допущение 23) that lets a generated service load and run its
    # spec through WebMock without Space Payments' real code.
    class BaseContract
      # The stub client class; not a canon name (the canon only knows `client`), so it lives here
      # and the generated spec reads it from the same constant.
      HTTP_CLIENT = "HttpClient"
      REQUIRES = %w[json net/http uri].freeze
      # How each member of Response is filled from a Net::HTTPResponse, by canon member name.
      RESPONSE_SOURCES = { "status" => "response.code.to_i", "body" => "parse_body(response.body)",
                           "headers" => "response.each_header.to_h" }.freeze

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
      def requires = REQUIRES
      def http_client = HTTP_CLIENT

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

      # "get" / "post": the method names out of the canon signatures ("client.post(url, json:, headers:)").
      def client_get = client_method_name("get")
      def client_post = client_method_name("post")

      # "json" / "form": the body keyword of client.post per media type (canon content_types).
      def json_keyword = canon.client_argument("application/json")
      def form_keyword = canon.client_argument("application/x-www-form-urlencoded")

      # "status: response.code.to_i, body: parse_body(response.body), headers: ..." in canon member order.
      def response_arguments
        response_members.map { |member| "#{member}: #{RESPONSE_SOURCES.fetch(member)}" }.join(", ")
      end

      private

      attr_reader :context, :canon

      def client_method_name(key)
        signature = canon.client_helpers.fetch(key)
        signature[/\Aclient\.(\w+)\(/, 1] or raise GenerationError, "cannot read the client method out of #{signature}"
      end
    end
  end
end
