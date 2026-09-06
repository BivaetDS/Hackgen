# frozen_string_literal: true

# SpecRunner owns the subprocess boundary: argv execution, RSpec summary parsing and setup errors.
RSpec.describe ProviderIntegrator::SpecRunner do
  let(:process) { instance_double(Process::Status, exitstatus: 0) }

  before do
    allow(Gem).to receive(:bin_path).with("rspec-core", "rspec").and_return("/tools/rspec")
  end

  it "returns the example and failure counts from RSpec output" do
    output = "....................\n\n20 examples, 0 failures\n"
    allow(Open3).to receive(:capture2e).and_return([output, process])

    run = described_class.call(spec_path: "/tmp/out/acme_service_spec.rb", chdir: "/tmp/out")

    aggregate_failures do
      expect(run).to be_ok
      expect(run.to_h).to include(examples: 20, failures: 0, output:, exit_status: 0, error: nil)
      expect(Open3).to have_received(:capture2e)
        .with(RbConfig.ruby, "/tools/rspec", "acme_service_spec.rb", "--format", "progress", "--no-color",
              chdir: "/tmp/out")
    end
  end

  it "keeps failed-example output for the reporter" do
    failed_process = instance_double(Process::Status, exitstatus: 1)
    output = "F\n\n1 example, 1 failure\n"
    allow(Open3).to receive(:capture2e).and_return([output, failed_process])

    run = described_class.call(spec_path: "acme_service_spec.rb", chdir: "/tmp/out")

    expect([run.ok?, run.examples, run.failures, run.output]).to eq([false, 1, 1, output])
  end

  it "turns an unavailable RSpec executable into a readable failed run" do
    allow(Gem).to receive(:bin_path).and_raise(Gem::GemNotFoundException, "missing rspec")

    run = described_class.call(spec_path: "acme_service_spec.rb", chdir: "/tmp/out")

    expect([run.ok?, run.error]).to match([false, a_string_starting_with("RSpec is unavailable: missing rspec")])
  end
end
