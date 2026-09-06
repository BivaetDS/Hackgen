# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::SchemaFacts do
  let(:facts) { described_class }

  describe ".type" do
    it "reads a plain 3.0 type" do
      aggregate_failures do
        expect(facts.type({ "type" => "string" })).to eq("string")
        expect(facts.type({ "type" => "object" })).to eq("object")
        expect(facts.type({})).to be_nil
      end
    end

    it "takes the first non-null entry of a 3.1 type list" do
      aggregate_failures do
        expect(facts.type({ "type" => %w[string null] })).to eq("string")
        expect(facts.type({ "type" => %w[null integer] })).to eq("integer")
      end
    end

    it "returns nil when the only declared type is null" do
      aggregate_failures do
        expect(facts.type({ "type" => "null" })).to be_nil
        expect(facts.type({ "type" => %w[null] })).to be_nil
      end
    end
  end

  describe ".nullable?" do
    it "reads 'nullable: true' the 3.0 way" do
      aggregate_failures do
        expect(facts.nullable?({ "type" => "string", "nullable" => true })).to be(true)
        expect(facts.nullable?({ "type" => "string", "nullable" => false })).to be(false)
        expect(facts.nullable?({ "type" => "string" })).to be(false)
      end
    end

    it "reads a null member of a 3.1 type list" do
      aggregate_failures do
        expect(facts.nullable?({ "type" => %w[string null] })).to be(true)
        expect(facts.nullable?({ "type" => %w[string integer] })).to be(false)
        expect(facts.nullable?({})).to be(false)
      end
    end
  end

  describe ".enum" do
    it "returns the values as declared" do
      expect(facts.enum({ "enum" => %w[pending done] })).to eq(%w[pending done])
    end

    it "returns nil for a missing, empty or non-array enum" do
      aggregate_failures do
        expect(facts.enum({})).to be_nil
        expect(facts.enum({ "enum" => [] })).to be_nil
        expect(facts.enum({ "enum" => "pending" })).to be_nil
      end
    end
  end

  describe ".constant" do
    it "reads 'const'" do
      aggregate_failures do
        expect(facts.constant({ "const" => "RUB" })).to eq("RUB")
        expect(facts.constant({ "const" => false })).to be(false)
      end
    end

    it "reads an enum of exactly one value" do
      expect(facts.constant({ "enum" => %w[RUB] })).to eq("RUB")
    end

    it "returns nil when the value is not pinned down" do
      aggregate_failures do
        expect(facts.constant({ "enum" => %w[RUB USD] })).to be_nil
        expect(facts.constant({ "type" => "string" })).to be_nil
      end
    end
  end

  describe ".example" do
    it "reads the 3.0 'example' and prefers it over a 3.1 'examples' list" do
      aggregate_failures do
        expect(facts.example({ "example" => "p_1" })).to eq("p_1")
        expect(facts.example({ "example" => "p_1", "examples" => %w[p_2] })).to eq("p_1")
      end
    end

    it "reads the first entry of a 3.1 'examples' array" do
      expect(facts.example({ "examples" => %w[p_1 p_2] })).to eq("p_1")
    end

    it "keeps a false or a 0 example: 2.12 counts them as values, not as the absence of one" do
      aggregate_failures do
        expect(facts.example({ "example" => false })).to be(false)
        expect(facts.example({ "example" => 0 })).to eq(0)
      end
    end

    it "returns nil for an empty list, a media-style examples Hash and no example at all" do
      aggregate_failures do
        expect(facts.example({ "examples" => [] })).to be_nil
        expect(facts.example({ "examples" => { "ok" => { "value" => 1 } } })).to be_nil
        expect(facts.example({ "type" => "string" })).to be_nil
      end
    end
  end

  describe ".description" do
    it "strips the declared text" do
      expect(facts.description({ "description" => "  Amount in kopecks \n" })).to eq("Amount in kopecks")
    end

    it "returns nil for blank, missing and non-String descriptions" do
      aggregate_failures do
        expect(facts.description({ "description" => "  \n " })).to be_nil
        expect(facts.description({})).to be_nil
        expect(facts.description({ "description" => 42 })).to be_nil
      end
    end
  end

  describe ".object?" do
    it "recognises an explicit type and a properties map" do
      aggregate_failures do
        expect(facts.object?({ "type" => "object" })).to be(true)
        expect(facts.object?({ "properties" => { "id" => { "type" => "string" } } })).to be(true)
      end
    end

    it "recognises the composition keywords, which describe an object without saying so" do
      aggregate_failures do
        expect(facts.object?({ "oneOf" => [{ "type" => "object" }] })).to be(true)
        expect(facts.object?({ "anyOf" => [{ "type" => "object" }] })).to be(true)
        expect(facts.object?({ "allOf" => [{ "type" => "object" }] })).to be(true)
      end
    end

    it "reads the object out of a 3.1 type list" do
      expect(facts.object?({ "type" => %w[object null] })).to be(true)
    end

    it "is false for a scalar and for a composition keyword that is not a list" do
      aggregate_failures do
        expect(facts.object?({ "type" => "string" })).to be(false)
        expect(facts.object?({ "oneOf" => "nonsense" })).to be(false)
      end
    end
  end

  describe ".array?" do
    it "recognises an explicit type and a declared items schema" do
      aggregate_failures do
        expect(facts.array?({ "type" => "array" })).to be(true)
        expect(facts.array?({ "items" => { "type" => "string" } })).to be(true)
      end
    end

    it "reads the array out of a 3.1 type list" do
      expect(facts.array?({ "type" => %w[array null] })).to be(true)
    end

    it "is false for objects and scalars" do
      aggregate_failures do
        expect(facts.array?({ "type" => "object" })).to be(false)
        expect(facts.array?({ "type" => "string" })).to be(false)
      end
    end
  end
end
