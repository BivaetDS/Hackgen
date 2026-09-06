# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Models::Result do
  let(:events) { ProviderIntegrator::Events }
  let(:error) { events.build("E003") }
  let(:warning) { events.build("W104") }
  let(:info) { events.build("W103") }

  it "succeeds when no error-level event is present" do
    result = described_class.new(value: 1, events: [warning, info])

    aggregate_failures do
      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.errors).to be_empty
      expect(result.warnings).to eq([warning])
      expect(result.infos).to eq([info])
    end
  end

  it "fails on any error-level event" do
    result = described_class.new(value: nil, events: [info, error])

    expect(result).to be_failure
    expect(result.errors).to eq([error])
  end

  describe ProviderIntegrator::Models::ParseResult do
    it "exposes the ProviderSpec as #spec (PLAN 3.1 usage)" do
      spec = ProviderIntegrator::Models::ProviderSpec.from_h(ModelExamples.all["ProviderSpec"])
      result = described_class.new(value: spec, events: spec.events)

      expect(result.spec).to be(spec)
      expect(result).to be_success
    end
  end

  describe ProviderIntegrator::Models::GenerationResult do
    let(:file) do
      ProviderIntegrator::Models::GeneratedFile.build(kind: :service, name: "novapay_service.rb",
                                                      path: "output/novapay_service.rb", content: "# service\n")
    end

    it "exposes the generated files as #files and finds one by kind (PLAN 3.1 usage)" do
      result = described_class.new(value: [file], events: [warning], validation: { "ok" => true })

      aggregate_failures do
        expect(result.files).to eq([file])
        expect(result.file(:service)).to be(file)
        expect(result.file(:fixtures)).to be_nil
        expect(result).to be_success
        expect(result.validation).to eq("ok" => true)
      end
    end

    it "fails on an E201 from the output validator" do
      result = described_class.new(value: [file], events: [events.build("E201", file: "x.rb", reason: "syntax")],
                                   validation: { "ok" => false })

      expect(result).to be_failure
    end
  end
end
