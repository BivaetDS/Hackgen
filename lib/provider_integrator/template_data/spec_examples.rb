# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Shared vocabulary of the example builders of the generated spec: stubbing a fixture
    # response, calling the service, and the expectations on a Result (success with the mapped
    # status, failure with the canon symbol and i18n code, provider code and Retry-After). Each
    # subclass builds one `describe` group for one contract method.
    class SpecExamples
      EXAMPLE_LEVEL = 2
      RETRY_AFTER_STUB = "60"

      def initialize(data)
        @data = data
        @spec = data.spec
        @canon = data.canon
        @service = data.service
        @subject = data.subject
        @request = data.request
      end

      # The `describe` group of this method (a SpecBlock::Group) and how many examples it holds.
      def group = SpecBlock::Group.build("describe #{Code.str("##{method_name}")}", children)
      def count = examples.size

      protected

      attr_reader :data, :spec, :canon, :service, :subject, :request

      def children = examples
      def let(name, lines) = SpecBlock::Let.build(name, lines, level: EXAMPLE_LEVEL)

      def example(description, lines)
        SpecBlock::Block.build("it #{Code.str(description)}", lines, level: EXAMPLE_LEVEL)
      end

      # "fixture('create_request', 'response_201')" - the example of fixtures.json the stub answers with.
      def fixture_call(*keys) = "fixture(#{keys.map { |key| Code.str(key) }.join(", ")})"

      # "stub_provider(:post, url, 201, fixture('create_request', 'response_201'))".
      def stub_line(target, code, key, headers: nil)
        arguments = [request.verb_literal(target), "url", code.to_s, fixture_call(key, "response_#{code}")]
        arguments << "headers: #{headers}" if headers
        "stub_provider(#{arguments.join(", ")})"
      end

      # "expect([result.error, result.code]).to eq([:too_many_requests, 'provider.rate_limit'])".
      def failure_expectation(parts)
        "expect([result.error, result.code]).to eq([#{parts.join(", ")}])"
      end

      # Expectations on a success Result for +body+ (a fixture success example of +target+).
      def success_expectations(target, body, with_id: false)
        lines = ["expect(result).to be_success"]
        id = with_id && provider_id(target, body)
        lines << "expect(result.provider_operation_id).to eq(#{Code.literal(id)})" if id
        lines << "expect(result.status).to eq(#{Code.str(expected_status(target, body))})"
      end

      def provider_id(target, body)
        path = service.provider_id_path(target) or return nil
        CallbackOutcome.dig(body, path)
      end

      # What map_status answers for the status value of +body+: STATUS_MAP or the default status.
      def expected_status(target, body)
        path = service.status_path(target) or return canon.default_status
        value = CallbackOutcome.dig(body, path).to_s
        spec.statuses.find { |mapping| mapping.provider == value }&.canonical || canon.default_status
      end

      # Stub and expectations for one error response of +target+ (as provider_error will map it).
      def error_lines(target, key, error, body, call)
        header, retry_after = retry_after_for(error, body)
        headers = header && "{ #{Code.str(retry_after_header)} => #{Code.str(header)} }"
        stub = stub_line(target, error.http, key, headers:)
        lines = [stub, "", "result = #{call}", "", failure_expectation(failure_parts(error.http))]
        code = provider_code(body)
        lines << "expect(result.details[:provider_code]).to eq(#{Code.str(code)})" if code
        lines << "expect(result.details[:retry_after]).to eq(#{retry_after})" if retry_after
        lines
      end

      # "maps HTTP 429 to failure(:too_many_requests, provider.rate_limit)".
      def error_description(error, extra = nil)
        symbol, i18n = failure_parts(error.http)
        "maps HTTP #{error.http} to failure(#{symbol}, #{i18n.delete("'")})#{extra}"
      end

      # [symbol, i18n] source of the failure provider_error returns for +http+.
      def failure_parts(http)
        mapped = data.error_mappings[http]&.canonical || default_canonical(http >= 500 ? "5xx" : "4xx")
        canon.failure_parts(canon.error_codes.include?(mapped) ? mapped : default_canonical("4xx"))
      end

      def default_canonical(range) = Dictionaries.errors.dig("http", "default_#{range}", "canonical")

      def provider_code(body)
        path = service.error_code_path or return nil
        CallbackOutcome.dig(body, path)&.to_s
      end

      # [stubbed header value, expected seconds] following retry_after_seconds: the header (stubbed
      # only when this error names it) first, then the body field the spec declares.
      def retry_after_for(error, body)
        sources = service.helpers.retry_after_sources
        return [nil, nil] if sources.empty?

        header = error.retry_after == "header" ? RETRY_AFTER_STUB : nil
        body_value = sources.include?("body") ? body[service.helpers.retry_after_field] : nil
        [header, (header || body_value)&.to_i]
      end

      def retry_after_header = service.helpers.retry_after_header

      # Error responses of +target+ that fixtures.json carries, with their ErrorMapping.
      def error_responses(target, key)
        target.responses.select { |response| response.kind == "error" }.filter_map do |response|
          error = target.errors.find { |item| item.http == response.http } or next
          body = data.fixture(key, "response_#{response.http}") or next
          [error, body]
        end
      end
    end
  end
end
