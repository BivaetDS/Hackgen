# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Generator::FixturesGenerator do
  let(:fixtures) { JSON.parse(GenerationHelpers.novapay_file(:fixtures)) }

  it "follows the reference layout: create_request, fetch_status, callback, callback_failed, then extras" do
    expect(fixtures.keys).to eq(%w[create_request fetch_status callback callback_failed cancel_request fetch_balance])
  end

  it "takes the create request and the declared responses from the spec examples" do
    create = fixtures["create_request"]

    aggregate_failures do
      expect(create.keys).to eq(%w[request response_201 response_400 response_401 response_402 response_409
                                   response_422 response_429 response_500])
      expect(create["request"]).to eq("amount" => 1_500_000, "currency" => "RUB", "external_id" => "op_abc123",
                                      "recipient" => { "bank_code" => "044525225", "bank_name" => "Сбербанк",
                                                       "phone" => "79001234567", "type" => "sbp" })
      expect(create["response_201"]).to include("id" => "np_7f3a9b2c", "status" => "pending")
      expect(create["response_422"]["error"]).to include("code" => "validation_error")
      expect(create["response_201"]).not_to have_key("_synthetic")
    end
  end

  it "synthesizes error bodies the spec gives no example for and marks them" do
    aggregate_failures do
      expect(fixtures["create_request"]["response_400"])
        .to eq("error" => { "code" => "validation_error", "message" => "Некорректный запрос" }, "_synthetic" => true)
      expect(fixtures["create_request"]["response_500"]["error"]["code"]).to eq("internal_error")
    end
  end

  it "adds a final status to success examples that lack one and says so" do
    status = fixtures["fetch_status"]["response_200"]

    aggregate_failures do
      expect(status).to include("id" => "np_7f3a9b2c", "status" => "completed", "_synthetic_fields" => ["status"])
      expect(fixtures["create_request"]["response_409"]).to include("status" => "completed")
      expect(fixtures["fetch_status"]["response_404"]).not_to have_key("_synthetic_fields")
    end
  end

  it "pairs each webhook example with the operation status the service will report" do
    aggregate_failures do
      expect(fixtures["callback"]).to eq("payload" => { "completed_at" => "2026-07-30T10:05:00Z",
                                                        "event" => "payout.completed", "external_id" => "op_abc123",
                                                        "payout_id" => "np_7f3a9b2c", "status" => "completed" },
                                         "expected_operation_status" => "approved")
      expect(fixtures["callback_failed"]["expected_operation_status"]).to eq("rejected")
      expect(fixtures["callback_failed"]["payload"]["error"]).to eq("code" => "recipient_not_found",
                                                                    "message" => "Recipient account not found")
    end
  end

  it "covers the methods outside the contract" do
    aggregate_failures do
      expect(fixtures["cancel_request"].keys).to eq(%w[response_200 response_409])
      expect(fixtures["fetch_balance"]["response_200"]).to include("balance" => 500_000_000, "currency" => "RUB")
    end
  end

  it "synthesizes callbacks and requests by type when the spec has no examples" do
    fixtures = JSON.parse(GenerationHelpers.generate_fixture("legacy_swagger2").file(:fixtures).content)
    request = fixtures["create_request"]["request"]

    aggregate_failures do
      expect(fixtures.keys.grep(/\Acallback/)).to include("callback", "callback_failed")
      expect(fixtures["callback"]).to include("_synthetic" => true, "expected_operation_status" => "approved")
      expect(fixtures["callback"]["payload"]["notification_type"]).to eq("PAYMENT_PAID")
      expect(request).to include("merchant_id", "order_id", "sum", "payment_type", "_synthetic_fields")
    end
  end

  it "serializes in insertion order with a trailing newline (JSON.pretty_generate, not sorted keys)" do
    content = GenerationHelpers.novapay_file(:fixtures)

    aggregate_failures do
      expect(content).to start_with("{\n  \"create_request\": {\n    \"request\": {")
      expect(content).to end_with("}\n")
      expect(content).not_to include("\r")
    end
  end
end
