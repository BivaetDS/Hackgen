# frozen_string_literal: true

# provider_spec.schema.json is the machine-readable half of docs/IR_CONTRACT.md: the hand-written
# NovaPay IR, every model example and the models themselves must agree with it.
RSpec.describe "provider_spec.schema.json" do
  let(:schemas) { ProviderIntegrator::Schemas }
  let(:models) { ProviderIntegrator::Models }
  let(:fixture_json) { read_fixture("normalized_novapay.json") }
  let(:fixture) { ProviderIntegrator::JsonCanon.parse(fixture_json) }

  def deep_copy(value)
    ProviderIntegrator::JsonCanon.parse(JSON.generate(value))
  end

  describe "spec/fixtures/normalized_novapay.json" do
    it "validates against the schema" do
      expect(schemas.errors(:provider_spec, fixture)).to eq([])
    end

    it "loads through ProviderSpec.from_json and re-serializes byte-identically" do
      spec = models::ProviderSpec.from_json(fixture_json)

      aggregate_failures do
        expect(spec.ir_version).to eq(1)
        expect(spec.to_canonical_json).to eq(fixture_json)
        expect(spec.to_canonical_json.encoding).to eq(Encoding::UTF_8)
      end
    end

    it "is already in canonical form (sorted keys, trailing newline, LF only)" do
      aggregate_failures do
        expect(ProviderIntegrator::JsonCanon.generate(fixture)).to eq(fixture_json)
        expect(fixture_json).not_to include("\r")
      end
    end
  end

  describe "model examples" do
    ModelExamples.all.each_key do |model_name|
      it "accepts the #{model_name} example under $defs/#{model_name}" do
        example = models.const_get(model_name).from_h(ModelExamples.all[model_name]).to_h
        subschema = schemas.schema(:provider_spec).ref("#/$defs/#{model_name}")

        expect(subschema.validate(example).map { |error| error["error"] }).to eq([])
      end
    end
  end

  describe "$defs vs models" do
    let(:defs) { schemas.load(:provider_spec).fetch("$defs") }

    it "has one strict object definition per serializable model, requiring exactly its members" do
      ModelExamples.all.each_key do |model_name|
        definition = defs.fetch(model_name) { raise "no $defs/#{model_name}" }
        members = models.const_get(model_name).members.map(&:to_s)

        aggregate_failures(model_name) do
          expect(definition["additionalProperties"]).to be(false)
          expect(definition["required"]).to match_array(members)
          expect(definition["properties"].keys).to match_array(members)
        end
      end
    end
  end

  describe "strictness" do
    it "rejects an unknown member, a wrong kind and an out-of-range confidence" do
      extra = deep_copy(fixture).merge("extra" => 1)
      wrong_kind = deep_copy(fixture).tap { |ir| ir["operations"][0]["kind"] = "payout" }
      overconfident = deep_copy(fixture).tap { |ir| ir["operations"][0]["confidence"] = 1.5 }

      aggregate_failures do
        expect(schemas.errors(:provider_spec, extra)).not_to be_empty
        expect(schemas.errors(:provider_spec, wrong_kind)).not_to be_empty
        expect(schemas.errors(:provider_spec, overconfident)).not_to be_empty
      end
    end

    it "rejects a missing member, a String http status and a non-pointer location" do
      missing = deep_copy(fixture).tap { |ir| ir["operations"][0].delete("confidence") }
      string_http = deep_copy(fixture).tap { |ir| ir["operations"][0]["responses"][0]["http"] = "201" }
      bad_location = deep_copy(fixture).tap { |ir| ir["events"][0]["location"] = "paths/x" }

      aggregate_failures do
        expect(schemas.errors(:provider_spec, missing)).not_to be_empty
        expect(schemas.errors(:provider_spec, string_http)).not_to be_empty
        expect(schemas.errors(:provider_spec, bad_location)).not_to be_empty
      end
    end

    it "keeps the ir_version pinned to 1" do
      expect(schemas.valid?(:provider_spec, deep_copy(fixture).merge("ir_version" => 2))).to be(false)
    end
  end
end
