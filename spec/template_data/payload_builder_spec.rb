# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::PayloadBuilder do
  let(:spec) { GenerationHelpers.novapay_spec }
  let(:operation) { spec.operation_for("create_request") }

  def field(path) = operation.request_fields.find { |item| item.provider_path == path }

  describe ".in_branch?" do
    it "keeps shared fields, drops requisites that are only required for another payout method" do
      aggregate_failures do
        expect(described_class.in_branch?(field("amount"), "sbp", operation)).to be(true)
        expect(described_class.in_branch?(field("recipient.bank_code"), "sbp", operation)).to be(true)
        expect(described_class.in_branch?(field("recipient.bank_code"), "card", operation)).to be(false)
        expect(described_class.in_branch?(field("recipient.card_number"), "sbp", operation)).to be(false)
        expect(described_class.in_branch?(field("recipient.card_number"), nil, operation)).to be(true)
      end
    end

    it "follows the oneOf branch of a field when it has one" do
      branch = ProviderIntegrator::Models::Branch.new(discriminator_path: "recipient.type", value: "card")
      branched = field("recipient.bank_name").with(branch:)

      aggregate_failures do
        expect(described_class.in_branch?(branched, "card", operation)).to be(true)
        expect(described_class.in_branch?(branched, "sbp", operation)).to be(false)
      end
    end
  end

  describe "#call" do
    it "renders the sbp payload of NovaPay with nested compact hashes and the evidence comments" do
      context = ProviderIntegrator::Generator::Context.new(spec:)
      canon = ProviderIntegrator::TemplateData::Canon.new
      scope = ProviderIntegrator::TemplateData::Scope.build(branch: "sbp")
      result = described_class.new(operation, canon:, context:, scope:).call

      aggregate_failures do
        expect(result.lines.first).to eq("{")
        expect(result.lines).to include("  amount: amount_in_minor_units(operation.amount),", "  recipient: {",
                                        "    bank_code: operation.payout_requisite.dig('sbp', 'bank_code'),",
                                        "  }.compact", "}.compact")
        expect(result.lines.join("\n")).not_to include("card_number")
        expect(result.helpers.map(&:name)).to eq(["amount_in_minor_units"])
        expect(result.docs.map(&:first)).to eq(%w[amount currency external_id recipient.type recipient.phone
                                                  recipient.bank_code recipient.bank_name])
      end
    end
  end
end
