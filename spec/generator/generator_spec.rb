# frozen_string_literal: true

require "open3"
require "tmpdir"

# The acceptance test of wave 1 part B (docs/PLAN.md 10): Generator.call on the hand-written
# NovaPay IR (no parser involved) yields the three files of the case study plus the report and the
# contract stub, shaped like the reference in docs/TZ.md, validated, and byte-identical across runs.
RSpec.describe ProviderIntegrator::Generator do
  let(:result) { GenerationHelpers.novapay_generation }
  let(:service) { GenerationHelpers.novapay_file(:service) }

  describe ".call on spec/fixtures/normalized_novapay.json" do
    it "succeeds with the six output files in output order" do
      aggregate_failures do
        expect(result).to be_success
        expect(result.files.map(&:name))
          .to eq(%w[novapay_service.rb base_contract.rb INTEGRATION.md fixtures.json novapay_service_spec.rb
                    generation_report.json])
        expect(result.files.map(&:kind)).to eq(%w[service base_contract documentation fixtures service_spec report])
        expect(result.files.map(&:path)).to all(start_with("output/novapay/"))
      end
    end

    it "passes every output validator check" do
      failed = result.validation["checks"].reject { |check| check["ok"] }

      aggregate_failures do
        expect(result.validation["ok"]).to be(true)
        expect(failed).to be_empty
        expect(result.validation["checks"].map { |check| check["name"] })
          .to include("novapay_service.rb: rubocop", "fixtures.json: schemas", "INTEGRATION.md: sections")
      end
    end

    it "is deterministic: a second run yields the same SHA-256 for every file" do
      again = described_class.call(spec: GenerationHelpers.novapay_spec, output_dir: "output/novapay")

      expect(again.files.map(&:sha256)).to eq(result.files.map(&:sha256))
    end

    it "names the class, the file and the ENV prefix after the --provider slug when one is given" do
      custom = described_class.call(spec: GenerationHelpers.novapay_spec, provider: "acme_pay", output_dir: "out")
      source = custom.file(:service).content

      aggregate_failures do
        expect(custom.file(:service).name).to eq("acme_pay_service.rb")
        expect(source).to include("class AcmePayService < BaseService", "ENV.fetch('ACME_PAY_BASE_URL'")
      end
    end

    it "rejects a provider slug that is not a safe identifier" do
      expect { described_class.call(spec: GenerationHelpers.novapay_spec, provider: "../x") }
        .to raise_error(ArgumentError, /not a safe identifier/)
    end
  end

  describe "the generated service (docs/TZ.md reference shape)" do
    it "has the reference skeleton: class, BASE_URL, the four contract methods, STATUS_MAP and ERROR_MAP" do
      aggregate_failures do
        expect(service).to start_with("# frozen_string_literal: true\n")
        expect(service).to include("class Provider\n  class NovapayService < BaseService")
        expect(service).to include("BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')")
        expect(service).to include("def create_request(operation, request_method = 'sbp')",
                                   "def fetch_status(operation)", "def process_callback(payload)",
                                   "def check_conditions(operation, request_method)")
        expect(service).to include("'pending'    => 'in_progress'", "'completed'  => 'approved'",
                                   "'cancelled'  => 'rejected'")
        expect(service).to include("401 => 'invalid_credentials'", "402 => 'insufficient_balance'",
                                   "429 => 'rate_limit'", "500 => 'internal_error'")
        expect(service).to include("429 => 'retry_with_backoff'")
      end
    end

    it "branches create_request by request_method with one payload builder per payout method" do
      aggregate_failures do
        expect(service).to include("case request_method", "when 'sbp' then build_sbp_payload(operation)",
                                   "when 'card' then build_card_payload(operation)")
        expect(service)
          .to include("return failure(:unprocessable_entity, 'unsupported_request_method') if payload.nil?")
        expect(service).to include("type: 'sbp',", "bank_code: operation.payout_requisite.dig('sbp', 'bank_code')")
        expect(service).to include("type: 'card',",
                                   "card_number: operation.payout_requisite.dig('card', 'card_number')")
        expect(service).not_to include("card_number: operation.payout_requisite.dig('sbp'")
      end
    end

    it "improves on the reference: units in a helper, threshold from minimum, 409 as success, Retry-After" do
      aggregate_failures do
        expect(service).to include("amount: amount_in_minor_units(operation.amount)", "(amount * 100).round")
        expect(service).to include("MIN_AMOUNT = 1000", "if operation.amount < MIN_AMOUNT")
        expect(service).to include("when 201, 409 then success(provider_operation_id: body['id']")
        expect(service).to include("retry_after: retry_after_seconds(response)", "casecmp?('Retry-After')")
        expect(service).to include("headers = auth_headers.merge(idempotency_headers(operation))")
        expect(service).to include("{ 'X-API-Key' => credentials[:api_key] }")
      end
    end

    it "verifies the webhook signature by the convention and dispatches on the event" do
      aggregate_failures do
        expect(service).to include("require 'json'", "require 'openssl'")
        expect(service).to include("verify_signature!(payload) # HMAC-SHA256 from X-NovaPay-Signature")
        expect(service).to include("payload.dig('headers', 'X-NovaPay-Signature')",
                                   "payload['raw_body'] || JSON.generate(callback_body(payload))",
                                   "OpenSSL::HMAC.hexdigest('SHA256', credentials[:callback_secret].to_s, message)")
        expect(service).to include("when 'payout.completed' then approve_operation(body['payout_id'])")
        expect(service).to include("when 'payout.failed', 'payout.cancelled' then " \
                                   "reject_operation(body['payout_id'], body.dig('error', 'code'))")
        expect(service).to include("else failure(:unprocessable_entity, 'unknown_event')")
      end
    end

    it "marks medium-confidence inferences with TODO(confidence) and cites the evidence" do
      aggregate_failures do
        expect(service).to include("# Evidence: description: копейках; error example (422): kopecks; minimum: 100000")
        expect(service).to include("# TODO(confidence 0.6): required when recipient.type = sbp")
        expect(service).to include("# TODO(confidence 0.6): encoding and canonicalization are not in the spec (W301)")
        expect(service).to include("REQUIRED_REQUISITES = {", "'sbp'  => %w[phone bank_code]",
                                   "'card' => %w[phone card_number]")
      end
    end

    it "generates cancel and balance as public methods outside the contract" do
      aggregate_failures do
        expect(service).to include("# Outside the BaseService contract (kind cancel)", "def cancel_request(operation)")
        expect(service).to include("# Outside the BaseService contract (kind balance)", "def fetch_balance\n")
        expect(service).to include("\"\#{BASE_URL}/payouts/\#{operation.provider_operation_id}/cancel\"")
      end
    end

    it "ships an HTTP client stub in base_contract.rb for local runs (docs/ASSUMPTIONS.md 23)" do
      contract = GenerationHelpers.novapay_file(:base_contract)

      aggregate_failures do
        expect(contract).to include("require 'net/http'", "class HttpClient", "def get(url, headers: {})",
                                    "def post(url, json: nil, form: nil, headers: {})")
        expect(contract).to include("Response.new(status: response.code.to_i, body: parse_body(response.body), " \
                                    "headers: response.each_header.to_h)")
      end
    end

    it "parses with Prism and keeps LF line endings" do
      aggregate_failures do
        expect(Prism.parse(service).errors).to be_empty
        expect(Prism.parse(GenerationHelpers.novapay_file(:base_contract)).errors).to be_empty
        expect(service).not_to include("\r")
        expect(service).to end_with("\n")
      end
    end
  end

  # The service and the contract stub are loaded in a child process with a fake client (no HTTP at
  # all): create_request, check_conditions and process_callback behave as the reference describes.
  describe "the generated service against base_contract.rb" do
    let(:script) { ProviderIntegrator::Files.read(File.expand_path("../fixtures/exercise_service.rb", __dir__)) }

    def run_generated_service
      Dir.mktmpdir("provider_integrator") do |dir|
        write_generated(dir)
        out, err, status = Open3.capture3(RbConfig.ruby, "--disable-gems", File.join(dir, "exercise.rb"))
        raise "exercise failed: #{err}" unless status.success?

        JSON.parse(out)
      end
    end

    def write_generated(dir)
      result.files.each { |file| ProviderIntegrator::Files.write(File.join(dir, file.name), file.content) }
      ProviderIntegrator::Files.write(File.join(dir, "exercise.rb"), script)
    end

    it "creates, checks, maps statuses and processes signed callbacks" do
      outcome = run_generated_service

      aggregate_failures do
        expect(outcome["create"]).to include("success" => true, "provider_operation_id" => "np_7f3a9b2c",
                                             "status" => "in_progress")
        expect(outcome["request"]).to include("url" => "https://api.sandbox.novapay.example/v1/payouts")
        expect(outcome["request"]["json"]).to eq("amount" => 150_000, "currency" => "RUB", "external_id" => "op_1",
                                                 "recipient" => { "type" => "sbp", "phone" => "79001234567",
                                                                  "bank_code" => "044525225" })
        expect(outcome["request"]["headers"]).to eq("X-API-Key" => "key", "Idempotency-Key" => "op_1")
        expect(outcome["duplicate"]).to include("success" => true, "status" => "in_progress")
        expect(outcome["rate_limited"]).to include("success" => false, "error" => "too_many_requests",
                                                   "code" => "provider.rate_limit", "retry_after" => 60)
        expect(outcome["too_low"]).to include("success" => false, "code" => "amount_too_low")
        expect(outcome["missing_requisite"]).to include("success" => false, "code" => "missing_requisite")
        expect(outcome["unsupported"]).to include("success" => false, "code" => "unsupported_request_method")
        expect(outcome["status"]).to include("success" => true, "status" => "approved")
        expect(outcome["callback"]).to include("success" => true, "status" => "approved",
                                               "provider_operation_id" => "np_7f3a9b2c")
        expect(outcome["callback_failed"]).to include("success" => true, "status" => "rejected",
                                                      "error_code" => "recipient_not_found")
        expect(outcome["bad_signature"]).to include("success" => false, "code" => "invalid_signature")
        expect(outcome["unknown_event"]).to include("success" => false, "code" => "unknown_event")
      end
    end
  end

  describe "the generation report" do
    let(:report) { JSON.parse(GenerationHelpers.novapay_file(:report)) }

    it "records the files with their digests, the validation and every event" do
      manifest = result.files.reject { |file| file.kind == "report" }.map(&:manifest)

      aggregate_failures do
        expect(report["files"]).to eq(manifest)
        expect(report["validation"]["ok"]).to be(true)
        expect(report["events"]["analysis"].map { |event| event["code"] }).to include("W301", "W402", "I401")
        expect(report["events"]["generation"]).to eq([])
        expect(report["provider"]).to include("slug" => "novapay", "class_name" => "Provider::NovapayService")
      end
    end

    it "lists the critical inferences and the TODO markers left in the code" do
      aggregate_failures do
        expect(report["requires_confirmation"].map { |item| item["code"] })
          .to eq(%w[W301 W402 W402 I201 I301 I401 I403])
        expect(report["inferences"]["amount_units"].first).to include("field" => "amount", "type" => "multiply",
                                                                      "value" => 100)
        expect(report["inferences"]["conditional_requirements"].map { |item| item["field"] })
          .to eq(%w[recipient.bank_code recipient.card_number])
        expect(report["todos"].map { |todo| todo["text"] }).to all(start_with("TODO(confidence "))
        expect(report["todos"].map { |todo| todo["file"] }.uniq).to eq(["novapay_service.rb"])
      end
    end
  end

  # Universality: the same generator, five deliberately different providers, valid output each time.
  describe "other provider specs" do
    %w[bearerpay rublepay numstatus cardpay legacy_swagger2].each do |name|
      it "generates validated output for #{name}" do
        generated = GenerationHelpers.generate_fixture(name)
        failed = generated.validation["checks"].reject { |check| check["ok"] }

        aggregate_failures do
          expect(generated).to be_success
          expect(failed).to be_empty
          expect(generated.file(:service).content).to include("< BaseService")
        end
      end
    end

    it "authenticates each provider its own way" do
      aggregate_failures do
        expect(GenerationHelpers.generate_fixture("bearerpay").file(:service).content)
          .to include("{ 'Authorization' => \"Bearer \#{credentials[:token]}\" }")
        expect(GenerationHelpers.generate_fixture("rublepay").file(:service).content)
          .to include("def with_api_key(url)", "URI.encode_www_form('api_key' => credentials[:api_key])")
        expect(GenerationHelpers.generate_fixture("numstatus").file(:service).content)
          .to include("def access_token", "grant_type: 'client_credentials'",
                      "TOKEN_URL = ENV.fetch('TRANZO_TOKEN_URL'")
      end
    end

    it "degrades without a webhook, sends forms for Swagger 2.0 and handles numeric statuses" do
      aggregate_failures do
        expect(GenerationHelpers.generate_fixture("bearerpay").file(:service).content)
          .to include("TODO(confidence 0.0): the spec declares no webhook (W304)", "raise NotImplementedError")
        expect(GenerationHelpers.generate_fixture("legacy_swagger2").file(:service).content)
          .to include("form: payload", "OpenSSL::Digest.hexdigest('MD5'")
        expect(GenerationHelpers.generate_fixture("numstatus").file(:service).content)
          .to include("'0'  => 'in_progress'", "'1'  => 'approved'", "map_status(body['state'])")
      end
    end
  end
end
