# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The private helpers every request path shares: auth_headers (by securitySchemes type),
    # idempotency headers, map_status, provider_error (ERROR_MAP -> failure), Retry-After and
    # error-code readers, and the amount conversion helpers the payloads asked for.
    class ServiceHelpers
      QUERY_TEMPLATE = '"#{url}#{url.include?(\'?\') ? \'&\' : \'?\'}#{URI.encode_www_form(%{pair})}"'

      def initialize(service)
        @service = service
        @canon = service.canon
        @auth = service.spec.authentication
      end

      def methods_data
        [*auth_methods, idempotency_method, map_status_method, provider_error_method, retry_after_method,
         error_code_method, *amount_methods].compact
      end

      # Where Retry-After comes from anywhere in the spec (["body", "header"] subset, sorted); the
      # generated spec stubs and expects the same sources.
      def retry_after_sources
        @retry_after_sources ||= service.spec.operations.flat_map(&:errors).map(&:retry_after).compact.uniq.sort
      end

      # The response header retry_after_seconds reads (the spec's name for it, else Retry-After).
      def retry_after_header
        headers = service.spec.operations.flat_map(&:responses).flat_map(&:headers)
        headers.find { |header| header.canonical == "retry_after" }&.name || "Retry-After"
      end

      # The body field retry_after_seconds reads when the source is the body.
      def retry_after_field = ExamplePaths.retry_after_field(service.spec.operations.flat_map(&:errors))

      private

      attr_reader :service, :canon, :auth

      def cred(key) = canon.credential(key)

      # ---- authentication ------------------------------------------------------------------------

      def auth_methods
        lines, extra = auth_lines
        [MethodData.build(name: "auth_headers", comment: auth_comment, lines: lines), *extra]
      end

      def auth_comment
        case auth.type
        when "none" then ["The spec declares no securitySchemes: requests are sent without credentials."]
        when "unknown" then [unsupported_scheme]
        else ["#{auth.scheme_name}: #{auth.type} in #{auth.location} #{auth.name}. Evidence: #{auth_evidence}"]
        end
      end

      def auth_evidence = auth.evidence.join("; ")

      def unsupported_scheme
        Generator::Confidence.todo(0.0, "security scheme #{auth.scheme_name} (#{auth.type}) is not supported (W501)")
      end

      def auth_lines
        case auth.type
        when "api_key" then api_key_lines
        when "http_bearer" then [["{ #{Code.str(auth.name)} => \"Bearer \#{#{cred("token")}}\" }"], []]
        when "http_basic" then basic_lines
        when "oauth2_client_credentials", "oauth2" then oauth_lines
        else [["{}"], []]
        end
      end

      def api_key_lines
        key = cred(auth.credentials_key)
        case auth.location
        when "query" then [["{}"], [query_method(key)]]
        when "cookie" then [["{ 'Cookie' => \"#{auth.name}=\#{#{key}}\" }"], []]
        else [["{ #{Code.str(auth.name)} => #{key} }"], []]
        end
      end

      def query_method(key)
        service.require("uri")
        MethodData.build(name: "with_api_key", params: "url",
                         comment: ["#{auth.scheme_name}: the key travels as the query parameter #{auth.name}."],
                         lines: [format(QUERY_TEMPLATE, pair: "#{Code.str(auth.name)} => #{key}")])
      end

      def basic_lines
        [["token = [\"\#{#{cred("login")}}:\#{#{cred("password")}}\"].pack('m0')",
          "{ #{Code.str(auth.name)} => \"Basic \#{token}\" }"], []]
      end

      def oauth_lines
        service.need(:token_url, auth.token_url)
        [["{ #{Code.str(auth.name)} => \"Bearer \#{access_token}\" }"], [access_token_method]]
      end

      def access_token_method
        scope = auth.scopes.empty? ? nil : "scope: #{Code.str(auth.scopes.join(" "))}"
        form = ["grant_type: 'client_credentials'", "client_id: #{cred("client_id")}",
                "client_secret: #{cred("client_secret")}", scope].compact
        MethodData.build(name: "access_token", comment: access_token_comment,
                         lines: ["form = { #{form.join(", ")} }",
                                 "response = client.post(TOKEN_URL, form: form, headers: {})",
                                 "response.body.to_h['access_token']"])
      end

      def access_token_comment
        ["OAuth2 client credentials at TOKEN_URL#{" (scopes: #{auth.scopes.join(", ")})" unless auth.scopes.empty?}.",
         Generator::Confidence.todo(Generator::Confidence::SIGNATURE_DEFAULTED,
                                    "cache the token until it expires; the spec does not state the lifetime")]
      end

      # ---- idempotency ---------------------------------------------------------------------------

      def idempotency_method
        idempotency = service.flag(:idempotency)
        return nil unless idempotency

        MethodData.build(name: "idempotency_headers", params: "operation", comment: idempotency_comment(idempotency),
                         lines: idempotency_lines(idempotency))
      end

      def idempotency_comment(idempotency)
        format = idempotency.format ? " (format #{idempotency.format})" : ""
        ["#{idempotency.name}#{format}: #{canon.accessor("external_id")} is the stable key of the request; " \
         "the provider answers a repeat with the original result."]
      end

      def idempotency_lines(idempotency)
        if idempotency.location == "header"
          return ["{ #{Code.str(idempotency.name)} => #{canon.accessor("external_id")}.to_s }"]
        end

        [Generator::Confidence.todo(0.0, "the idempotency key is sent in the #{idempotency.location} " \
                                         "(#{idempotency.name}), which this helper does not cover"),
         "{}"]
      end

      # ---- responses -----------------------------------------------------------------------------

      def map_status_method
        return nil if service.spec.statuses.empty?

        MethodData.build(name: "map_status", params: "value",
                         comment: ["Provider status -> Space Payments status (STATUS_MAP); unknown values stay " \
                                   "#{canon.default_status} until the next notification."],
                         lines: ["STATUS_MAP.fetch(value.to_s, #{Code.str(canon.default_status)})"])
      end

      def provider_error_method
        branches = error_codes.map { |code| "when #{Code.str(code)} then #{canon.failure_for_error(code, details)}" }
        lines = [*detail_lines, "case ERROR_MAP.fetch(response.status) { #{fallback_expression} }", *branches,
                 "else #{canon.failure_for_error(default_canonical("4xx"), details)}", "end"]
        MethodData.build(name: "provider_error", params: "response", lines: lines,
                         comment: ["Error response -> failure through ERROR_MAP (HTTP status -> canonical code)."])
      end

      # The canonical code for a status ERROR_MAP does not list: 5xx and 4xx defaults of errors.yml.
      def fallback_expression
        "response.status >= 500 ? #{Code.str(default_canonical("5xx"))} : #{Code.str(default_canonical("4xx"))}"
      end

      def default_canonical(range) = Dictionaries.errors.dig("http", "default_#{range}", "canonical")

      # Canonical codes the case lists, in canon order; the 4xx default is the else branch.
      def error_codes
        present = service.spec.operations.flat_map(&:errors).map(&:canonical) + [default_canonical("5xx")]
        canon.error_codes.select { |code| present.include?(code) } - [default_canonical("4xx")]
      end

      def detail_lines
        parts = []
        parts << "provider_code: error_code(body)" if service.error_code_path
        parts << "retry_after: retry_after_seconds(response)" if retry_after_sources.any?
        return [] if parts.empty?

        lines = []
        lines << "body = response.body || {}" if service.error_code_path
        lines << "details = { #{parts.join(", ")} }.compact"
      end

      def details = detail_lines.empty? ? nil : "**details"

      def retry_after_method
        return nil if retry_after_sources.empty?

        MethodData.build(name: "retry_after_seconds", params: "response", lines: retry_after_lines,
                         comment: ["Retry-After of a rate-limited response in seconds " \
                                   "(#{retry_after_sources.join(" or ")}); nil when the provider sent none."])
      end

      def retry_after_lines
        lines = []
        values = []
        if retry_after_sources.include?("header")
          header = Code.str(retry_after_header)
          lines << "header = response.headers.to_h.find { |name, _| name.to_s.casecmp?(#{header}) }&.last"
          values << "header"
        end
        if retry_after_sources.include?("body")
          lines << "body_value = (response.body || {})[#{Code.str(retry_after_field)}]"
          values << "body_value"
        end
        lines << "(#{values.join(" || ")})&.to_i"
      end

      def error_code_method
        path = service.error_code_path
        return nil unless path

        MethodData.build(name: "error_code", params: "body",
                         comment: ["Provider error code of an error response (#{path} in the spec)."],
                         lines: ["#{Code.access("body", path)}&.to_s"])
      end

      def amount_methods
        service.amount_helpers.map do |helper|
          MethodData.build(name: helper.name, params: "amount", comment: helper.comment, lines: helper.lines)
        end
      end
    end
  end
end
