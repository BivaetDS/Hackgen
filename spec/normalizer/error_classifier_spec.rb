# frozen_string_literal: true

# docs/IR_CONTRACT.md 2.8: the HTTP status always yields a canonical code and an action; an example
# code refines it, an enum value is the weaker second source, and a transport failure (429, 5xx)
# never becomes a terminal reject because the provider code says so (http_guard).
RSpec.describe ProviderIntegrator::Normalizer::ErrorClassifier do
  subject(:classifier) { described_class.new }

  let(:nested_error) do
    { "error" => { "type" => "object",
                   "properties" => { "code" => { "type" => "string" }, "message" => { "type" => "string" } } } }
  end
  let(:retry_after_header) do
    ProviderIntegrator::Models::ResponseHeader.new(name: "Retry-After", type: "integer",
                                                   description: "Seconds to wait", canonical: "retry_after")
  end

  # The response as ResponseReader hands it over: the flattened schema, its mappings and the headers.
  # Nothing is stubbed; fields.yml maps "code" onto error.code on its own.
  def body_of(pointer:, schema:, example: nil, headers: [], root: {})
    document = ProviderIntegrator::Parser::Document.new(root:, log: ProviderIntegrator::EventLog.new,
                                                        spec_format: "3.0.3")
    fields = ProviderIntegrator::Parser::SchemaExtractor.new(document).call(schema, pointer)
    mappings = ProviderIntegrator::Normalizer::FieldMapper.new.call(fields, context: "response", error_context: true)
    described_class::Body.of(example:, fields:, mappings:, headers:)
  end

  # A response whose schema is a named component of the spec.
  def error_body(properties:, example: nil, headers: [], schema_name: "PayoutError")
    pointer = "#/components/schemas/#{schema_name}"
    body_of(pointer:, schema: { "$ref" => pointer }, example:, headers:,
            root: { "components" => { "schemas" => { schema_name => { "type" => "object",
                                                                      "properties" => properties } } } })
  end

  # The same response with its schema written inline in the operation, owned by no component.
  def inline_error_body(properties:)
    body_of(pointer: "#/paths/~1payouts/post/responses/400/content/application~1json/schema",
            schema: { "type" => "object", "properties" => properties })
  end

  describe "#call" do
    context "when the response carries an example code" do
      it "reads the code through the field mapped to error.code and cites both rules" do
        body = error_body(properties: nested_error,
                          example: { "error" => { "code" => "unauthorized", "message" => "Invalid API key" } })

        expect(classifier.call(http: 401, response: body)).to have_attributes(
          provider_code: "unauthorized", canonical: "invalid_credentials", action: "fatal_block_provider",
          retry_after: nil, confidence: 0.95, source: "example", unknown_code: false,
          evidence: ["example (401): code unauthorized",
                     "errors.yml: unauthorized -> invalid_credentials (fatal_block_provider)"]
        )
      end

      it "reads a flat error_code and keeps the provider spelling in the evidence" do
        body = error_body(properties: { "error_code" => { "type" => "string" },
                                        "retry_after" => { "type" => "integer" } },
                          example: { "error_code" => "TOO_MANY_REQUESTS", "retry_after" => 30 })

        expect(classifier.call(http: 429, response: body)).to have_attributes(
          provider_code: "TOO_MANY_REQUESTS", canonical: "rate_limit", action: "retry_with_backoff",
          retry_after: "body", source: "example",
          evidence: ["example (429): code TOO_MANY_REQUESTS",
                     "errors.yml: TOO_MANY_REQUESTS -> rate_limit (retry_with_backoff)"]
        )
      end

      it "appends the note of the errors.yml entry as the last evidence line" do
        body = error_body(properties: nested_error, example: { "error" => { "code" => "card_expired" } })

        expect(classifier.call(http: 400, response: body).evidence).to eq(
          ["example (400): code card_expired",
           "errors.yml: card_expired -> validation_error (terminal_reject)",
           "note: отказ по получателю/комплаенсу — исправить реквизиты, не повторять запрос"]
        )
      end

      it "reports an unknown code as an HTTP-only decision, so the caller raises W202" do
        body = error_body(properties: nested_error, example: { "error" => { "code" => "TRANSFER_NOT_CANCELABLE" } })

        expect(classifier.call(http: 409, response: body)).to have_attributes(
          provider_code: "TRANSFER_NOT_CANCELABLE", canonical: "conflict", action: "conflict",
          source: "example", unknown_code: true,
          evidence: ["example (409): code TRANSFER_NOT_CANCELABLE", "errors.yml: HTTP 409 -> conflict (conflict)"]
        )
      end
    end

    context "when a transport status meets a terminal provider code" do
      let(:body) { error_body(properties: nested_error, example: { "error" => { "code" => "invalid_signature" } }) }

      it "keeps the HTTP default and records the action it overrode" do
        expect(classifier.call(http: 429, response: body)).to have_attributes(
          provider_code: "invalid_signature", canonical: "rate_limit", action: "retry_with_backoff",
          confidence: 0.95, source: "example",
          evidence: ["example (429): code invalid_signature",
                     "errors.yml: HTTP 429 -> rate_limit (retry_with_backoff)",
                     "http 429 overrides terminal action fatal_block_provider"]
        )
      end

      it "lets the same code decide on a status that is not guarded" do
        expect(classifier.call(http: 401, response: body)).to have_attributes(
          canonical: "invalid_credentials", action: "fatal_block_provider",
          evidence: ["example (401): code invalid_signature",
                     "errors.yml: invalid_signature -> invalid_credentials (fatal_block_provider)"]
        )
      end
    end

    context "when there is no example but the error schema enumerates its codes" do
      it "picks the value that spells the canonical name of the HTTP default" do
        body = error_body(properties: { "code" => { "type" => "string",
                                                    "enum" => %w[validation_error internal_error rate_limited] } })

        expect(classifier.call(http: 500, response: body)).to have_attributes(
          provider_code: "internal_error", canonical: "internal_error", action: "retry_alert_ops",
          confidence: 0.8, source: "enum",
          evidence: ["enum PayoutError.code: internal_error",
                     "errors.yml: HTTP 500 -> internal_error (retry_alert_ops)"]
        )
      end

      it "otherwise picks the first value whose dictionary entry agrees with the HTTP default" do
        body = error_body(properties: { "code" => { "type" => "string", "enum" => %w[bad_input rate_limited] } },
                          schema_name: "TransferError")

        expect(classifier.call(http: 429, response: body)).to have_attributes(
          provider_code: "rate_limited", canonical: "rate_limit", action: "retry_with_backoff", source: "enum",
          evidence: ["enum TransferError.code: rate_limited",
                     "errors.yml: HTTP 429 -> rate_limit (retry_with_backoff)"]
        )
      end

      it "calls an inline schema \"inline\", because no component owns its enum" do
        body = inline_error_body(properties: { "code" => { "type" => "string",
                                                           "enum" => %w[bad_input validation_error] } })

        expect(classifier.call(http: 400, response: body)).to have_attributes(
          provider_code: "validation_error", canonical: "validation_error", action: "terminal_reject",
          confidence: 0.8, source: "enum",
          evidence: ["enum inline.code: validation_error",
                     "errors.yml: HTTP 400 -> validation_error (terminal_reject)"]
        )
      end

      it "falls back to the HTTP default when no enum value agrees with it" do
        body = error_body(properties: { "code" => { "type" => "string", "enum" => %w[bad_input weird_code] } })

        expect(classifier.call(http: 402, response: body)).to have_attributes(
          provider_code: nil, canonical: "insufficient_balance", action: "retry_later", source: "http_default"
        )
      end
    end

    context "when the response says nothing but its status" do
      it "maps by HTTP alone at the http_default confidence" do
        expect(classifier.call(http: 404, response: described_class::Body.of)).to have_attributes(
          provider_code: nil, canonical: "not_found", action: "unknown_state", retry_after: nil,
          confidence: 0.6, source: "http_default",
          evidence: ["errors.yml: HTTP 404 -> not_found (unknown_state)"]
        )
      end

      it "reads Retry-After from a declared header" do
        body = error_body(properties: nested_error, headers: [retry_after_header])

        expect(classifier.call(http: 429, response: body).retry_after).to eq("header")
      end
    end

    context "when overrides.yml pins the action of a code" do
      it "keeps the canonical code, takes the action and marks the source" do
        body = error_body(properties: nested_error, example: { "error" => { "code" => "insufficient_funds" } })
        overrides = { "insufficient_funds" => "terminal_reject" }

        expect(classifier.call(http: 402, response: body, override_actions: overrides)).to have_attributes(
          provider_code: "insufficient_funds", canonical: "insufficient_balance", action: "terminal_reject",
          confidence: 1.0, source: "override",
          evidence: ["example (402): code insufficient_funds", "overrides.yml: error action terminal_reject"]
        )
      end
    end
  end

  describe "#http_default" do
    it "answers from the table, then by status class" do
      aggregate_failures do
        expect(classifier.http_default(503)).to eq({ "canonical" => "internal_error", "action" => "retry_alert_ops" })
        expect(classifier.http_default(418)).to eq({ "canonical" => "validation_error",
                                                     "action" => "terminal_reject" })
        expect(classifier.http_default(599)).to eq({ "canonical" => "internal_error", "action" => "retry_alert_ops" })
      end
    end
  end

  describe "a spec whose error codes are provider inventions" do
    let(:parsed) { ProviderIntegrator::Parser.call(path: fixture_path("specs", "cardpay.yaml")) }

    it "maps them by HTTP and the caller raises W202 for each" do
      mapping = parsed.spec.operations.flat_map(&:errors).find { |error| error.provider_code == "CP_KEY_REVOKED" }

      aggregate_failures do
        expect(mapping).to have_attributes(http: 401, canonical: "invalid_credentials",
                                           action: "fatal_block_provider", source: "example")
        expect(parsed.spec.events.select { |event| event.code == "W202" }.map(&:message))
          .to eq(["Provider error code CP_KEY_REVOKED (HTTP 401) has no canonical analog; " \
                  "defaulting to invalid_credentials"])
      end
    end
  end
end
