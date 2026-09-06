# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::Code do
  describe ".key" do
    it "uses symbol keys for identifiers and quoted rockets otherwise" do
      aggregate_failures do
        expect(described_class.key("amount")).to eq("amount:")
        expect(described_class.key("bank-code")).to eq("'bank-code' =>")
        expect(described_class.key("X-Sign")).to eq("'X-Sign' =>")
      end
    end
  end

  describe ".hash_lines" do
    it "renders entries with commas, comments above and nested hashes as multi-line values" do
      nested = described_class.hash_lines(["type: 'sbp'", "phone: p"], open: "recipient: {", close: "}.compact")
      entry = described_class::Entry["amount: a", "Evidence: minimum 1", nil]
      lines = described_class.hash_lines([entry, described_class::Entry[nested.join("\n")]], close: "}.compact")

      expect(lines).to eq(["{", "  # Evidence: minimum 1", "  amount: a,", "  recipient: {", "    type: 'sbp',",
                           "    phone: p", "  }.compact", "}.compact"])
    end

    it "renders an empty literal on one line" do
      expect(described_class.hash_lines([])).to eq(["{}"])
    end
  end

  describe ".access" do
    it "indexes one segment and digs several, dropping array markers" do
      aggregate_failures do
        expect(described_class.access("body", "status")).to eq("body['status']")
        expect(described_class.access("body", "error.code")).to eq("body.dig('error', 'code')")
        expect(described_class.access("body", "items[].id")).to eq("body.dig('items', 'id')")
      end
    end
  end

  describe ".word_array" do
    it "prefers %w[] and falls back to an Array literal" do
      aggregate_failures do
        expect(described_class.word_array(%w[sbp card])).to eq("%w[sbp card]")
        expect(described_class.word_array(["a b"])).to eq("['a b']")
        expect(described_class.word_array([])).to eq("[]")
      end
    end
  end

  describe ".wrap" do
    it "wraps long comments at the width and keeps explicit line breaks" do
      lines = described_class.wrap("#{"word " * 30}end\nsecond", width: 40)

      aggregate_failures do
        expect(lines.map(&:length)).to all(be <= 40)
        expect(lines.last).to eq("second")
        expect(lines.join(" ")).to eq("#{"word " * 30}end second")
      end
    end
  end

  describe ".indent" do
    it "indents two spaces per level and leaves blank lines empty" do
      expect(described_class.indent(["a", "", "b"], 2)).to eq("    a\n\n    b")
    end
  end
end
