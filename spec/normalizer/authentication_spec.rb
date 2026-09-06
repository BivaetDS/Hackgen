# frozen_string_literal: true

# docs/IR_CONTRACT.md 2.2: one Authentication per spec - the scheme most operations use, with the
# credentials key the canon reserves for its type, the others kept as alternatives, and an unusable
# scheme reported (W501) instead of guessed at.
RSpec.describe ProviderIntegrator::Normalizer::Authentication do
  let(:log) { ProviderIntegrator::EventLog.new }
  let(:api_key_scheme) { { "type" => "apiKey", "in" => "header", "name" => "X-API-Key" } }
  let(:bearer_scheme) { { "type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT" } }

  def authentication(schemes, usage:, operation_count:)
    root = schemes.empty? ? {} : { "components" => { "securitySchemes" => schemes } }
    document = ProviderIntegrator::Parser::Document.new(root:, log:, spec_format: "3.0.3")
    described_class.new(document:, log:).call(usage:, operation_count:)
  end

  describe "#call" do
    context "with a single apiKey scheme" do
      it "records where the key goes, the canon credentials key and how many operations use it" do
        auth = authentication({ "ApiKeyAuth" => api_key_scheme }, usage: { "ApiKeyAuth" => 4 }, operation_count: 5)

        expect(auth).to have_attributes(
          type: "api_key", scheme_name: "ApiKeyAuth", location: "header", name: "X-API-Key", bearer_format: nil,
          token_url: nil, scopes: [], credentials_key: "api_key", confidence: 1.0, source: "security_schemes",
          alternatives: [],
          evidence: ["securitySchemes.ApiKeyAuth: apiKey in header X-API-Key",
                     "security: ApiKeyAuth used by 4 of 5 operations"]
        )
      end
    end

    context "with an http scheme" do
      it "puts a bearer token in the Authorization header and keeps its format" do
        auth = authentication({ "BearerAuth" => bearer_scheme }, usage: { "BearerAuth" => 3 }, operation_count: 3)

        expect(auth).to have_attributes(
          type: "http_bearer", location: "header", name: "Authorization", bearer_format: "JWT",
          credentials_key: "token", confidence: 1.0,
          evidence: ["securitySchemes.BearerAuth: http bearer in header Authorization",
                     "security: BearerAuth used by 3 of 3 operations"]
        )
      end

      it "asks for a login when the scheme is basic" do
        auth = authentication({ "BasicAuth" => { "type" => "http", "scheme" => "basic" } },
                              usage: { "BasicAuth" => 1 }, operation_count: 1)

        expect(auth).to have_attributes(
          type: "http_basic", location: "header", name: "Authorization", bearer_format: nil,
          credentials_key: "login",
          evidence: ["securitySchemes.BasicAuth: http basic in header Authorization",
                     "security: BasicAuth used by 1 of 1 operations"]
        )
      end
    end

    context "with an oauth2 scheme" do
      let(:scopes) { { "payouts:write" => "Create a payout", "payouts:read" => "Read a payout" } }
      let(:flow) { { "tokenUrl" => "https://auth.example/oauth2/token", "scopes" => scopes } }
      let(:client_credentials) { { "type" => "oauth2", "flows" => { "clientCredentials" => flow } } }

      it "keeps the token url and the scopes, and names the flow in the evidence" do
        auth = authentication({ "MerchantOAuth2" => client_credentials },
                              usage: { "MerchantOAuth2" => 2 }, operation_count: 2)

        expect(auth).to have_attributes(
          type: "oauth2_client_credentials", location: "header", name: "Authorization",
          token_url: "https://auth.example/oauth2/token", scopes: ["payouts:write", "payouts:read"],
          credentials_key: "client_id",
          evidence: ["securitySchemes.MerchantOAuth2: oauth2 in header Authorization " \
                     "(clientCredentials https://auth.example/oauth2/token)",
                     "security: MerchantOAuth2 used by 2 of 2 operations"]
        )
      end

      it "stays plain oauth2 when no clientCredentials flow is declared" do
        scheme = { "type" => "oauth2",
                   "flows" => { "authorizationCode" => { "authorizationUrl" => "https://auth.example/authorize",
                                                         "tokenUrl" => "https://auth.example/token",
                                                         "scopes" => { "payouts" => "All" } } } }
        auth = authentication({ "UserOAuth2" => scheme }, usage: { "UserOAuth2" => 1 }, operation_count: 1)

        expect(auth).to have_attributes(type: "oauth2", token_url: nil, scopes: ["payouts"],
                                        credentials_key: "client_id")
      end
    end

    context "with a scheme type the generator cannot implement" do
      it "keeps it as unknown, leaves the credentials to the integrator and raises W501" do
        scheme = { "type" => "openIdConnect", "openIdConnectUrl" => "https://example/.well-known/openid" }
        auth = authentication({ "OidcAuth" => scheme }, usage: { "OidcAuth" => 1 }, operation_count: 1)

        aggregate_failures do
          expect(auth).to have_attributes(type: "unknown", scheme_name: "OidcAuth", location: nil, name: nil,
                                          credentials_key: nil,
                                          evidence: ["securitySchemes.OidcAuth: openIdConnect",
                                                     "security: OidcAuth used by 1 of 1 operations"])
          expect(log.with_code("W501").map(&:details)).to eq([{ "scheme_name" => "OidcAuth",
                                                                "type" => "openIdConnect" }])
        end
      end
    end

    context "with an unusable scheme the spec only offers as a second option" do
      it "keeps it as an unknown alternative without warning about code it will not generate" do
        schemes = { "ApiKeyAuth" => api_key_scheme,
                    "OidcAuth" => { "type" => "openIdConnect", "openIdConnectUrl" => "https://example/oidc" } }
        auth = authentication(schemes, usage: { "ApiKeyAuth" => 2, "OidcAuth" => 1 }, operation_count: 3)

        aggregate_failures do
          expect(auth).to have_attributes(scheme_name: "ApiKeyAuth", type: "api_key", confidence: 1.0)
          expect(auth.alternatives.map(&:to_h)).to eq(
            [{ "scheme_name" => "OidcAuth", "type" => "unknown", "location" => nil, "name" => nil }]
          )
          expect(log).to be_empty
        end
      end
    end

    context "without securitySchemes" do
      it "says so plainly instead of inventing a scheme" do
        auth = authentication({}, usage: {}, operation_count: 3)

        aggregate_failures do
          expect(auth).to have_attributes(type: "none", scheme_name: nil, location: nil, name: nil, scopes: [],
                                          credentials_key: nil, confidence: 1.0, source: "security_schemes",
                                          alternatives: [], evidence: ["no securitySchemes declared"])
          expect(log).to be_empty
        end
      end
    end

    context "with two schemes" do
      let(:schemes) { { "ApiKeyAuth" => api_key_scheme, "BearerAuth" => bearer_scheme } }

      it "picks the one most operations use and keeps the other as an alternative" do
        auth = authentication(schemes, usage: { "ApiKeyAuth" => 3, "BearerAuth" => 1 }, operation_count: 4)

        aggregate_failures do
          expect(auth).to have_attributes(scheme_name: "ApiKeyAuth", type: "api_key", confidence: 1.0)
          expect(auth.alternatives.map(&:to_h)).to eq(
            [{ "scheme_name" => "BearerAuth", "type" => "http_bearer", "location" => "header",
               "name" => "Authorization" }]
          )
          expect(auth.evidence.last).to eq("security: ApiKeyAuth used by 3 of 4 operations")
        end
      end

      it "lowers the confidence to 0.7 when the two are used equally often" do
        auth = authentication(schemes, usage: { "ApiKeyAuth" => 1, "BearerAuth" => 1 }, operation_count: 2)

        aggregate_failures do
          expect(auth).to have_attributes(scheme_name: "ApiKeyAuth", confidence: 0.7)
          expect(auth.alternatives.map(&:scheme_name)).to eq(["BearerAuth"])
        end
      end
    end
  end

  describe "#requirements_for" do
    let(:analyzer) do
      root = { "security" => [{ "ApiKeyAuth" => [] }],
               "components" => { "securitySchemes" => { "ApiKeyAuth" => api_key_scheme } } }
      document = ProviderIntegrator::Parser::Document.new(root:, log:, spec_format: "3.0.3")
      described_class.new(document:, log:)
    end

    def operation(node) = ProviderIntegrator::Parser::Document::OperationRef.new(node:)

    it "falls back to the document security and honours an explicit opt-out" do
      aggregate_failures do
        expect(analyzer.requirements_for(operation({}))).to eq(["ApiKeyAuth"])
        expect(analyzer.requirements_for(operation("security" => [{ "BearerAuth" => %w[payouts] }])))
          .to eq(["BearerAuth"])
        expect(analyzer.requirements_for(operation("security" => []))).to eq([])
        expect(analyzer.public?(operation("security" => []))).to be(true)
        expect(analyzer.public?(operation({}))).to be(false)
      end
    end
  end
end
