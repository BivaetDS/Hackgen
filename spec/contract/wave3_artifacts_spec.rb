# frozen_string_literal: true

RSpec.describe "Wave 3 artifacts" do
  let(:root) { File.expand_path("../..", __dir__) }

  it "documents every CLI flag and the clean-machine workflow" do
    readme = File.read(File.join(root, "README.md"))
    flags = %w[--spec --provider --output --overrides --analyze-only --strict --run-spec --verbose --lang --version]

    expect(flags).to all(satisfy { |flag| readme.include?("`#{flag}") })
    expect(readme).to include("bundle install", "bundle exec rake check", "Troubleshooting")
  end

  it "ships a schema-valid overrides example" do
    raw = Psych.safe_load_file(File.join(root, "examples/overrides.example.yml"), permitted_classes: [], aliases: false)

    expect(ProviderIntegrator::Schemas.errors(:overrides, raw)).to be_empty
  end

  it "runs the container as a non-root user with the CLI as its entry point" do
    dockerfile = File.read(File.join(root, "Dockerfile"))
    compose = YAML.safe_load_file(File.join(root, "compose.yaml"), aliases: false)

    expect(dockerfile).to include("FROM ruby:3.3-slim", "USER integrator")
    expect(dockerfile).to include('ENTRYPOINT ["bundle", "exec", "ruby", "bin/integrate"]')
    expect(compose.dig("services", "integrator", "volumes")).to include(
      "./specs:/workspace/specs:ro", "./output:/workspace/output"
    )
  end
end
