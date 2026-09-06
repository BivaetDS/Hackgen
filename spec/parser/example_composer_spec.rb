# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::ExampleComposer do
  let(:log) { ProviderIntegrator::EventLog.new }
  let(:components) { {} }
  let(:composer) do
    root = { "components" => components }
    described_class.new(ProviderIntegrator::Parser::Document.new(root:, log:, spec_format: "3.0.3"))
  end

  describe "#for_media" do
    let(:components) { { "schemas" => { "Payout" => { "type" => "object", "example" => { "from" => "schema" } } } } }

    it "prefers the media example over every other source" do
      media = { "example" => { "from" => "media" },
                "examples" => { "ok" => { "value" => { "from" => "examples" } } },
                "schema" => { "$ref" => "#/components/schemas/Payout" } }

      expect(composer.for_media(media, "#/m")).to eq({ "from" => "media" })
    end

    it "falls back to the value of the first named example, in document order" do
      media = { "examples" => { "accepted" => { "value" => { "status" => "pending" } },
                                "rejected" => { "value" => { "status" => "rejected" } } },
                "schema" => { "$ref" => "#/components/schemas/Payout" } }

      expect(composer.for_media(media, "#/m")).to eq({ "status" => "pending" })
    end

    it "falls back to the schema example when the media declares none" do
      expect(composer.for_media({ "schema" => { "$ref" => "#/components/schemas/Payout" } }, "#/m"))
        .to eq({ "from" => "schema" })
    end

    it "returns nil for a media object with neither example nor schema" do
      aggregate_failures do
        expect(composer.for_media(nil, "#/m")).to be_nil
        expect(composer.for_media({}, "#/m")).to be_nil
        expect(composer.for_media({ "schema" => { "type" => "string" } }, "#/m")).to be_nil
      end
    end
  end

  describe "#named_examples" do
    let(:components) { { "examples" => { "Accepted" => { "value" => { "status" => "pending" } } } } }

    it "returns name => value in document order, resolving $ref'd example components" do
      media = { "examples" => { "accepted" => { "$ref" => "#/components/examples/Accepted" },
                                "rejected" => { "value" => { "status" => "rejected" } } } }

      expect(composer.named_examples(media, "#/m"))
        .to eq({ "accepted" => { "status" => "pending" }, "rejected" => { "status" => "rejected" } })
    end

    it "skips an entry that declares no value and returns {} when there are no examples" do
      aggregate_failures do
        expect(composer.named_examples({ "examples" => { "todo" => { "summary" => "later" } } }, "#/m")).to eq({})
        expect(composer.named_examples({}, "#/m")).to eq({})
        expect(composer.named_examples(nil, "#/m")).to eq({})
      end
    end
  end

  describe "#for_schema" do
    it "composes an object from the property examples, in properties order" do
      schema = { "type" => "object",
                 "properties" => { "payout_id" => { "type" => "string", "example" => "p_42" },
                                   "amount" => { "type" => "integer", "example" => 10_000 } } }

      expect(composer.for_schema(schema, "#/s")).to eq({ "payout_id" => "p_42", "amount" => 10_000 })
    end

    it "skips a property that yields nothing rather than inventing a value from its type" do
      schema = { "type" => "object",
                 "properties" => { "payout_id" => { "type" => "string", "example" => "p_42" },
                                   "comment" => { "type" => "string" },
                                   "created_at" => { "type" => "string", "format" => "date-time" } } }

      expect(composer.for_schema(schema, "#/s")).to eq({ "payout_id" => "p_42" })
    end

    it "reads a scalar from const, from a one-value enum and from default" do
      schema = { "type" => "object",
                 "properties" => { "kind" => { "type" => "string", "const" => "payout" },
                                   "currency" => { "type" => "string", "enum" => %w[RUB] },
                                   "attempts" => { "type" => "integer", "default" => 0 },
                                   "test" => { "type" => "boolean", "default" => false },
                                   "status" => { "type" => "string", "enum" => %w[pending done] } } }

      expect(composer.for_schema(schema, "#/s"))
        .to eq({ "kind" => "payout", "currency" => "RUB", "attempts" => 0, "test" => false })
    end

    it "composes an array into a one-element array" do
      schema = { "type" => "array", "items" => { "type" => "object",
                                                 "properties" => { "sku" => { "type" => "string",
                                                                              "example" => "A-1" } } } }

      expect(composer.for_schema(schema, "#/s")).to eq([{ "sku" => "A-1" }])
    end

    it "composes nested objects and drops the ones with nothing to give" do
      schema = { "type" => "object",
                 "properties" => { "recipient" => { "type" => "object",
                                                    "properties" => { "type" => { "const" => "sbp" } } },
                                   "meta" => { "type" => "object",
                                               "properties" => { "note" => { "type" => "string" } } } } }

      expect(composer.for_schema(schema, "#/s")).to eq({ "recipient" => { "type" => "sbp" } })
    end

    it "returns nil for an object, an array and a scalar with nothing to give" do
      aggregate_failures do
        expect(composer.for_schema({ "type" => "object",
                                     "properties" => { "a" => { "type" => "string" } } }, "#/s")).to be_nil
        expect(composer.for_schema({ "type" => "array", "items" => { "type" => "string" } }, "#/s")).to be_nil
        expect(composer.for_schema({ "type" => "string" }, "#/s")).to be_nil
      end
    end

    it "merges allOf before composing" do
      root = { "components" => { "schemas" => {
        "Base" => { "type" => "object", "properties" => { "id" => { "type" => "string", "example" => "p_1" } } },
        "Payout" => { "allOf" => [{ "$ref" => "#/components/schemas/Base" },
                                  { "type" => "object",
                                    "properties" => { "currency" => { "const" => "RUB" } } }] }
      } } }
      document = ProviderIntegrator::Parser::Document.new(root:, log:, spec_format: "3.0.3")

      expect(described_class.new(document).for_schema({ "$ref" => "#/components/schemas/Payout" }, "#/s"))
        .to eq({ "id" => "p_1", "currency" => "RUB" })
    end

    it "returns nil and reports E005 when the schema cannot be resolved" do
      value = composer.for_schema({ "$ref" => "#/components/schemas/Missing" }, "#/s")

      aggregate_failures do
        expect(value).to be_nil
        expect(log.to_a.map(&:code)).to eq(%w[E005])
        expect(log.to_a.first.message).to eq("Unresolvable $ref #/components/schemas/Missing")
      end
    end
  end
end
