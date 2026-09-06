# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::FieldSchema do
  let(:spec) { GenerationHelpers.novapay_spec }
  let(:create) { spec.operation_for("create_request") }

  it "rebuilds a nested object schema with the required lists of every level" do
    schema = described_class.for(create.request_fields)

    aggregate_failures do
      expect(schema["required"]).to eq(%w[amount currency external_id recipient])
      expect(schema["properties"]["amount"]).to eq("type" => "integer", "minimum" => 100_000)
      expect(schema["properties"]["currency"]["enum"]).to eq(["RUB"])
      expect(schema.dig("properties", "recipient", "required")).to eq(%w[type phone])
      expect(schema.dig("properties", "recipient", "properties", "phone", "pattern")).to eq("^7\\d{10}$")
    end
  end

  it "keeps conditionally required and branch fields optional" do
    schema = described_class.for(create.request_fields)

    expect(schema.dig("properties", "recipient", "required")).not_to include("bank_code", "card_number")
  end

  it "accepts the spec example and rejects a wrong type through json_schemer" do
    schema = JSONSchemer.schema(described_class.for(create.request_fields))

    aggregate_failures do
      expect(schema.valid?(create.request_body.example)).to be(true)
      expect(schema.valid?(create.request_body.example.merge("amount" => "1500"))).to be(false)
      expect(schema.valid?(create.request_body.example.except("recipient"))).to be(false)
    end
  end

  it "models array items from items[] paths" do
    fields = GenerationHelpers.generate_fixture("bearerpay").files && ProviderIntegrator::Parser
             .call!(path: repo_path("spec", "fixtures", "specs", "bearerpay.yaml"))
             .operations.find { |operation| operation.operation_id == "listTransfers" }.response_fields
    schema = described_class.for(fields)

    aggregate_failures do
      expect(schema.dig("properties", "items", "type")).to eq("array")
      expect(schema.dig("properties", "items", "items", "properties", "status",
                        "enum")).to eq(%w[NEW SENT DONE DECLINED])
    end
  end
end
