# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Public methods for the operations outside the BaseService contract (cancel, balance, refund,
    # list, unknown, second create candidates): one request method plus a parse helper each,
    # named by the canon (cancel_request, fetch_balance, ...) or from the operationId.
    class ExtraMethods
      Entry = Data.define(:operation, :name, :url, :payload, :params)

      def initialize(service)
        @service = service
        @canon = service.canon
        @names = service.canon.contract_methods.dup
        @entries = service.context.extra_operations.each_with_index.map { |operation, index| entry(operation, index) }
      end

      def public_methods_data
        @entries.map { |entry| request_method(entry) }
      end

      def private_methods_data
        @entries.flat_map { |entry| [entry.payload, parse_method(entry)].compact }
      end

      private

      attr_reader :service, :canon

      def entry(operation, index)
        name = unique_name(operation, index)
        url = Url.new(operation, canon:)
        service.add_notes(url.comments)
        payload = payload_method(operation, name)
        Entry.new(operation:, name:, url:, payload:, params: params(operation, url, payload))
      end

      def unique_name(operation, index)
        fallback = "extra_#{index}"
        candidates = [operation.canonical_method, Inflector.identifier(operation.operation_id, fallback:)].compact
        name = candidates.find { |candidate| !@names.include?(candidate) } || "#{candidates.last}_#{index}"
        @names << name
        name
      end

      def params(operation, url, payload)
        list = []
        list << "operation" if url.operation? || payload
        list << "request_method" if payload && requisites?(operation)
        list << "params = {}" if query?(operation)
        list.join(", ")
      end

      def requisites?(operation)
        operation.request_fields.any? { |field| field.canonical.to_s.start_with?("requisite.") }
      end

      def query?(operation)
        operation.method == "GET" && operation.parameters.any? { |item| item.in == "query" && !item.canonical }
      end

      def payload_method(operation, name)
        return nil unless operation.request_body && !operation.request_fields.empty?

        result = PayloadBuilder.new(operation, canon:, context: service.context, scope: service.scope).call
        register(result, name)
        payload_data(name, "Body of #{operation.method} #{operation.path}.", result)
      end

      def payload_data(name, title, result)
        MethodData.build(name: "build_#{name}_payload", params: "operation, request_method = nil",
                         comment: [title, *result.notes], lines: result.lines)
      end

      def register(result, name)
        service.add_env_constants(result.env_constants)
        service.add_amount_helpers(result.helpers)
        service.payload_docs[["extra", name]] = result.docs
      end

      def request_method(entry)
        MethodData.build(name: entry.name, params: entry.params, comment: comment(entry.operation),
                         lines: request_lines(entry), rescues: service.rescues)
      end

      def comment(operation)
        [
          "Outside the #{canon.base_service} contract (kind #{operation.kind}): " \
          "#{operation.method} #{operation.path} (#{operation.operation_id}).",
          operation.summary,
          Generator::Confidence.todo_if_needed(operation.confidence, "operation kind #{operation.kind} with " \
                                                                     "confidence #{operation.confidence}")
        ].compact
      end

      def request_lines(entry)
        operation = entry.operation
        [*payload_line(entry), *url_lines(entry),
         Requests.call_line(operation, url: "url", headers: headers(operation), canon:,
                                       payload: entry.payload ? "payload" : nil),
         "parse_#{entry.name}_response(response)"]
      end

      def payload_line(entry)
        return [] unless entry.payload

        arguments = requisites?(entry.operation) ? "operation, request_method" : "operation"
        ["payload = #{entry.payload.name}(#{arguments})"]
      end

      def url_lines(entry)
        expression = entry.url.expression
        expression = "with_api_key(#{expression})" if service.need?(:auth_query)
        lines = ["url = #{expression}"]
        return lines unless query?(entry.operation)

        service.require("uri")
        lines << "url = \"\#{url}?\#{URI.encode_www_form(params)}\" unless params.empty?"
      end

      def headers(operation)
        idempotency = operation.idempotency
        return "auth_headers" unless idempotency && idempotency.location == "header" && operation.method != "GET"

        service.need(:idempotency, idempotency) unless service.need?(:idempotency)
        "auth_headers.merge(idempotency_headers(operation))"
      end

      def parse_method(entry)
        operation = entry.operation
        status = service.status_path(operation)
        outcome = status ? "status: map_status(#{Code.access("body", status)}), response: body" : "response: body"
        guard = "return provider_error(response) unless #{Requests.success_check(operation.success_codes)}"
        MethodData.build(name: "parse_#{entry.name}_response", params: "response",
                         lines: ["body = response.body || {}", guard, "", "#{canon.success}(#{outcome})"])
      end
    end
  end
end
