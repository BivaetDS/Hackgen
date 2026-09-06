# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # What the generated spec expects of the HTTP requests the service sends: the URL expression
    # (BASE_URL through described_class), the verb, the authentication carried as headers or a
    # query parameter, the idempotency header, and the request body fields of the exercised payout
    # method with the values SpecSubject derives from the fixtures.
    class SpecRequest
      ACCESS_TOKEN = "test-access-token"
      BASIC_TEMPLATE = "%{login}:%{password}"

      def initialize(data)
        @data = data
        @spec = data.spec
        @canon = data.canon
        @service = data.service
        @subject = data.subject
        @auth = spec.authentication
      end

      def operation = data.context.create_operation
      def verb_literal(target) = ":#{target.method.downcase}"

      # "\"\#{described_class::BASE_URL}/payouts\"" - the service URL of +target+ for a `let(:url)`.
      def url_expression(target)
        Url.new(target, canon:).expression.sub("\#{BASE_URL}", "\#{described_class::BASE_URL}")
      end

      # True when the create body is form-urlencoded (the spec decodes it with URI.decode_www_form).
      def form?
        Requests.body_keyword(operation, canon) == canon.client_argument("application/x-www-form-urlencoded")
      end

      # True when the api key travels as a query parameter (every stub and assertion adds it).
      def query? = service.need?(:auth_query)

      # "{ 'api_key' => credentials[:api_key] }" for the `auth_query` let.
      def query_literal
        "{ #{Code.str(auth.name)} => #{canon.credential(auth.credentials_key)} }"
      end

      # True when the service fetches an OAuth2 token first (the spec stubs TOKEN_URL in a before).
      def token? = %w[oauth2_client_credentials oauth2].include?(auth.type)

      # { header name => expected value } for a call of +target+: authentication plus, for the
      # create operation, the idempotency key.
      def headers(target)
        result = auth_headers.dup
        idempotency = target.idempotency
        result[idempotency.name] = subject.id.to_s if idempotency&.location == "header" && target.method != "GET"
        result
      end

      # "{ 'X-API-Key' => 'test-api_key' }" or nil when nothing is expected.
      def headers_literal(target)
        expected = headers(target)
        expected.empty? ? nil : Code.literal(expected)
      end

      # [[container path or nil, [[leaf, value], ...]], ...] - the body fields the fixture-built
      # operation makes the service send, grouped by container in field order.
      def body_groups
        groups = {}
        body_fields.each do |field, value|
          *parents, leaf = field.provider_path.split(".")
          (groups[parents.empty? ? nil : parents.join(".")] ||= []) << [leaf, form? ? value.to_s : value]
        end
        groups.to_a
      end

      private

      attr_reader :data, :spec, :canon, :service, :subject, :auth

      def auth_headers
        case auth.type
        when "api_key" then api_key_headers
        when "http_bearer" then { auth.name => "Bearer #{subject.credentials["token"]}" }
        when "http_basic" then { auth.name => "Basic #{basic_token}" }
        when "oauth2_client_credentials", "oauth2" then { auth.name => "Bearer #{ACCESS_TOKEN}" }
        else {}
        end
      end

      def api_key_headers
        key = subject.credentials[auth.credentials_key]
        case auth.location
        when "query" then {}
        when "cookie" then { "Cookie" => "#{auth.name}=#{key}" }
        else { auth.name => key }
        end
      end

      def basic_token
        pair = format(BASIC_TEMPLATE, login: subject.credentials["login"], password: subject.credentials["password"])
        [pair].pack("m0")
      end

      # [[field, sent value], ...] for the leaves of the exercised payout method the platform fills.
      def body_fields
        scope = Scope.build(branch: subject.request_method)
        source = FieldSource.new(operation, canon:, context: data.context, scope:)
        leaves.filter_map do |field|
          value = subject.sent_value(source.for(field))
          [field, value] unless value.nil?
        end
      end

      def leaves
        return [] unless operation

        operation.request_fields.select do |field|
          PayloadBuilder.in_branch?(field, subject.request_method, operation) && !PayloadBuilder.container?(field) &&
            !field.provider_path.include?("[]")
        end
      end
    end
  end
end
