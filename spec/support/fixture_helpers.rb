# frozen_string_literal: true

# Paths and readers for spec/fixtures. Reads are binary so byte-identity assertions hold on Windows.
module FixtureHelpers
  FIXTURES_DIR = File.expand_path("../fixtures", __dir__)
  REPO_ROOT = File.expand_path("../..", __dir__)

  def fixture_path(*parts)
    File.join(FIXTURES_DIR, *parts)
  end

  def repo_path(*parts)
    File.join(REPO_ROOT, *parts)
  end

  def read_fixture(*parts)
    ProviderIntegrator::Files.read(fixture_path(*parts))
  end

  # The hand-written expected IR for NovaPay as a String-keyed Hash.
  def novapay_ir_hash
    ProviderIntegrator::JsonCanon.parse(read_fixture("normalized_novapay.json"))
  end

  # The NovaPay OpenAPI document as a Hash (what the parser hands to openapi3_parser).
  def novapay_openapi_hash
    Psych.safe_load_file(fixture_path("specs", "novapay.yaml"), permitted_classes: [Symbol])
  end
end
