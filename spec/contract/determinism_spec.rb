# frozen_string_literal: true

# Wave 2 freezes both sides of the pipeline: parsing the same bytes yields canonical-identical IR,
# and generating from that IR yields the same names and SHA-256 digests for every regression spec.
determinism_names = %w[novapay bearerpay rublepay numstatus cardpay legacy_swagger2]

RSpec.describe "pipeline determinism" do
  determinism_names.each do |name|
    it "is byte-stable for #{name}" do
      path = fixture_path("specs", "#{name}.yaml")
      first_spec = ProviderIntegrator::Parser.call!(path:)
      second_spec = ProviderIntegrator::Parser.call!(path:)
      first = ProviderIntegrator::Generator.call(spec: first_spec, output_dir: "output/#{name}")
      ProviderIntegrator::Generator::RubyFormatter.cache.clear if name == "novapay"
      second = ProviderIntegrator::Generator.call(spec: second_spec, output_dir: "output/#{name}")

      aggregate_failures do
        expect(ProviderIntegrator::JsonCanon.generate(second_spec.to_h))
          .to eq(ProviderIntegrator::JsonCanon.generate(first_spec.to_h))
        expect(second.files.map { |file| [file.name, file.sha256] })
          .to eq(first.files.map { |file| [file.name, file.sha256] })
      end
    end
  end
end
