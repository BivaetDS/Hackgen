# frozen_string_literal: true

RSpec.describe ProviderIntegrator::CLI do
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

  it "analyses the case study spec and reports what it recognised" do
    status, out, = run_cli(%w[integrate --spec docs/provider_api.yaml --provider novapay])

    aggregate_failures do
      expect(status).to eq(0)
      expect(out).to include("OpenAPI 3.0.3, NovaPay Payout API 1.0.0", "Found 5 endpoints",
                             "create_request", "Auth: ApiKeyAuth", "X-NovaPay-Signature", "W301")
    end
  end

  it "prints the IR as canonical JSON with --analyze-only" do
    status, out, = run_cli(%w[integrate --spec docs/provider_api.yaml --analyze-only])
    json = out[out.index(/^\{/)..]

    aggregate_failures do
      expect(status).to eq(0)
      expect(ProviderIntegrator::JsonCanon.parse(json)["provider"]["slug"]).to eq("novapay")
    end
  end

  it "reports an unusable spec with its event code and exit status 3" do
    status, out, = run_cli(%w[integrate --spec spec/fixtures/specs/invalid_bad_ref.yaml])

    expect([status, out]).to match([3, a_string_including("E005")])
  end

  it "turns warnings into a failure under --strict (exit 4)" do
    status, = run_cli(%w[integrate --spec docs/provider_api.yaml --strict])
    expect(status).to eq(4)
  end

  it "rejects a --provider that is not a safe slug" do
    status, _, err = run_cli(%w[integrate --spec docs/provider_api.yaml --provider ../evil])
    expect([status, err]).to match([1, a_string_including("invalid --provider")])
  end

  it "treats integrate as the default command so the TZ invocation shape works" do
    status, out, = run_cli(%w[--spec docs/provider_api.yaml --provider novapay --lang ruby])
    expect([status, out]).to match([0, a_string_including("Found 5 endpoints")])
  end
end
