# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # `describe '#fetch_status'`: the GET with the auth headers and the mapped status of the
    # fixture response, plus one example per error response; a NotImplementedError expectation
    # when the spec has no status operation (W106).
    class SpecStatusExamples < SpecExamples
      FIXTURE = "fetch_status"

      def method_name = "fetch_status"

      def examples
        @examples ||= stub? ? [stub_example] : [success_example, *error_examples].compact
      end

      def summary
        return "заглушка (`NotImplementedError`, W106)" if stub?

        codes = error_responses(operation, FIXTURE).map { |error, _| error.http }
        parts = ["запрос с авторизацией", "статус из response_#{operation.success_codes.first}"]
        parts << "ошибки #{codes.join(", ")}" unless codes.empty?
        parts.join(", ")
      end

      protected

      def children
        return examples unless operation

        [let("url", [request.url_expression(operation)]), *examples]
      end

      private

      def operation = data.context.status_operation
      def stub? = operation.nil? || Generator::Confidence.stub?(operation.confidence)
      def call = "service.fetch_status(operation)"

      def stub_example
        example("raises NotImplementedError: the spec has no status operation (W106)",
                ["expect { #{call} }.to raise_error(NotImplementedError)"])
      end

      def success_example
        code = operation.success_codes.first
        body = data.fixture(FIXTURE, "response_#{code}") or return nil
        lines = [stub_line(operation, code, FIXTURE), "", "result = #{call}", "", made_expectation,
                 *success_expectations(operation, body)]
        example("#{operation.method.upcase}s the operation with the auth headers and maps the status of " \
                "response_#{code}", lines)
      end

      def made_expectation
        options = []
        options << "query: auth_query" if request.query?
        headers = request.headers_literal(operation)
        options << "headers: #{headers}" if headers
        with = options.empty? ? "" : ".with(#{options.join(", ")})"
        "expect(a_request(#{request.verb_literal(operation)}, url)#{with}).to have_been_made.once"
      end

      def error_examples
        error_responses(operation, FIXTURE).map do |error, body|
          example(error_description(error), error_lines(operation, FIXTURE, error, body, call))
        end
      end
    end
  end
end
