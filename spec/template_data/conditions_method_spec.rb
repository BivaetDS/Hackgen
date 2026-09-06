# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::ConditionsMethod do
  describe ".required_requisites" do
    it "lists the requisites of each NovaPay payout method by the schema and the conditions" do
      expect(described_class.required_requisites(GenerationHelpers.novapay_spec.operation_for("create_request")))
        .to eq("sbp" => %w[phone bank_code], "card" => %w[phone card_number])
    end

    it "leaves the discriminator out: it is a constant of the branch, not a value the platform supplies" do
      spec = ProviderIntegrator::Parser.call!(path: fixture_path("specs", "rublepay.yaml"))
      requisites = described_class.required_requisites(spec.operation_for("create_request"))

      aggregate_failures do
        expect(requisites["card"]).to eq(%w[card_number expiry_month expiry_year cvc])
        expect(requisites["sbp"]).to eq(%w[bank_code])
        expect(requisites.values.flatten).not_to include("source_type")
      end
    end

    it "returns a flat list without payout methods and nil without requisites" do
      create = GenerationHelpers.novapay_spec.operation_for("create_request")
      bare = create.with(request_fields: create.request_fields.reject { |f| f.canonical.to_s.start_with?("requisite") })

      aggregate_failures do
        expect(described_class.required_requisites(create.with(request_methods: nil))).to eq(%w[phone])
        expect(described_class.required_requisites(bare)).to be_nil
        expect(described_class.required_requisites(nil)).to be_nil
      end
    end
  end
end
