# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # fetch_status and parse_status_response: GET the operation by its provider id, map the status
    # through STATUS_MAP, hand errors to provider_error. A stub when the spec has no status operation.
    class StatusMethod
      def initialize(service)
        @service = service
        @operation = service.context.status_operation
        @canon = service.canon
      end

      def public_methods_data
        return [stub] unless operation

        [MethodData.build(name: "fetch_status", params: "operation", comment: comment, lines: body_lines,
                          rescues: service.rescues)]
      end

      def private_methods_data
        return [] unless operation

        [MethodData.build(name: "parse_status_response", params: "operation, response", lines: parse_lines)]
      end

      private

      attr_reader :service, :operation, :canon

      def comment
        lines = ["#{operation.method} #{operation.path} (#{operation.operation_id})."]
        lines << Generator::Confidence.todo_if_needed(operation.confidence,
                                                      "operation classified as status with confidence " \
                                                      "#{operation.confidence}; confirm it returns the payout state")
        lines.compact
      end

      def body_lines
        if Generator::Confidence.stub?(operation.confidence)
          return ["raise NotImplementedError, #{Code.str("fetch_status: the spec has no reliable status operation")}"]
        end

        [Requests.call_line(operation, url: url, headers: "auth_headers", canon:),
         "parse_status_response(operation, response)"]
      end

      def url
        builder = Url.new(operation, canon:)
        service.add_notes(builder.comments)
        service.need?(:auth_query) ? "with_api_key(#{builder.expression})" : builder.expression
      end

      def parse_lines
        status = service.status_path(operation)
        ["body = response.body || {}",
         "return provider_error(response) unless #{Requests.success_check(operation.success_codes)}",
         "",
         *status_note(status),
         "#{canon.success}(status: #{status_expression(status)}, response: body)"]
      end

      def status_note(status)
        return [] if status

        [Generator::Confidence.todo(0.0,
                                    "the status response declares no status field; #{canon.default_status} assumed")]
      end

      def status_expression(status)
        status ? "map_status(#{Code.access("body", status)})" : Code.str(canon.default_status)
      end

      def stub
        MethodData.build(name: "fetch_status", params: "operation",
                         comment: [Generator::Confidence.todo(0.0, "the spec has no status operation (W106); " \
                                                                   "rely on process_callback")],
                         lines: ["raise NotImplementedError, " \
                                 "#{Code.str("fetch_status: no status operation in the spec")}"])
      end
    end
  end
end
