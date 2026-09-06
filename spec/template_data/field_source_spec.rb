# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::FieldSource do
  let(:spec) { GenerationHelpers.novapay_spec }
  let(:context) { ProviderIntegrator::Generator::Context.new(spec:) }
  let(:canon) { ProviderIntegrator::TemplateData::Canon.new }
  let(:operation) { spec.operation_for("create_request") }
  let(:scope) { ProviderIntegrator::TemplateData::Scope.build(branch: "sbp") }
  let(:source) { described_class.new(operation, canon:, context:, scope:) }

  def field(path) = operation.request_fields.find { |item| item.provider_path == path }

  it "converts the amount through the helper the conversion asks for, citing the evidence" do
    result = source.for(field("amount"))

    aggregate_failures do
      expect(result.expression).to eq("amount_in_minor_units(operation.amount)")
      expect(result.helper.name).to eq("amount_in_minor_units")
      expect(result.comments).to eq(["Evidence: description: копейках; error example (422): kopecks; minimum: 100000"])
      expect(result.doc).to include("`operation.amount` x 100")
    end
  end

  it "turns a single-value enum into a constant and the discriminator into the branch value" do
    aggregate_failures do
      expect(source.for(field("currency")).expression).to eq("'RUB'")
      expect(source.for(field("recipient.type")).expression).to eq("'sbp'")
      expect(source.for(field("external_id")).expression).to eq("operation.id")
    end
  end

  it "reads requisites from the payout method hash and marks conditional ones with a TODO" do
    bank_code = source.for(field("recipient.bank_code"))

    aggregate_failures do
      expect(bank_code.expression).to eq("operation.payout_requisite.dig('sbp', 'bank_code')")
      expect(bank_code.comments).to eq(["TODO(confidence 0.6): required when recipient.type = sbp " \
                                        "(description: обязателен для type=sbp)"])
      expect(source.for(field("recipient.phone")).comments).to eq([])
    end
  end

  it "uses the run-time request_method when no branch is fixed" do
    unbranched = described_class.new(operation, canon:, context:)

    aggregate_failures do
      expect(unbranched.for(field("recipient.type")).expression).to eq("request_method")
      expect(unbranched.for(field("recipient.phone")).expression)
        .to eq("operation.payout_requisite.dig(request_method, 'phone')")
    end
  end

  context "with fields the platform has no source for" do
    let(:base) { field("recipient.bank_name") }

    it "omits an optional unmapped field and sends nil with a TODO for a required one" do
      optional = base.with(canonical: nil)
      required = base.with(canonical: nil, required: true, confidence: 0.0)

      aggregate_failures do
        expect(source.for(optional)).to be_omitted
        expect(source.for(required).expression).to eq("nil")
        expect(source.for(required).comments.first)
          .to start_with("TODO(confidence 0.0): required field recipient.bank_name")
      end
    end

    it "sends callback URLs from an ENV constant and merchant ids from the credentials" do
      callback = base.with(canonical: "callback_url", provider_path: "notify_url")
      merchant = base.with(canonical: "merchant_account", provider_path: "merchant_id")

      aggregate_failures do
        expect(source.for(callback)).to have_attributes(expression: "CALLBACK_URL", env_constant: "callback_url")
        expect(source.for(callback).doc).to include("NOVAPAY_CALLBACK_URL")
        expect(source.for(merchant).expression).to eq("credentials[:merchant_id]")
      end
    end
  end

  it "borrows the create conversion for another operation's amount and says so" do
    scope = ProviderIntegrator::TemplateData::Scope.build(fallback_conversion: field("amount").conversion)
    borrowed = described_class.new(operation, canon:, context:, scope:)
    result = borrowed.for(field("amount").with(conversion: nil))

    aggregate_failures do
      expect(result.expression).to eq("amount_in_minor_units(operation.amount)")
      expect(result.comments.last).to eq("Units assumed equal to create_request (not analysed for this operation)")
    end
  end
end
