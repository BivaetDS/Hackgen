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

  it "refuses to integrate until wave 1 with exit status 1" do
    status, _, err = run_cli(%w[integrate --spec docs/provider_api.yaml --provider novapay])
    expect([status, err.strip]).to eq([1, "integrate is not implemented until wave 1"])
  end

  it "treats integrate as the default command so the TZ invocation shape works" do
    status, _, err = run_cli(%w[--spec docs/provider_api.yaml --provider novapay --lang ruby])
    expect([status, err]).to eq([1, "integrate is not implemented until wave 1\n"])
  end
end
