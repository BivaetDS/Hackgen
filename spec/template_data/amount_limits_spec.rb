# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::AmountLimits do
  let(:canon) { ProviderIntegrator::TemplateData::Canon.new }
  let(:operation) { GenerationHelpers.novapay_spec.operation_for("create_request") }
  let(:amount) { operation.request_fields.find { |field| field.canonical == "amount" } }

  def with_amount(field)
    operation.with(request_fields: operation.request_fields.map { |item| item.canonical == "amount" ? field : item })
  end

  it "converts the minimum in kopecks into the major units of operation.amount" do
    limits = described_class.for(operation, canon)

    aggregate_failures do
      expect(limits.map(&:name)).to eq(["MIN_AMOUNT"])
      expect(limits.first.value).to eq(1000)
      expect(limits.first.comment)
        .to eq("minimum of amount: 100000 in minor units of the provider = 1000 in major units of operation.amount.")
      expect(limits.first.evidence).to start_with("Evidence: description: копейках")
    end
  end

  it "keeps fractions as floats and adds MAX_AMOUNT when a maximum is declared" do
    limits = described_class.for(with_amount(amount.with(minimum: 150, maximum: 10_000_000)), canon)

    expect(limits.map { |limit| [limit.name, limit.value] }).to eq([["MIN_AMOUNT", 1.5], ["MAX_AMOUNT", 100_000]])
  end

  it "leaves the value untouched without a conversion or with an identity one" do
    identity = amount.conversion.with(type: "identity", value: 1, unit_to: "major")
    limits = described_class.for(with_amount(amount.with(minimum: 10, conversion: identity)), canon)

    aggregate_failures do
      expect(limits.first.value).to eq(10)
      expect(limits.first.comment).to eq("minimum of amount: 10 (major units).")
      expect(described_class.for(with_amount(amount.with(minimum: nil)), canon)).to eq([])
      expect(described_class.for(nil, canon)).to eq([])
    end
  end
end
