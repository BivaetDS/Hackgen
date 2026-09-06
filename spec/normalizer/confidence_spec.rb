# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Normalizer::Confidence do
  describe ".from_scores" do
    it "is the margin of the leader over the runner-up: (best - second) / (best + 1)" do
      aggregate_failures do
        expect(described_class.from_scores({ "create" => 9, "status" => 0 })).to eq(0.9)
        expect(described_class.from_scores({ "create" => 11, "status" => 3 })).to eq(0.67)
        expect(described_class.from_scores({ "create" => 6, "cancel" => 5 })).to eq(0.14)
      end
    end

    it "ignores every score below the runner-up" do
      expect(described_class.from_scores({ "create" => 8, "status" => 5, "cancel" => 3, "list" => 0 })).to eq(0.33)
    end

    it "treats a lone leader as if the runner-up scored zero" do
      expect(described_class.from_scores({ "create" => 5 })).to eq(0.83)
    end

    it "rounds to two decimals, the storage format of every confidence in the IR" do
      aggregate_failures do
        expect(described_class.from_scores({ "create" => 2 })).to eq(0.67)
        expect(described_class.from_scores({ "create" => 3 })).to eq(0.75)
        expect(described_class.from_scores({ "create" => 100 })).to eq(0.99)
      end
    end

    it "is 0.0 for a tie for the lead: a draw decides nothing" do
      aggregate_failures do
        expect(described_class.from_scores({ "create" => 5, "cancel" => 5 })).to eq(0.0)
        expect(described_class.from_scores({ "create" => 5, "cancel" => 5, "status" => 3 })).to eq(0.0)
      end
    end

    it "is 0.0 when nothing scored" do
      aggregate_failures do
        expect(described_class.from_scores({ "create" => 0, "status" => 0 })).to eq(0.0)
        expect(described_class.from_scores({})).to eq(0.0)
      end
    end
  end

  describe ".round" do
    it "returns a two-decimal Float, never an Integer" do
      aggregate_failures do
        expect(described_class.round(0.666666)).to eq(0.67)
        expect(described_class.round(0.9)).to eq(0.9)
        expect(described_class.round(1)).to be_a(Float).and eq(1.0)
      end
    end
  end

  describe ".thresholds" do
    it "reads the classification thresholds from operations.yml" do
      expect(described_class.thresholds).to eq(ProviderIntegrator::Dictionaries.operations.fetch("thresholds"))
    end

    it "orders them unknown_below < structural_only_cap < low_confidence_below" do
      thresholds = described_class.thresholds

      aggregate_failures do
        expect(thresholds.fetch("unknown_below")).to eq(0.3)
        expect(thresholds.fetch("structural_only_cap")).to eq(0.5)
        expect(thresholds.fetch("low_confidence_below")).to eq(0.6)
      end
    end
  end
end
