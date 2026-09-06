# frozen_string_literal: true

# Generator runs for specs. Generation is pure (same IR -> same files), so the NovaPay run is
# memoized per process: RuboCop formatting is the slow part and every spec would repeat it.
module GenerationHelpers
  module_function

  # The hand-written NovaPay IR as a ProviderSpec (no parser involved).
  def novapay_spec
    @novapay_spec ||= ProviderIntegrator::Models::ProviderSpec.from_json(
      ProviderIntegrator::Files.read(File.expand_path("../fixtures/normalized_novapay.json", __dir__))
    )
  end

  # Generator.call on the NovaPay IR, once per process.
  def novapay_generation
    @novapay_generation ||= ProviderIntegrator::Generator.call(spec: novapay_spec, output_dir: "output/novapay")
  end

  # Content of the generated NovaPay file of +kind+ (service, base_contract, documentation, fixtures, report).
  def novapay_file(kind)
    novapay_generation.file(kind).content
  end

  # Generator.call for a fixture spec parsed from spec/fixtures/specs/<name>.yaml.
  def generate_fixture(name, **)
    spec = ProviderIntegrator::Parser.call!(path: File.expand_path("../fixtures/specs/#{name}.yaml", __dir__))
    ProviderIntegrator::Generator.call(spec:, output_dir: "output/#{name}", **)
  end
end
