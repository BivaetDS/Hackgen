# frozen_string_literal: true

# Rich example Hashes for the composite IR models; they reuse the leaf examples from ModelExamples::CORE.
module ModelExamples
  FIELD = { provider_path: "recipient.bank_code", canonical: "requisite.bank_code", type: "string", format: nil,
            required: false, nullable: false, enum: nil, constant: nil, pattern: nil, minimum: nil, maximum: nil,
            min_length: nil, max_length: nil, description: "БИК банка (обязателен для type=sbp)", example: "044525225",
            default: nil, conversion: nil, conditional_required: CORE["ConditionalRequired"],
            branch: CORE["Branch"], confidence: 1.0, evidence: ["dictionary: bank_code -> requisite.bank_code"],
            source: "dictionary" }.freeze

  AMOUNT = FIELD.merge(provider_path: "amount", canonical: "amount", type: "integer", required: true,
                       minimum: 100_000, description: "Сумма в копейках", example: 1_500_000,
                       conversion: CORE["Conversion"], conditional_required: nil, branch: nil).freeze

  RESPONSE = { http: 429, description: "Too many requests", schema_name: "ErrorResponse", kind: "error",
               content_type: "application/json", example: nil, headers: [CORE["ResponseHeader"]] }.freeze

  OPERATION = { kind: "create", in_contract: true, canonical_method: "create_request", operation_id: "createPayout",
                method: "POST", path: "/payouts", summary: "Create payout", description: nil, tags: ["Payouts"],
                security: ["ApiKeyAuth"], public: false, classification: CORE["Classification"],
                idempotency: CORE["Idempotency"], parameters: [CORE["Parameter"]], request_body: CORE["RequestBody"],
                request_fields: [AMOUNT, FIELD], response_fields: [AMOUNT], responses: [RESPONSE],
                success_codes: [201, 409], idempotent_duplicate_codes: [409], errors: [CORE["ErrorMapping"]],
                request_methods: CORE["RequestMethods"], confidence: 0.9 }.freeze

  WEBHOOK = { path: "/webhooks/payout", method: "POST", operation_id: "payoutWebhook", summary: "Webhook",
              source: "path_heuristic", confidence: 0.87, evidence: ["path: webhooks -> webhook +3"],
              signature: CORE["Signature"], event_field: "event", events: [CORE["WebhookEvent"]],
              status_field: "status", id_field: "payout_id", external_id_field: "external_id",
              error_code_path: "error.code", error_message_path: "error.message", payload_fields: [FIELD],
              examples: { "completed" => { "event" => "payout.completed", "status" => "completed" } },
              response: CORE["WebhookResponse"] }.freeze

  IR = {
    "FieldMapping" => FIELD,
    "Response" => RESPONSE,
    "Operation" => OPERATION,
    "Webhook" => WEBHOOK,
    "ProviderSpec" => { ir_version: 1, provider: CORE["Provider"], spec_format: CORE["SpecFormat"],
                        servers: [CORE["Server"]], authentication: CORE["Authentication"], operations: [OPERATION],
                        statuses: [CORE["StatusMapping"]], webhook: WEBHOOK, gateway_config: CORE["GatewayConfig"],
                        overrides_applied: [CORE["OverrideApplied"]], events: [CORE["Event"]],
                        extensions: { "x-space-payments-operation" => "create" } }
  }.freeze

  # { "ModelName" => example Hash } for every serializable model.
  def self.all
    CORE.merge(IR)
  end
end
