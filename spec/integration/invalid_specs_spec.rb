# frozen_string_literal: true

require "tmpdir"

# Every unusable fixture is a CLI contract: one stable E-code, exit 3, no backtrace and no files.
invalid_cases = {
  "invalid_broken_yaml" => "E001",
  "invalid_no_paths" => "E003",
  "invalid_bad_ref" => "E005",
  "invalid_no_create" => "E101"
}

RSpec.describe "invalid spec diagnostics", type: :integration do
  def run_cli(args)
    stdout = StringIO.new
    stderr = StringIO.new
    exit_code = 0
    begin
      $stdout = stdout
      $stderr = stderr
      ProviderIntegrator::CLI.start(args)
    rescue SystemExit => e
      exit_code = e.status
    ensure
      $stdout = STDOUT
      $stderr = STDERR
    end
    [exit_code, stdout.string, stderr.string]
  end

  invalid_cases.each do |name, code|
    it "reports #{name} as #{code}" do
      Dir.mktmpdir("invalid-spec") do |dir|
        exit_code, out, err = run_cli(["--spec", fixture_path("specs", "#{name}.yaml"), "--output", dir])

        aggregate_failures do
          expect(exit_code).to eq(3)
          expect(out).to be_empty
          expect(err).to start_with("The spec cannot be used:\n  #{code} ")
          expect(err.lines.size).to eq(2)
          expect(err).not_to match(/\.rb:\d+/)
          expect(Dir.children(dir)).to be_empty
        end
      end
    end
  end
end
