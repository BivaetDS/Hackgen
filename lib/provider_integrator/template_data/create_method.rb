# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # create_request and its private companions: one build_<method>_payload per payout method
    # (or a single build_<payout|deposit>_payload), and parse_create_response, which treats the
    # idempotent-duplicate status as success and hands everything else to provider_error.
    class CreateMethod
      def initialize(service)
        @service = service
        @operation = service.context.create_operation
        @canon = service.canon
      end

      def public_methods_data
        return [stub] unless operation

        [MethodData.build(name: "create_request", params: signature_params, comment: comment, lines: body_lines,
                          rescues: service.rescues)]
      end

      def private_methods_data
        return [] unless operation

        payload_methods + [parse_method]
      end

      private

      attr_reader :service, :operation, :canon

      def methods = operation.request_methods
      def branches = methods ? methods.values : [nil]

      def signature_params
        default = Code.str(service.default_request_method)
        signature = canon.signature("create_request", default_request_method: default)
        signature.delete_prefix("create_request(").delete_suffix(")")
      end

      def comment
        todo = Generator::Confidence.todo_if_needed(operation.confidence,
                                                    "operation classified as create with confidence " \
                                                    "#{operation.confidence}; confirm it creates a payout")
        ["#{operation.method} #{operation.path} (#{operation.operation_id}).", todo].compact
      end

      def body_lines
        return low_confidence_lines if Generator::Confidence.stub?(operation.confidence)

        call = Requests.call_line(operation, url: url, headers: headers, canon:, payload: "payload")
        payload_lines + header_lines + [call, "parse_create_response(operation, response)"]
      end

      def payload_lines
        return ["payload = #{single_payload_name}(operation)"] unless methods

        lines = ["payload =", "  case request_method"]
        branches.each { |branch| lines << "  when #{Code.str(branch)} then #{payload_name(branch)}(operation)" }
        lines << "  end"
        lines << "return #{canon.failure_for_service_code("unsupported_request_method")} if payload.nil?"
        lines << ""
      end

      def low_confidence_lines
        ["raise NotImplementedError, #{Code.str("create_request: the spec has no reliable create operation")}"]
      end

      def url
        builder = Url.new(operation, canon:)
        service.add_notes(builder.comments)
        service.need?(:auth_query) ? "with_api_key(#{builder.expression})" : builder.expression
      end

      def headers = header_lines.empty? ? "auth_headers" : "headers"

      # "headers = auth_headers.merge(idempotency_headers(operation))" when the create call carries a key.
      def header_lines
        return [] unless operation.idempotency&.location == "header"

        service.need(:idempotency, operation.idempotency)
        ["headers = auth_headers.merge(idempotency_headers(operation))"]
      end

      def single_payload_name
        "build_#{service.spec.gateway_config&.direction == "deposit" ? "deposit" : "payout"}_payload"
      end

      def payload_name(branch) = "build_#{Inflector.identifier(branch)}_payload"

      def payload_methods
        branches.map do |branch|
          result = PayloadBuilder.new(operation, canon:, context: service.context, scope: service.scope(branch:)).call
          register(result, branch)
          name = branch ? payload_name(branch) : single_payload_name
          MethodData.build(name:, params: "operation", comment: payload_comment(branch, result), lines: result.lines)
        end
      end

      def register(result, branch)
        service.add_env_constants(result.env_constants)
        service.add_amount_helpers(result.helpers)
        service.payload_docs[["create", branch]] = result.docs
      end

      def payload_comment(branch, result)
        schema = operation.request_body&.schema_name
        target = branch ? "request_method #{Code.str(branch)}" : "the single payout method of the spec"
        schema_note = schema && " (schema #{schema})"
        ["Body of #{operation.method} #{operation.path} for #{target}#{schema_note}.", *result.notes]
      end

      def parse_method
        MethodData.build(name: "parse_create_response", params: "operation, response", lines: parse_lines,
                         comment: ["Success statuses #{operation.success_codes.join(", ")}; everything else goes " \
                                   "through ERROR_MAP."])
      end

      def parse_lines
        success = operation.success_codes
        lines = ["body = response.body || {}", "case response.status"]
        lines << "# #{duplicate_note}" unless operation.idempotent_duplicate_codes.empty?
        lines << "when #{success.join(", ")} then #{success_call}"
        lines << "else provider_error(response)"
        lines << "end"
      end

      def duplicate_note
        "#{operation.idempotent_duplicate_codes.join(", ")}: duplicate by idempotency key - the provider returns " \
          "the original result, treated as success."
      end

      def success_call
        id = service.provider_id_path(operation)
        status = service.status_path(operation)
        parts = ["provider_operation_id: #{id ? Code.access("body", id) : "nil"}"]
        parts << "status: #{status ? "map_status(#{Code.access("body", status)})" : Code.str(canon.default_status)}"
        parts << "response: body"
        "#{canon.success}(#{parts.join(", ")})"
      end

      def stub
        MethodData.build(name: "create_request", params: "operation, request_method = nil",
                         comment: [Generator::Confidence.todo(0.0, "the spec has no create operation (E101)")],
                         lines: ["raise NotImplementedError, " \
                                 "#{Code.str("create_request: no create operation in the spec")}"])
      end
    end
  end
end
