# frozen_string_literal: true

require "open3"
require "tmpdir"

# The acceptance test of wave 1 (docs/PLAN.md 10): the executable itself, started from an empty
# directory as a user would, turns the case study spec into the files on disk in one pass. Runs
# once in a child process (the rest of the CLI behaviour is covered in process by spec/cli_spec.rb).
RSpec.describe "bin/integrate", type: :integration do
  let(:executable) { repo_path("bin", "integrate") }
  let(:spec_path) { repo_path("docs", "provider_api.yaml") }
  let(:golden_dir) { repo_path("spec", "golden", "novapay") }
  let(:expected_files) { %w[novapay_service.rb INTEGRATION.md fixtures.json base_contract.rb generation_report.json] }

  def integrate(workdir, *args)
    Open3.capture3(RbConfig.ruby, executable, "--spec", spec_path, "--provider", "novapay", "--output", "out", *args,
                   chdir: workdir)
  end

  it "generates the NovaPay integration from a clean directory with the reference transcript" do
    Dir.mktmpdir("integrate") do |workdir|
      out, err, status = integrate(workdir)
      written = File.join(workdir, "out", "novapay")

      aggregate_failures do
        expect(status.exitstatus).to eq(0), "stderr: #{err}"
        expect(err).to be_empty
        expect(out).to include("Parsing spec... OpenAPI 3.0.3, NovaPay Payout API 1.0.0\n", "Found 5 endpoints",
                               "  create_request   -> POST /payouts", "Auth: ApiKeyAuth (header: X-API-Key)\n",
                               "Webhook signature: X-NovaPay-Signature (HMAC-SHA256)")
        expect(out).to include("Generating service...\n", "Generating integration guide...\n",
                               "Generating test fixtures...\n", "Validating output... Ruby syntax OK",
                               "Completed with 3 warnings:\n  W301", "Requires confirmation: 7 items",
                               "Output:\n  out/novapay/novapay_service.rb\n  out/novapay/INTEGRATION.md\n")
        expect(Dir.children(written).sort).to eq(expected_files.sort)
        expected_files.each do |name|
          expect(ProviderIntegrator::Files.read(File.join(written, name)))
            .to eq(ProviderIntegrator::Files.read(File.join(golden_dir, name))), "#{name} differs from the golden copy"
        end
      end
    end
  end
end
