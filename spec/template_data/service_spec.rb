# frozen_string_literal: true

# Unit-level checks of the service pieces on IR variations the fixture specs do not cover: stubs,
# single-method payloads, status-field callbacks and query-string list methods.
RSpec.describe ProviderIntegrator::TemplateData::Service do
  let(:spec) { GenerationHelpers.novapay_spec }

  def service_for(spec)
    described_class.new(ProviderIntegrator::Generator::Context.new(spec:))
  end

  def source_of(methods, name) = methods.find { |method| method.name == name }.source

  it "orders the contract methods as the canon does and lists the extras after them" do
    service = service_for(spec)

    aggregate_failures do
      expect(service.contract_methods.map(&:name)).to eq(%w[create_request fetch_status process_callback
                                                            check_conditions])
      expect(service.extra_methods.map(&:name)).to eq(%w[cancel_request fetch_balance])
      expect(service.private_methods_data.map(&:name))
        .to include("build_sbp_payload", "build_card_payload", "parse_create_response", "verify_signature!",
                    "missing_requisites", "auth_headers", "idempotency_headers", "map_status", "provider_error",
                    "retry_after_seconds", "error_code", "amount_in_minor_units")
      expect(service.requires).to eq(%w[json openssl])
    end
  end

  it "generates stubs when the spec has no status operation and no webhook" do
    stubbed = spec.with(operations: spec.operations.select { |op| op.kind == "create" }, webhook: nil)
    service = service_for(stubbed)

    aggregate_failures do
      expect(source_of(service.contract_methods, "fetch_status"))
        .to include("TODO(confidence 0.0): the spec has no status operation (W106)", "raise NotImplementedError")
      expect(source_of(service.contract_methods, "process_callback"))
        .to include("TODO(confidence 0.0): the spec declares no webhook (W304)")
      expect(service.private_methods_data.map(&:name)).not_to include("verify_signature!", "callback_body")
      expect(service.requires).to eq([])
    end
  end

  it "builds a single payload without branching when the requisites declare no payout methods" do
    create = spec.operation_for("create_request")
    single = create.with(request_methods: nil)
    service = service_for(spec.with(operations: spec.operations.map { |op| op.equal?(create) ? single : op }))

    aggregate_failures do
      expect(source_of(service.contract_methods, "create_request"))
        .to include("def create_request(operation, request_method = 'create')",
                    "payload = build_payout_payload(operation)")
      expect(source_of(service.contract_methods, "create_request")).not_to include("case request_method")
      expect(source_of(service.private_methods_data, "build_payout_payload"))
        .to include("phone: operation.payout_requisite.dig(request_method, 'phone')")
      expect(service.top_constants.map(&:name)).to include("REQUIRED_REQUISITES")
      expect(service.top_constants.map(&:name)).not_to include("REQUEST_METHODS")
    end
  end

  it "dispatches the callback on the status field when the payload has no event" do
    webhook = spec.webhook.with(event_field: nil, events: [])
    service = service_for(spec.with(webhook:))
    source = source_of(service.contract_methods, "process_callback")

    aggregate_failures do
      expect(source).to include("case map_status(body['status'])",
                                "when 'approved' then approve_operation(body['payout_id'])",
                                "when 'rejected' then reject_operation(body['payout_id'], body.dig('error', 'code'))")
      expect(source).to include("when 'in_progress' then success(status: 'in_progress', response: body)")
    end
  end

  it "adds the query string of a list operation and names unknown operations from their operationId" do
    generated = GenerationHelpers.generate_fixture("bearerpay").file(:service).content

    aggregate_failures do
      expect(generated).to include("def list_requests(params = {})",
                                   "url = \"\#{url}?\#{URI.encode_www_form(params)}\" unless params.empty?")
      expect(generated).to include("def quote_transfer_fee(operation, request_method)",
                                   "def download_transfer_receipt(operation)")
      expect(generated).to include("require 'uri'")
    end
  end
end
