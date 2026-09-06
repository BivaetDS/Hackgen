# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::Swagger2Converter do
  let(:log) { ProviderIntegrator::EventLog.new }

  def convert(document)
    source = { "swagger" => "2.0", "info" => { "title" => "Kassira", "version" => "2.4" }, "paths" => {} }
             .merge(document)
    loaded = ProviderIntegrator::Parser::Loader::Loaded.new(document: source, openapi: nil, swagger: "2.0")
    described_class.call(loaded:, log:).document
  end

  # One path item with a single POST operation, the shape almost every 2.0 provider uses.
  def post(operation)
    { "paths" => { "/payment/create" => { "post" => operation } } }
  end

  def created(document) = document.dig("paths", "/payment/create", "post")

  describe ".call" do
    it "keeps the document usable as OpenAPI 3.0 and announces the conversion with W103" do
      loaded = ProviderIntegrator::Parser::Loader::Loaded.new(
        document: { "swagger" => "2.0", "info" => { "title" => "Kassira", "version" => "2.4" }, "paths" => {} },
        openapi: nil, swagger: "2.0"
      )
      result = described_class.call(loaded:, log:)

      aggregate_failures do
        expect(result.openapi).to eq("3.0.3")
        expect(result.swagger).to eq("2.0")
        expect(result.document["openapi"]).to eq("3.0.3")
        expect(result.document).not_to have_key("swagger")
        expect(log.with_code("W103").map(&:message))
          .to eq(["Swagger 2.0 document converted to OpenAPI 3.0 before analysis"])
      end
    end

    it "builds one server from host, basePath and schemes" do
      aggregate_failures do
        expect(convert("host" => "api.kassira.example", "basePath" => "/merchant/v2", "schemes" => ["https"])
                 .values_at("servers", "host", "basePath", "schemes"))
          .to eq([[{ "url" => "https://api.kassira.example/merchant/v2" }], nil, nil, nil])
        expect(convert("host" => "api.kassira.example")["servers"]).to eq([{ "url" => "https://api.kassira.example" }])
        expect(convert("schemes" => %w[http https], "host" => "api.x.example")["servers"])
          .to eq([{ "url" => "http://api.x.example" }])
        expect(convert("servers" => [{ "url" => "https://declared.example" }])["servers"])
          .to eq([{ "url" => "https://declared.example" }])
      end
    end

    it "moves definitions into components.schemas and rewrites every reference to them" do
      document = convert(
        "definitions" => { "PaymentInfo" => { "type" => "object", "properties" => {
          "fault" => { "$ref" => "#/definitions/Fault" }
        } }, "Fault" => { "type" => "object" } },
        **post("responses" => { "200" => { "description" => "ok",
                                           "schema" => { "$ref" => "#/definitions/PaymentInfo" } } })
      )

      aggregate_failures do
        expect(document).not_to have_key("definitions")
        expect(document.dig("components", "schemas", "PaymentInfo", "properties", "fault"))
          .to eq("$ref" => "#/components/schemas/Fault")
        expect(created(document).dig("responses", "200", "content", "application/json", "schema"))
          .to eq("$ref" => "#/components/schemas/PaymentInfo")
      end
    end

    it "turns a body parameter into a requestBody with the media type the operation consumes" do
      operation = { "consumes" => ["application/json"],
                    "parameters" => [{ "name" => "body", "in" => "body", "required" => true,
                                       "description" => "Notification body",
                                       "schema" => { "$ref" => "#/definitions/CallbackPayload" } }],
                    "responses" => {} }
      document = convert("consumes" => ["application/x-www-form-urlencoded"], **post(operation))

      aggregate_failures do
        expect(created(document)["requestBody"]).to eq(
          "required" => true, "description" => "Notification body",
          "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/CallbackPayload" } } }
        )
        expect(created(document)).not_to have_key("parameters")
        expect(created(document)).not_to have_key("consumes")
      end
    end

    it "falls back to JSON for a body neither the operation nor the document says it consumes" do
      operation = { "parameters" => [{ "name" => "body", "in" => "body", "schema" => { "type" => "object" } }],
                    "responses" => {} }

      expect(created(convert(post(operation)))["requestBody"]).to eq(
        "required" => false, "content" => { "application/json" => { "schema" => { "type" => "object" } } }
      )
    end

    it "rebuilds formData parameters as one urlencoded object schema with the required names" do
      operation = { "parameters" => [
        { "name" => "order_id", "in" => "formData", "required" => true, "type" => "string", "maxLength" => 40 },
        { "name" => "sum", "in" => "formData", "required" => true, "type" => "integer", "format" => "int64",
          "description" => "Сумма списания в копейках" },
        { "name" => "purpose", "in" => "formData", "required" => false, "type" => "string" }
      ], "responses" => {} }

      expect(created(convert(post(operation)))["requestBody"]).to eq(
        "required" => true,
        "content" => { "application/x-www-form-urlencoded" => { "schema" => {
          "type" => "object",
          "properties" => { "order_id" => { "type" => "string", "maxLength" => 40 },
                            "sum" => { "type" => "integer", "format" => "int64",
                                       "description" => "Сумма списания в копейках" },
                            "purpose" => { "type" => "string" } },
          "required" => %w[order_id sum]
        } } }
      )
    end

    it "moves a response schema under content, using the produces of the operation" do
      operation = { "produces" => ["application/xml"], "responses" => { "200" => {
        "description" => "ok", "schema" => { "type" => "object" }, "examples" => { "application/xml" => "<ok/>" }
      } } }
      document = convert("produces" => ["application/json"], **post(operation))

      expect(created(document)["responses"]).to eq(
        "200" => { "description" => "ok",
                   "content" => { "application/xml" => { "schema" => { "type" => "object" },
                                                         "example" => "<ok/>" } } }
      )
    end

    it "gives 2.0 parameters and response headers the schema object 3.0 expects" do
      operation = { "parameters" => [{ "name" => "X-Request-Id", "in" => "header", "required" => false,
                                       "type" => "string", "maxLength" => 64, "description" => "Request id" }],
                    "responses" => { "429" => { "description" => "too many", "headers" => {
                      "Retry-After" => { "type" => "integer", "description" => "Seconds" }
                    } } } }
      document = created(convert(post(operation)))

      aggregate_failures do
        expect(document["parameters"]).to eq([{ "name" => "X-Request-Id", "in" => "header", "required" => false,
                                                "description" => "Request id",
                                                "schema" => { "type" => "string", "maxLength" => 64 } }])
        expect(document.dig("responses", "429", "headers", "Retry-After"))
          .to eq("description" => "Seconds", "schema" => { "type" => "integer" })
      end
    end

    it "translates securityDefinitions into 3.0 security schemes" do
      document = convert("securityDefinitions" => {
                           "Basic" => { "type" => "basic", "description" => "Login and password" },
                           "Machine" => { "type" => "oauth2", "flow" => "application",
                                          "tokenUrl" => "https://api.x.example/token",
                                          "scopes" => { "payouts" => "Create payouts" } },
                           "Token" => { "type" => "apiKey", "name" => "X-Merchant-Token", "in" => "header" }
                         })

      expect(document.dig("components", "securitySchemes")).to eq(
        "Basic" => { "type" => "http", "scheme" => "basic", "description" => "Login and password" },
        "Machine" => { "type" => "oauth2", "flows" => { "clientCredentials" => {
          "tokenUrl" => "https://api.x.example/token", "scopes" => { "payouts" => "Create payouts" }
        } } },
        "Token" => { "type" => "apiKey", "name" => "X-Merchant-Token", "in" => "header" }
      )
    end
  end

  describe ".call on the Kassira 2.0 fixture" do
    subject(:document) { described_class.call(loaded:, log:).document }

    let(:loaded) { ProviderIntegrator::Parser::Loader.call(path: fixture_path("specs", "legacy_swagger2.yaml"), log:) }

    it "produces a document the validator accepts" do
      converted = described_class.call(loaded:, log:)

      aggregate_failures do
        expect(ProviderIntegrator::Parser::Validator.call(loaded: converted, log:)).to be(true)
        expect(log.to_a.map(&:code)).to eq(["W103"])
      end
    end

    it "converts the create operation, its shared parameter and its reusable responses" do
      operation = document.dig("paths", "/payment/create", "post")

      aggregate_failures do
        expect(document["servers"]).to eq([{ "url" => "https://api.kassira.example/merchant/v2" }])
        expect(operation.dig("requestBody", "content", "application/x-www-form-urlencoded", "schema", "required"))
          .to eq(%w[merchant_id contract_num order_id sum cur payment_type])
        expect(operation["parameters"]).to eq([{ "$ref" => "#/components/parameters/RequestId" }])
        expect(document.dig("components", "parameters", "RequestId", "schema"))
          .to eq("type" => "string", "maxLength" => 64)
        expect(operation.dig("responses", "401")).to eq("$ref" => "#/components/responses/Unauthorized")
        expect(document.dig("components", "responses", "TooManyRequests", "headers", "Retry-After"))
          .to eq("description" => "Через сколько секунд допустим повторный запрос.",
                 "schema" => { "type" => "integer" })
      end
    end

    it "keeps the JSON callback body JSON even though the API consumes forms" do
      callback = document.dig("paths", "/callback/payment", "post")

      aggregate_failures do
        expect(callback["requestBody"]["content"].keys).to eq(["application/json"])
        expect(callback.dig("requestBody", "content", "application/json", "schema"))
          .to eq("$ref" => "#/components/schemas/CallbackPayload")
        expect(callback.dig("responses", "200", "content", "application/json", "schema"))
          .to eq("$ref" => "#/components/schemas/CallbackAck")
      end
    end
  end
end
