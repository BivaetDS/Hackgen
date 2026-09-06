# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Normalizer::WebhookAnalyzer do
  subject(:analyzer) { described_class.new(context:) }

  let(:log) { ProviderIntegrator::EventLog.new }
  let(:overrides) { ProviderIntegrator::Normalizer::Overrides.load(path: nil, log:) }
  let(:document) { ProviderIntegrator::Parser::Document.new(root: {}, log:, spec_format: "3.0.3") }
  let(:context) { ProviderIntegrator::Normalizer::Context.new(document:, log:, overrides:) }

  # ---- inputs the analyzer reads: a built operation and the raw reference it came from ----------

  def models = ProviderIntegrator::Models

  def field(path, **attrs)
    defaults = { provider_path: path, canonical: nil, type: "string", format: nil, required: false, nullable: false,
                 enum: nil, constant: nil, pattern: nil, minimum: nil, maximum: nil, min_length: nil,
                 max_length: nil, description: nil, example: nil, default: nil, conversion: nil,
                 conditional_required: nil, branch: nil, confidence: 1.0, evidence: [], source: "dictionary" }
    models::FieldMapping.new(**defaults, **attrs)
  end

  def classification(evidence, confidence: 0.92)
    scores = { "create" => 0, "status" => 0, "cancel" => 0, "balance" => 0, "webhook" => 11, "refund" => 0,
               "list" => 0 }
    models::Classification.new(confidence:, source: "scoring", scores:, evidence:)
  end

  def operation(**attrs)
    defaults = { kind: "webhook", in_contract: true, canonical_method: "process_callback",
                 operation_id: "payoutWebhook", method: "POST", path: "/webhooks/payout", summary: "Webhook",
                 description: nil, tags: ["Webhooks"], security: [], public: true, idempotency: nil,
                 classification: classification([]), parameters: [], request_body: nil, request_fields: [],
                 response_fields: [], responses: [], success_codes: [], idempotent_duplicate_codes: [], errors: [],
                 request_methods: nil, confidence: 0.92 }
    models::Operation.new(**defaults, **attrs)
  end

  def operation_ref(path: "/webhooks/payout")
    pointer = ProviderIntegrator::Parser::Pointer.build("paths", path, "post")
    ProviderIntegrator::Parser::Document::OperationRef.new(path:, http_method: "post", node: {}, pointer:,
                                                           path_item: {})
  end

  def analyse(operation, **attrs) = analyzer.call(operation:, ref: operation_ref(path: operation.path), **attrs)

  describe "#call on a NovaPay-like notification endpoint" do
    subject(:webhook) { analyse(novapay_operation) }

    let(:novapay_operation) do
      operation(classification: classification(novapay_evidence), parameters: [signature_parameter],
                description: "Подпись передаётся в заголовке X-NovaPay-Signature (HMAC-SHA256).",
                request_fields: payload_fields, request_body: body, responses: [ok_response])
    end
    let(:novapay_evidence) do
      ["operationId token 'webhook' -> webhook (+5)", "path token 'webhooks' -> webhook (+3)",
       "tag 'Webhooks' -> webhook (+2)", "text 'webhook' -> webhook (+1)"]
    end
    let(:signature_parameter) do
      models::Parameter.new(name: "X-NovaPay-Signature", in: "header", required: true, type: "string", format: nil,
                            description: "HMAC-SHA256 подпись тела запроса", example: nil, enum: nil,
                            canonical: "signature")
    end
    let(:payload_fields) do
      [field("event", canonical: "event", required: true,
                      enum: %w[payout.completed payout.failed payout.processing payout.cancelled]),
       field("payout_id", canonical: "provider_operation_id", required: true),
       field("external_id", canonical: "external_id"),
       field("status", canonical: "status", required: true, enum: %w[pending completed failed]),
       field("error", canonical: "error", type: "object"),
       field("error.code", canonical: "error.code"),
       field("error.message", canonical: "error.message")]
    end
    let(:body) do
      models::RequestBody.new(content_type: "application/json", required: true, schema_name: "WebhookPayload",
                              example: nil, examples: { "completed" => { "event" => "payout.completed" } })
    end
    let(:ok_response) do
      models::Response.new(http: 200, description: "Webhook принят", schema_name: nil, kind: "success",
                           content_type: "application/json", example: { "received" => true }, headers: [])
    end

    it "records where the endpoint is and that the path found it" do
      aggregate_failures do
        expect(webhook.path).to eq("/webhooks/payout")
        expect(webhook.method).to eq("POST")
        expect(webhook.operation_id).to eq("payoutWebhook")
        expect(webhook.source).to eq("path_heuristic")
        expect(webhook.confidence).to eq(0.92)
        expect(webhook.evidence).to eq(novapay_evidence)
        expect(webhook.payload_fields).to eq(payload_fields)
      end
    end

    it "names every payload role" do
      aggregate_failures do
        expect(webhook.event_field).to eq("event")
        expect(webhook.status_field).to eq("status")
        expect(webhook.id_field).to eq("payout_id")
        expect(webhook.external_id_field).to eq("external_id")
        expect(webhook.error_code_path).to eq("error.code")
        expect(webhook.error_message_path).to eq("error.message")
      end
    end

    it "maps the declared events, keeps the named examples and reads the answer" do
      aggregate_failures do
        expect(webhook.events.map(&:value)).to eq(%w[payout.completed payout.failed payout.processing
                                                     payout.cancelled])
        expect(webhook.events.map(&:canonical_status)).to eq(%w[approved rejected in_progress rejected])
        expect(webhook.events.map(&:source).uniq).to eq(["dictionary"])
        expect(webhook.events.map(&:confidence).uniq).to eq([0.95])
        expect(webhook.examples).to eq("completed" => { "event" => "payout.completed" })
        expect(webhook.response.to_h).to eq("http" => 200, "example" => { "received" => true })
      end
    end

    it "reads the signature from the header parameter and reports it (I301) with W301 for the open encoding" do
      signature = webhook.signature

      aggregate_failures do
        expect(signature.to_h).to include("name" => "X-NovaPay-Signature", "location" => "header",
                                          "algorithm" => "hmac-sha256", "encoding" => "unknown",
                                          "message" => "raw_body", "source" => "parameter")
        expect(log.with_code("I301").map(&:location)).to eq(["#/paths/~1webhooks~1payout/post/parameters/0"])
        expect(log.with_code("W301").first.details)
          .to include("name" => "X-NovaPay-Signature", "default_encoding" => "hex", "default_message" => "raw_body")
        expect(log.include?("W302")).to be(false)
      end
    end
  end

  describe "how the endpoint was found" do
    it "prefers the path over the tag and the tag over the operationId" do
      aggregate_failures do
        expect(analyse(operation(classification: classification(["operationId token 'callback' -> webhook (+5)",
                                                                 "path token 'hooks' -> webhook (+3)",
                                                                 "tag 'Callbacks' -> webhook (+2)"]))).source)
          .to eq("path_heuristic")
        expect(analyse(operation(classification: classification(["operationId token 'callback' -> webhook (+5)",
                                                                 "tag 'Callbacks' -> webhook (+2)"]))).source)
          .to eq("tag_heuristic")
        expect(analyse(operation(classification: classification(["operationId token 'notify' -> webhook (+5)",
                                                                 "text 'notification' -> webhook (+1)"]))).source)
          .to eq("operation_id_heuristic")
      end
    end

    it "takes the source and the confidence from a declaration and raises no W302" do
      webhook = analyse(operation(classification: classification(["path token 'callbacks' -> webhook (+3)"])),
                        source: "callbacks", confidence: 1.0)

      aggregate_failures do
        expect([webhook.source, webhook.confidence]).to eq(["callbacks", 1.0])
        expect(log.include?("W302")).to be(false)
      end
    end

    it "warns (W302) when a heuristic find rests on a single signal" do
      analyse(operation(path: "/hooks", classification: classification(["path token 'hooks' -> webhook (+3)"])))

      event = log.with_code("W302").first
      aggregate_failures do
        expect(event.message).to eq("Webhook endpoint POST /hooks identified by path_heuristic heuristic, " \
                                    "not via OpenAPI callbacks")
        expect(event.location).to eq("#/paths/~1hooks/post")
        expect(event.details).to eq("heuristic" => "path_heuristic", "method" => "POST", "path" => "/hooks")
      end
    end

    it "falls back to the path heuristic when the classification left no evidence at all" do
      webhook = analyse(operation)

      expect([webhook.source, log.include?("W302")]).to eq(["path_heuristic", true])
    end
  end

  describe "payload roles" do
    def roles_for(*fields)
      analyse(operation(request_fields: fields))
    end

    it "follows the dictionary order first and prefers the top level only on a tie" do
      aggregate_failures do
        expect(roles_for(field("type"), field("data.event")).event_field).to eq("data.event")
        expect(roles_for(field("data.event"), field("event")).event_field).to eq("event")
        expect(roles_for(field("data.status"), field("status")).status_field).to eq("status")
        expect(roles_for(field("payload.notification_type")).event_field).to eq("payload.notification_type")
      end
    end

    it "honours the status exclude list and leaves the role empty when nothing matches" do
      aggregate_failures do
        expect(roles_for(field("old_status"), field("state")).status_field).to eq("state")
        expect(roles_for(field("old_status"), field("previous_status")).status_field).to be_nil
        expect(roles_for(field("amount")).event_field).to be_nil
        expect(roles_for(field("amount")).events).to eq([])
      end
    end

    it "takes id, external id and error paths from the canonical names, top level first" do
      webhook = roles_for(field("data.payout_id", canonical: "provider_operation_id"),
                          field("id", canonical: "provider_operation_id"),
                          field("merchant_order_id", canonical: "external_id"),
                          field("failure.code", canonical: "error.code"),
                          field("failure.message", canonical: "error.message"))

      aggregate_failures do
        expect(webhook.id_field).to eq("id")
        expect(webhook.external_id_field).to eq("merchant_order_id")
        expect(webhook.error_code_path).to eq("failure.code")
        expect(webhook.error_message_path).to eq("failure.message")
      end
    end

    it "leaves every role empty for a payload nothing matches" do
      webhook = roles_for(field("signature"), field("attempt"))

      expect(webhook.to_h.slice("event_field", "status_field", "id_field", "external_id_field", "error_code_path",
                                "error_message_path").values).to all(be_nil)
    end
  end

  describe "events" do
    def events_for(enum)
      analyse(operation(request_fields: [field("event_type", enum:)])).events
    end

    it "maps each enum value through statuses.yml, by the last token or an earlier one" do
      aggregate_failures do
        expect(events_for(%w[payout.completed]).first.to_h)
          .to eq("value" => "payout.completed", "canonical_status" => "approved", "confidence" => 0.95,
                 "source" => "dictionary")
        expect(events_for(%w[payout.cancelled.final]).first.to_h)
          .to eq("value" => "payout.cancelled.final", "canonical_status" => "rejected", "confidence" => 0.85,
                 "source" => "token")
      end
    end

    it "warns (W203) and records no status for an event the dictionary does not know" do
      events = events_for(%w[payout.completed payout.escalated])

      aggregate_failures do
        expect(events.last.to_h).to eq("value" => "payout.escalated", "canonical_status" => nil,
                                       "confidence" => 0.0, "source" => "none")
        expect(log.with_code("W203").map(&:message))
          .to eq(["Webhook event payout.escalated has no canonical status; the service treats it as unknown_event"])
      end
    end
  end

  describe "examples and the answer" do
    it "keeps the named examples, falls back to the single one and stays empty without a body" do
      named = models::RequestBody.new(content_type: "application/json", required: true, schema_name: nil,
                                      example: { "event" => "one" }, examples: { "paid" => { "event" => "two" } })
      single = models::RequestBody.new(content_type: "application/json", required: true, schema_name: nil,
                                       example: { "event" => "one" }, examples: {})

      aggregate_failures do
        expect(analyse(operation(request_body: named)).examples).to eq("paid" => { "event" => "two" })
        expect(analyse(operation(request_body: single)).examples).to eq("default" => { "event" => "one" })
        expect(analyse(operation).examples).to eq({})
      end
    end

    it "answers with the first success response and with nil when the spec declares none" do
      created = models::Response.new(http: 202, description: "Accepted", schema_name: nil, kind: "success",
                                     content_type: nil, example: nil, headers: [])
      error = models::Response.new(http: 400, description: "Bad", schema_name: nil, kind: "error",
                                   content_type: nil, example: nil, headers: [])

      aggregate_failures do
        expect(analyse(operation(responses: [error, created])).response.to_h)
          .to eq("http" => 202, "example" => nil)
        expect(analyse(operation(responses: [error])).response).to be_nil
      end
    end
  end

  describe "the signature the payload itself carries" do
    it "uses a top-level payload field when no parameter is marked as the signature" do
      fields = [field("sign", description: "MD5 of the concatenated fields, hex"), field("event")]
      webhook = analyse(operation(request_fields: fields))

      aggregate_failures do
        expect(webhook.signature.to_h).to include("location" => "body", "name" => "sign", "algorithm" => "md5",
                                                  "encoding" => "hex", "message" => "concatenated_fields",
                                                  "source" => "field")
        expect(log.with_code("I301").map(&:location)).to eq(["#/paths/~1webhooks~1payout/post"])
      end
    end

    it "ignores a nested field that only looks like a signature" do
      webhook = analyse(operation(request_fields: [field("data.sign", description: "MD5 of the fields, hex"),
                                                   field("event")]))

      aggregate_failures do
        expect(webhook.signature).to be_nil
        expect(log.include?("I301")).to be(false)
      end
    end

    it "leaves the signature nil when neither a parameter nor a payload field declares one" do
      webhook = analyse(operation(request_fields: [field("event")]))

      aggregate_failures do
        expect(webhook.signature).to be_nil
        expect(log.include?("I301")).to be(false)
        expect(log.include?("W301")).to be(false)
      end
    end
  end

  describe "the signature overrides.yml pins" do
    let(:overrides) do
      ProviderIntegrator::Normalizer::Overrides.new(
        { "signature" => { "header" => "X-Sign", "algorithm" => "hmac-sha512", "encoding" => "hex",
                           "message" => "raw_body" } }, log
      )
    end

    it "signs a webhook whose operation declares nothing, and asks for no confirmation" do
      webhook = analyse(operation(request_fields: [field("event")]))

      aggregate_failures do
        expect(webhook.signature.to_h).to eq(
          "location" => "header", "name" => "X-Sign", "algorithm" => "hmac-sha512", "encoding" => "hex",
          "message" => "raw_body", "secret" => "callback_secret", "confidence" => 0.9,
          "evidence" => ["overrides.yml: signature X-Sign (header)"], "source" => "override"
        )
        expect(log.with_code("I301").map(&:location)).to eq(["#/paths/~1webhooks~1payout/post"])
        expect(log.include?("W301")).to be(false)
      end
    end
  end
end
