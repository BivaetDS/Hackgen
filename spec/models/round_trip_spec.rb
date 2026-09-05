# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Models do
  ModelExamples.all.each do |model_name, example|
    describe model_name do
      let(:model) { described_class.const_get(model_name) }
      let(:instance) { model.from_h(example) }

      it "round-trips JSON -> from_h -> to_h -> JSON byte-identically" do
        json = instance.to_canonical_json
        reparsed = model.from_json(json)

        aggregate_failures do
          expect(reparsed.to_canonical_json).to eq(json)
          expect(reparsed).to eq(instance)
          expect(model.from_h(instance.to_h)).to eq(instance)
        end
      end

      it "exposes every member in to_h with String keys" do
        expect(instance.to_h.keys).to eq(model.members.map(&:to_s))
      end
    end
  end

  it "covers every serializable model" do
    serializable = described_class.constants.select do |name|
      klass = described_class.const_get(name)
      klass.is_a?(Class) && klass.include?(ProviderIntegrator::Models::Base)
    end

    expect(serializable.map(&:to_s)).to match_array(ModelExamples.all.keys)
  end
end
