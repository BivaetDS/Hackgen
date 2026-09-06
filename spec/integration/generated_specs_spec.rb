# frozen_string_literal: true

require "open3"
require "tmpdir"

# The generated RSpec is executable evidence, not documentation: each regression provider gets
# its six files in an isolated directory and its spec runs against HttpClient through WebMock.
generated_spec_names = %w[novapay bearerpay rublepay numstatus cardpay legacy_swagger2]

RSpec.describe "generated service specs", type: :integration do
  def run_generated_spec(name)
    result = GenerationHelpers.generate_fixture(name)
    Dir.mktmpdir("generated-#{name}") do |dir|
      result.files.each { |file| ProviderIntegrator::Files.write(File.join(dir, file.name), file.content) }
      spec_file = result.file(:service_spec).name
      rspec_bin = Gem.bin_path("rspec-core", "rspec")
      output, process = Open3.capture2e(RbConfig.ruby, rspec_bin, spec_file, "--format", "progress", "--no-color",
                                        chdir: dir)
      return [result, output, process]
    end
  end

  generated_spec_names.each do |name|
    it "passes for #{name}" do
      result, output, process = run_generated_spec(name)

      aggregate_failures do
        expect(result).to be_success
        expect(process.exitstatus).to eq(0), output
        expect(output).to match(/\d+ examples?, 0 failures/)
      end
    end
  end
end
