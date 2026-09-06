# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # `describe '#create_request'`: the request the service sends (URL, headers, body fields),
    # success on the first success status, idempotent duplicates as success, one example per
    # error response of fixtures.json, and an unknown request_method refused without a request.
    class SpecCreateExamples < SpecExamples
      FIXTURE = "create_request"

      def method_name = "create_request"

      def examples
        @examples ||= if stub?
                        [stub_example]
                      else
                        [request_example, *success_examples, *error_examples, *unsupported_example]
                      end
      end

      # Russian summary for INTEGRATION.md ("Тесты").
      def summary
        return "заглушка (`NotImplementedError`)" if stub?

        ["запрос (URL, заголовки, тело)", "успех #{operation.success_codes.first}", duplicate_summary, error_summary,
         ("неизвестный request_method" if operation.request_methods)].compact.join(", ")
      end

      protected

      def children
        return examples unless operation

        lets = [let("url", [request.url_expression(operation)])]
        headers = request.headers_literal(operation)
        lets << let("request_headers", [headers]) if headers
        lets + examples
      end

      private

      def operation = data.context.create_operation
      def stub? = operation.nil? || Generator::Confidence.stub?(operation.confidence)

      def duplicate_summary
        codes = operation.idempotent_duplicate_codes
        codes.empty? ? nil : "дубль #{codes.join("/")}"
      end

      def error_summary
        codes = error_responses(operation, FIXTURE).map { |error, _| error.http }
        codes.empty? ? nil : "ошибки #{codes.join(", ")}"
      end

      def call
        argument = operation.request_methods ? ", #{Code.str(subject.request_method)}" : ""
        "service.create_request(operation#{argument})"
      end

      def stub_example
        example("raises NotImplementedError: the spec has no reliable create operation",
                ["expect { service.create_request(operation) }.to raise_error(NotImplementedError)"])
      end

      def request_example
        verb = operation.method.upcase
        lines = [stub_line(operation, operation.success_codes.first, FIXTURE), "", call, "", made_expectation]
        request.body_groups.each { |container, pairs| lines.concat(body_expectation(container, pairs)) }
        example("#{verb}s the create request of fixtures.json with the auth headers", lines)
      end

      # "expect(a_request(:post, url).with(headers: request_headers)).to have_been_made.once".
      def made_expectation
        options = []
        options << "query: auth_query" if request.query?
        options << "headers: request_headers" if request.headers_literal(operation)
        with = options.empty? ? "" : ".with(#{options.join(", ")})"
        "expect(a_request(#{request.verb_literal(operation)}, url)#{with}).to have_been_made.once"
      end

      def body_expectation(container, pairs)
        receiver = container ? Code.access("sent_body", container) : "sent_body"
        entries = pairs.map { |leaf, value| "#{Code.str(leaf)} => #{Code.literal(value)}" }
        Code.hash_lines(entries, open: "expect(#{receiver}).to include(", close: ")")
      end

      def success_examples
        operation.success_codes.map do |code|
          body = data.fixture(FIXTURE, "response_#{code}") or next
          duplicate = operation.idempotent_duplicate_codes.include?(code)
          example(success_description(code, duplicate), success_lines(code, body))
        end.compact
      end

      def success_description(code, duplicate)
        return "treats HTTP #{code} (idempotent duplicate) as success" if duplicate

        "returns success with the provider id and the mapped status of response_#{code}"
      end

      def success_lines(code, body)
        [stub_line(operation, code, FIXTURE), "", "result = #{call}", "",
         *success_expectations(operation, body, with_id: true)]
      end

      def error_examples
        error_responses(operation, FIXTURE).map do |error, body|
          extra = error.retry_after == "header" ? " with Retry-After" : nil
          example(error_description(error, extra), error_lines(operation, FIXTURE, error, body, call))
        end
      end

      def unsupported_example
        return [] unless operation.request_methods

        parts = canon.service_failure_parts("unsupported_request_method")
        [example("refuses an unknown request_method without calling the provider",
                 ["result = service.create_request(operation, #{Code.str("unsupported")})", "",
                  failure_expectation(parts), "expect(WebMock).not_to have_requested(:any, /./)"])]
      end
    end
  end
end
