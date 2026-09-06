# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::Pointer do
  describe ".escape" do
    it "escapes a tilde before a slash, per RFC 6901" do
      aggregate_failures do
        expect(described_class.escape("/payouts/{payout_id}")).to eq("~1payouts~1{payout_id}")
        expect(described_class.escape("a~b")).to eq("a~0b")
        expect(described_class.escape("a~1b")).to eq("a~01b")
        expect(described_class.escape("get")).to eq("get")
        expect(described_class.escape(0)).to eq("0")
      end
    end
  end

  describe ".unescape" do
    it "expands ~1 before ~0, so escape is reversible" do
      aggregate_failures do
        expect(described_class.unescape("~1payouts~1{payout_id}")).to eq("/payouts/{payout_id}")
        expect(described_class.unescape("a~0b")).to eq("a~b")
        expect(described_class.unescape("a~01b")).to eq("a~1b")
        expect(described_class.unescape("plain")).to eq("plain")
      end
    end

    it "round-trips every segment through escape" do
      segments = ["/payouts/{payout_id}", "a~b", "~1", "components", "x-space-payments-operation"]

      expect(segments.map { |segment| described_class.unescape(described_class.escape(segment)) }).to eq(segments)
    end
  end

  describe ".build" do
    it "builds the event locations of docs/IR_CONTRACT.md section 3" do
      aggregate_failures do
        expect(described_class.build("paths", "/payouts/{payout_id}", "get"))
          .to eq("#/paths/~1payouts~1{payout_id}/get")
        expect(described_class.build("components", "schemas", "Recipient", "properties", "bank_code"))
          .to eq("#/components/schemas/Recipient/properties/bank_code")
      end
    end

    it "flattens arrays and stringifies non-String segments" do
      aggregate_failures do
        expect(described_class.build(["paths", "/payouts"], "post")).to eq("#/paths/~1payouts/post")
        expect(described_class.build("paths", "/payouts", "post", "parameters", 0))
          .to eq("#/paths/~1payouts/post/parameters/0")
      end
    end
  end

  describe ".join" do
    it "appends escaped segments to an existing pointer" do
      aggregate_failures do
        expect(described_class.join("#/paths/~1payouts/post", "parameters", 0))
          .to eq("#/paths/~1payouts/post/parameters/0")
        expect(described_class.join("#/paths", "/payouts")).to eq("#/paths/~1payouts")
      end
    end

    it "starts a fresh pointer from the document root for nil and \"#\"" do
      aggregate_failures do
        expect(described_class.join(nil, "paths", "/payouts")).to eq("#/paths/~1payouts")
        expect(described_class.join("#", "paths", "/payouts")).to eq("#/paths/~1payouts")
      end
    end
  end

  describe ".parse" do
    it "splits a local pointer into unescaped segments" do
      aggregate_failures do
        expect(described_class.parse("#/paths/~1payouts~1{payout_id}/get"))
          .to eq(["paths", "/payouts/{payout_id}", "get"])
        expect(described_class.parse("#")).to eq([])
        expect(described_class.parse("#/a//b")).to eq(["a", "", "b"])
      end
    end

    it "returns nil for anything that does not address this document" do
      aggregate_failures do
        expect(described_class.parse("other.yaml#/X")).to be_nil
        expect(described_class.parse("https://example.test/schema.yaml#/X")).to be_nil
        expect(described_class.parse("#components")).to be_nil
        expect(described_class.parse(nil)).to be_nil
        expect(described_class.parse(42)).to be_nil
      end
    end

    it "round-trips the segments of build" do
      segments = ["paths", "/payouts/{payout_id}", "get", "responses", "200"]

      expect(described_class.parse(described_class.build(*segments))).to eq(segments)
    end
  end

  describe ".local?" do
    it "accepts document-local references only" do
      aggregate_failures do
        expect(described_class.local?("#/components/schemas/Recipient")).to be(true)
        expect(described_class.local?("#")).to be(true)
        expect(described_class.local?("other.yaml#/X")).to be(false)
        expect(described_class.local?("https://example.test/schema.yaml#/X")).to be(false)
        expect(described_class.local?("definitions.json")).to be(false)
        expect(described_class.local?(nil)).to be(false)
      end
    end
  end
end
