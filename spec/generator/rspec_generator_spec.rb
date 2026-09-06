# frozen_string_literal: true

# The generated RSpec is an output artefact in its own right: it must stay provider-neutral,
# derive its requests from fixtures.json and cover the authentication/body/signature variants.
RSpec.describe ProviderIntegrator::Generator::RspecGenerator do
  def parsed(name)
    ProviderIntegrator::Parser.call!(path: fixture_path("specs", "#{name}.yaml"))
  end

  def generate(spec, slug: spec.provider.slug)
    context = ProviderIntegrator::Generator::Context.new(spec:, provider: slug, output_dir: "output/#{slug}")
    described_class.new(context).call
  end

  it "renders the NovaPay service spec with request, response, signature and condition examples" do
    file = generate(parsed("novapay"))

    aggregate_failures do
      expect(file.kind).to eq("service_spec")
      expect(file.name).to eq("novapay_service_spec.rb")
      expect(file.content).to include("require 'webmock/rspec'", "RSpec.describe Provider::NovapayService do")
      expect(file.content).to include("stub_provider(:post, url, 201, fixture('create_request', 'response_201'))")
      expect(file.content).to include("treats HTTP 409 (idempotent duplicate) as success")
      expect(file.content).to include("headers: { 'Retry-After' => '60' }")
      expect(file.content).to include("OpenSSL::HMAC.hexdigest('SHA256'", "refuses a payload whose signature")
      expect(file.content).to include("refuses an amount below MIN_AMOUNT", "REQUIRED_REQUISITES")
    end
  end

  it "uses a NotImplementedError example when the IR has no webhook" do
    spec = parsed("novapay").with(webhook: nil)

    expect(generate(spec).content)
      .to include("raises NotImplementedError: the spec declares no webhook (W304)")
  end

  it "puts an IR-declared body signature into the payload" do
    spec = parsed("novapay")
    signature = spec.webhook.signature.with(location: "body", name: "signature")
    changed = spec.with(webhook: spec.webhook.with(signature:))

    expect(generate(changed).content).to include("body.merge('signature' => signature_for(body))")
  end

  it "matches an IR-declared query api key on every provider stub" do
    spec = parsed("novapay")
    authentication = spec.authentication.with(location: "query", name: "api_key")

    expect(generate(spec.with(authentication:)).content)
      .to include("let(:auth_query) { { 'api_key' => credentials[:api_key] } }",
                  "stub_request(verb, url).with(query: auth_query)")
  end

  it "decodes an IR-declared form request before checking its fields" do
    spec = parsed("novapay")
    create = spec.operation_for("create_request")
    request_body = create.request_body.with(content_type: "application/x-www-form-urlencoded")
    changed_create = create.with(request_body:)
    operations = spec.operations.map { |operation| operation.equal?(create) ? changed_create : operation }

    expect(generate(spec.with(operations:)).content)
      .to include("require 'uri'", "URI.decode_www_form(requests.last.body).to_h")
  end
end
