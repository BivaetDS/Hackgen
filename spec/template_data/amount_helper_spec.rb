# frozen_string_literal: true

# apply/reverse are the generation-time twins of the helper the service gets: the generated spec
# builds operation.amount out of a fixture value with reverse and expects apply of it to be sent.
RSpec.describe ProviderIntegrator::TemplateData::AmountHelper do
  def conversion(type, value = nil, unit_from: "major", unit_to: "minor")
    ProviderIntegrator::Models::Conversion.new(type:, value:, unit_from:, unit_to:, confidence: 0.9, evidence: [],
                                               source: "inference")
  end

  describe ".for" do
    it "names the helper after the direction of the conversion and has none for identity" do
      aggregate_failures do
        expect(described_class.for(conversion("multiply", 100)).name).to eq("amount_in_minor_units")
        expect(described_class.for(conversion("divide", 100)).name).to eq("amount_in_major_units")
        expect(described_class.for(conversion("to_decimal_string")).name).to eq("amount_as_decimal_string")
        expect(described_class.for(conversion("identity", 1))).to be_nil
      end
    end
  end

  describe ".reverse and .apply" do
    it "turns kopecks back into rubles and rubles into kopecks (multiply)" do
      multiply = conversion("multiply", 100)

      aggregate_failures do
        expect(described_class.reverse(multiply, 1_500_000)).to eq(15_000)
        expect(described_class.reverse(multiply, 12_345)).to eq(123.45)
        expect(described_class.apply(multiply, 15_000)).to eq(1_500_000)
        expect(described_class.apply(multiply, 123.45)).to eq(12_345)
      end
    end

    it "inverts a division and a decimal string" do
      divide = conversion("divide", 100, unit_from: "minor", unit_to: "major")
      decimal = conversion("to_decimal_string")

      aggregate_failures do
        expect(described_class.reverse(divide, 15.5)).to eq(1550)
        expect(described_class.apply(divide, 1550)).to eq(15.5)
        expect(described_class.reverse(decimal, "1500.00")).to eq(1500)
        expect(described_class.apply(decimal, 1500)).to eq("1500.00")
        expect(described_class.apply(decimal, described_class.reverse(decimal, "10.15"))).to eq("10.15")
      end
    end

    it "passes identity and missing conversions through and returns nil for non-numeric input" do
      aggregate_failures do
        expect(described_class.reverse(nil, 42)).to eq(42)
        expect(described_class.apply(nil, 42)).to eq(42)
        expect(described_class.reverse(conversion("identity", 1), "7.5")).to eq(7.5)
        expect(described_class.reverse(conversion("multiply", 100), "not a number")).to be_nil
      end
    end
  end
end
