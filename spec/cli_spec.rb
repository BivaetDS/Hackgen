# frozen_string_literal: true

require "tmpdir"

# bin/integrate end to end, in process: the reference invocation writes the files, every failure
# has its exit code from docs/PLAN.md 7, errors go to stderr and never carry a backtrace by default.
RSpec.describe ProviderIntegrator::CLI do
  let(:out_dir) { Dir.mktmpdir("cli") }
  let(:spec_path) { repo_path("docs", "provider_api.yaml") }

  after { FileUtils.rm_rf(out_dir) }

  def run_cli(args)
    stdout = StringIO.new
    stderr = StringIO.new
    status = 0
    begin
      $stdout = stdout
      $stderr = stderr
      described_class.start(args)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout = STDOUT
      $stderr = STDERR
    end
    [status, stdout.string, stderr.string]
  end

  def written = Dir.glob("**/*", base: out_dir).select { |entry| File.file?(File.join(out_dir, entry)) }.sort

  it "exits with a non-zero status when a command fails" do
    expect(described_class.exit_on_failure?).to be(true)
  end

  it "prints the version" do
    status, out, = run_cli(%w[version])
    expect([status, out]).to eq([0, "provider-integrator #{ProviderIntegrator::VERSION}\n"])
  end

  it "maps --version to the version command" do
    _, out, = run_cli(%w[--version])
    expect(out).to include(ProviderIntegrator::VERSION)
  end

  it "generates the case study integration into <output>/<provider>/ with the reference transcript" do
    status, out, err = run_cli(["integrate", "--spec", spec_path, "--provider", "novapay", "--output", out_dir])

    aggregate_failures do
      expect(status).to eq(0)
      expect(err).to be_empty
      expect(out).to include("Parsing spec... OpenAPI 3.0.3, NovaPay Payout API 1.0.0", "Found 5 endpoints",
                             "Auth: ApiKeyAuth (header: X-API-Key)",
                             "Webhook signature: X-NovaPay-Signature (HMAC-SHA256)")
      expect(out).to include("Generating service...\nGenerating integration guide...\nGenerating test fixtures...\n",
                             "Validating output... Ruby syntax OK", "Completed with 3 warnings:", "W301",
                             "Output:\n  #{File.join(out_dir, "novapay", "novapay_service.rb")}\n")
      expect(written).to eq(%w[INTEGRATION.md base_contract.rb fixtures.json generation_report.json
                               novapay_service.rb novapay_service_spec.rb].map { |name| "novapay/#{name}" })
      expect(ProviderIntegrator::Files.read(File.join(out_dir, "novapay", "novapay_service.rb")))
        .to eq(ProviderIntegrator::Files.read(repo_path("spec", "golden", "novapay", "novapay_service.rb")))
    end
  end

  it "treats integrate as the default command so the TZ invocation shape works" do
    status, out, = run_cli(["--spec", spec_path, "--provider", "novapay", "--lang", "ruby", "--output", out_dir])
    expect([status, out]).to match([0, a_string_including("Found 5 endpoints")])
  end

  it "prints the IR alone on stdout with --analyze-only and the analysis on stderr" do
    status, out, err = run_cli(["integrate", "--spec", spec_path, "--analyze-only", "--output", out_dir])

    aggregate_failures do
      expect(status).to eq(0)
      expect(ProviderIntegrator::JsonCanon.parse(out)["provider"]["slug"]).to eq("novapay")
      expect(err).to include("Found 5 endpoints", "Completed with 3 warnings:")
      expect(written).to be_empty
    end
  end

  it "reports an unusable spec on stderr with its event code and exit status 3" do
    status, out, err = run_cli(["integrate", "--spec", fixture_path("specs", "invalid_bad_ref.yaml"),
                                "--output", out_dir])

    aggregate_failures do
      expect(status).to eq(3)
      expect(err).to eq("The spec cannot be used:\n  E005 Unresolvable $ref #/components/schemas/PayeeAccount\n")
      expect(out).to be_empty
      expect(written).to be_empty
    end
  end

  it "turns warnings into exit 4 under --strict but still writes the files" do
    status, = run_cli(["integrate", "--spec", spec_path, "--strict", "--output", out_dir])

    expect([status, written.size]).to eq([4, 6])
  end

  it "runs the generated spec under --run-spec and prints its summary" do
    run_result = ProviderIntegrator::Models::SpecRun.new(
      examples: 20, failures: 0, output: "20 examples, 0 failures\n", exit_status: 0, error: nil
    )
    allow(ProviderIntegrator::SpecRunner).to receive(:call).and_return(run_result)

    status, out, err = run_cli(["--spec", spec_path, "--run-spec", "--output", out_dir])

    aggregate_failures do
      expect(status).to eq(0)
      expect(out).to include("Running generated spec... RSpec 20 examples, 0 failures\n")
      expect(err).to be_empty
      expect(written.size).to eq(6)
    end
  end

  it "exits 5, reports RSpec output and keeps the files when --run-spec fails" do
    run_result = ProviderIntegrator::Models::SpecRun.new(
      examples: 20, failures: 1, output: "failure details\n20 examples, 1 failure\n", exit_status: 1, error: nil
    )
    allow(ProviderIntegrator::SpecRunner).to receive(:call).and_return(run_result)

    status, out, err = run_cli(["--spec", spec_path, "--run-spec", "--output", out_dir])

    aggregate_failures do
      expect(status).to eq(5)
      expect(err).to include("Running generated spec... FAILED", "failure details",
                             "Generated spec failed; files were kept in #{File.join(out_dir, "novapay")}.")
      expect(out).to include("Output:", "novapay_service_spec.rb")
      expect(written.size).to eq(6)
    end
  end

  it "rejects a --provider that is not a safe slug with exit 2" do
    status, _, err = run_cli(["integrate", "--spec", spec_path, "--provider", "../evil"])
    expect([status, err]).to match([2, a_string_including("invalid --provider")])
  end

  it "rejects a --lang other than ruby with exit 2" do
    status, _, err = run_cli(["integrate", "--spec", spec_path, "--lang", "go"])
    expect([status, err]).to match([2, a_string_including("unsupported --lang \"go\"")])
  end

  it "exits 2 on Thor's own argument errors (missing --spec)" do
    status, _, err = run_cli(%w[integrate])
    expect([status, err]).to match([2, a_string_including("--spec")])
  end

  it "exits 5 and writes nothing when the generated output fails validation" do
    failed = ProviderIntegrator::Models::GenerationResult.new(
      value: [], validation: { "ok" => false, "checks" => [] },
      events: [ProviderIntegrator::Events.build("E201", file: "novapay_service.rb", reason: "ERB tags remain")]
    )
    allow(ProviderIntegrator::Generator).to receive(:call).and_return(failed)

    status, _, err = run_cli(["integrate", "--spec", spec_path, "--output", out_dir])

    aggregate_failures do
      expect(status).to eq(5)
      expect(err).to include("Generation failed; nothing was written:", "E201 Generated novapay_service.rb is invalid")
      expect(written).to be_empty
    end
  end

  it "exits 6 when the output cannot be written" do
    blocker = File.join(out_dir, "blocker")
    File.write(blocker, "")

    status, _, err = run_cli(["integrate", "--spec", spec_path, "--output", blocker])

    expect([status, err])
      .to match([6, a_string_starting_with("Cannot write output: cannot write #{blocker}/novapay: ")])
  end

  it "exits 1 on an internal error without a backtrace" do
    allow(ProviderIntegrator::Parser).to receive(:call).and_raise(RuntimeError, "boom")

    status, _, err = run_cli(["integrate", "--spec", spec_path, "--output", out_dir])

    expect([status, err])
      .to eq([1, "Internal error: RuntimeError: boom\nRun again with --verbose to see the backtrace.\n"])
  end

  it "prints the backtrace of an internal error under --verbose" do
    allow(ProviderIntegrator::Parser).to receive(:call).and_raise(RuntimeError, "boom")

    status, _, err = run_cli(["integrate", "--spec", spec_path, "--output", out_dir, "--verbose"])

    expect([status, err]).to match([1, a_string_including("Internal error: RuntimeError: boom\n    ", "cli_spec.rb")])
  end
end
