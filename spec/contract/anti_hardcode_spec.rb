# frozen_string_literal: true

# Nothing provider-specific lives in lib/: the knowledge about providers is in the dictionaries
# and in the spec being analysed (docs/PLAN.md 9, CLAUDE.md invariants).
RSpec.describe "anti-hardcode" do
  let(:lib_files) { Dir[repo_path("lib", "**", "*")].select { |path| File.file?(path) } }
  let(:templates) { Dir[repo_path("lib", "provider_integrator", "templates", "*")] }

  it "mentions NovaPay nowhere under lib/ (grep -ri novapay lib/ is empty)" do
    offenders = lib_files.select { |path| ProviderIntegrator::Files.read(path).match?(/novapay/i) }

    expect(offenders).to be_empty
  end

  it "keeps provider values out of the templates" do
    tokens = %w[X-API-Key Idempotency-Key X-NovaPay np_7f RUB_SBP_WITHDRAW payouts]
    offenders = templates.flat_map do |path|
      content = ProviderIntegrator::Files.read(path)
      tokens.select { |token| content.include?(token) }.map { |token| "#{File.basename(path)}: #{token}" }
    end

    expect(offenders).to be_empty
  end
end
