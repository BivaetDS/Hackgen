# frozen_string_literal: true

RSpec.describe ProviderIntegrator::JsonCanon do
  describe ".generate" do
    it "sorts object keys at every depth, keeps array order and ends with a newline" do
      value = { "z" => 1, "a" => { "d" => [3, { "y" => 1, "x" => 2 }], "c" => nil }, "m" => [] }

      expect(described_class.generate(value)).to eq(<<~JSON)
        {
          "a": {
            "c": null,
            "d": [
              3,
              {
                "x": 2,
                "y": 1
              }
            ]
          },
          "m": [],
          "z": 1
        }
      JSON
    end

    it "is independent of insertion order and of String/Symbol keys" do
      a = described_class.generate({ b: 1, a: { d: 1, c: 2 } })
      b = described_class.generate({ "a" => { "c" => 2, "d" => 1 }, "b" => 1 })

      expect(a).to eq(b)
    end

    it "keeps floats and integers distinct and UTF-8 unescaped" do
      text = described_class.generate({ "confidence" => 1.0, "ir_version" => 1, "name" => "Сбербанк" })

      expect(text).to include('"confidence": 1.0', '"ir_version": 1', '"name": "Сбербанк"')
    end

    it "rejects keys that are neither String nor Symbol" do
      expect { described_class.generate({ 1 => "x" }) }.to raise_error(ArgumentError, /keys must be Strings/)
    end
  end

  describe ".canonicalize" do
    it "converts Symbol values to Strings and leaves scalars untouched" do
      expect(described_class.canonicalize({ k: :sym, n: 2, f: 0.5, b: true, x: nil }))
        .to eq({ "b" => true, "f" => 0.5, "k" => "sym", "n" => 2, "x" => nil })
    end
  end

  describe ".stringify_keys" do
    it "deep-converts keys without reordering" do
      expect(described_class.stringify_keys({ b: [{ d: 1, c: 2 }], a: 1 }).keys).to eq(%w[b a])
    end
  end

  describe ".parse" do
    it "round-trips canonical output" do
      value = { "a" => [1, 2.5, "x", nil, true], "b" => { "c" => {} } }

      expect(described_class.parse(described_class.generate(value))).to eq(value)
    end
  end

  describe ".sha256" do
    it "hashes bytes deterministically regardless of string encoding" do
      utf8 = "Сбербанк"
      expect(described_class.sha256(utf8)).to eq(described_class.sha256(utf8.b))
      expect(described_class.sha256("")).to eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    end
  end
end
