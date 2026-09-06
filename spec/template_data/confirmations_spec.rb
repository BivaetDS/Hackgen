# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::Confirmations do
  let(:items) { described_class.new(GenerationHelpers.novapay_spec).items }

  it "collects every warning and the critical infos, in IR order" do
    expect(items.map(&:code)).to eq(%w[W301 W402 W402 I201 I301 I401 I403])
  end

  it "points each item at the generated code and carries the signals as evidence" do
    units = items.find { |item| item.code == "I401" }

    aggregate_failures do
      expect(items.map(&:where).uniq).to eq(["verify_signature!", "check_conditions, REQUIRED_REQUISITES", "STATUS_MAP",
                                             "build_*_payload, MIN_AMOUNT", "ProviderGateway config"])
      expect(units.evidence).to eq(["description: копейках", "error example (422): kopecks", "minimum: 100000"])
      expect(items.first.location).to eq("#/paths/~1webhooks~1payout/post/parameters/0")
    end
  end

  it "leaves plain infos such as I101 out" do
    expect(items.map(&:code)).not_to include("I101", "W102")
  end
end
