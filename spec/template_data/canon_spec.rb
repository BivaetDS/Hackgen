# frozen_string_literal: true

RSpec.describe ProviderIntegrator::TemplateData::Canon do
  subject(:canon) { described_class.new }

  it "renders failure calls and their parts from canonical_contract.yml" do
    aggregate_failures do
      expect(canon.failure_for_error("rate_limit")).to eq("failure(:too_many_requests, 'provider.rate_limit')")
      expect(canon.failure_for_error("rate_limit", "**details"))
        .to eq("failure(:too_many_requests, 'provider.rate_limit', **details)")
      expect(canon.failure_parts("rate_limit")).to eq([":too_many_requests", "'provider.rate_limit'"])
      expect(canon.failure_for_service_code("unknown_event")).to eq("failure(:unprocessable_entity, 'unknown_event')")
      expect(canon.service_failure_parts("invalid_signature")).to eq([":unauthorized", "'invalid_signature'"])
    end
  end

  it "refuses codes the canon does not know" do
    aggregate_failures do
      expect { canon.failure_parts("teapot") }.to raise_error(ProviderIntegrator::GenerationError, /teapot/)
      expect { canon.service_failure_parts("teapot") }.to raise_error(ProviderIntegrator::GenerationError, /teapot/)
    end
  end

  it "exposes the platform names the templates need without literals" do
    aggregate_failures do
      expect([canon.namespace, canon.base_service]).to eq(%w[Provider BaseService])
      expect(canon.credential("api_key")).to eq("credentials[:api_key]")
      expect(canon.credential_keys("http_basic")).to eq(%w[login password])
      expect(canon.requisite_access("'sbp'", "'phone'")).to eq("operation.payout_requisite.dig('sbp', 'phone')")
      expect(canon.signature("create_request", default_request_method: "'sbp'"))
        .to eq("create_request(operation, request_method = 'sbp')")
    end
  end
end
