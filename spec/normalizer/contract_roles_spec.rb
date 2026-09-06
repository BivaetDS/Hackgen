# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Normalizer::ContractRoles do
  subject(:roles) { described_class.new(log:) }

  let(:log) { ProviderIntegrator::EventLog.new }
  let(:canon) { ProviderIntegrator::Dictionaries.canonical_contract }

  # A Models::Operation with only the members the role assignment reads; the rest stay empty.
  def operation(kind:, operation_id:, path: "/payouts", method: "POST", **scoring)
    confidence = scoring.fetch(:confidence, 0.9)
    ProviderIntegrator::Models::Operation.new(
      kind:, operation_id:, path:, method:, confidence:, in_contract: false, canonical_method: nil, summary: nil,
      description: nil, tags: [], security: [], public: false, idempotency: nil, parameters: [], request_body: nil,
      request_fields: [], response_fields: [], responses: [], success_codes: [], idempotent_duplicate_codes: [],
      errors: [], request_methods: nil,
      classification: classification(kind, scoring.fetch(:score, 9), confidence)
    )
  end

  def classification(kind, score, confidence)
    scores = ProviderIntegrator::Dictionaries.operations.fetch("kinds").to_h { |name| [name, 0] }
    scores[kind] = score if scores.key?(kind)
    ProviderIntegrator::Models::Classification.new(confidence:, source: "scoring", scores:, evidence: [])
  end

  # The refs carry only the JSON pointer that the events use as their location.
  def assign(operations)
    refs = operations.map do |item|
      verb = item.method.downcase
      ProviderIntegrator::Parser::Document::OperationRef.new(
        path: item.path, http_method: verb, node: {}, path_item: {},
        pointer: ProviderIntegrator::Parser::Pointer.build("paths", item.path, verb)
      )
    end
    roles.call(operations, refs)
  end

  def create = operation(kind: "create", operation_id: "createPayout")
  def status = operation(kind: "status", operation_id: "getPayoutStatus", path: "/payouts/{payout_id}", method: "GET")
  def webhook = operation(kind: "webhook", operation_id: "payoutWebhook", path: "/webhooks/payout")

  describe "#call" do
    it "gives the single candidate of each role the contract method of canonical_contract.yml" do
      assigned = assign([create, status, webhook])

      aggregate_failures do
        expect(assigned.map(&:in_contract)).to eq([true, true, true])
        expect(assigned.map(&:canonical_method)).to eq(%w[create_request fetch_status process_callback])
        expect(assigned.map(&:canonical_method))
          .to eq(canon.fetch("contract_roles").values_at("create", "status", "webhook"))
        expect(log.include?("W102")).to be(false)
      end
    end

    it "reports every classified operation with I101" do
      assign([create, status])

      aggregate_failures do
        expect(log.with_code("I101").size).to eq(2)
        expect(log.with_code("I101").first.message)
          .to eq("Operation createPayout (POST /payouts) classified as create with confidence 0.9")
        expect(log.with_code("I101").first.location).to eq("#/paths/~1payouts/post")
        expect(log.with_code("I101").last.message)
          .to eq("Operation getPayoutStatus (GET /payouts/{payout_id}) classified as status with confidence 0.9")
        expect(log.with_code("I101").last.location).to eq("#/paths/~1payouts~1{payout_id}/get")
      end
    end

    it "gives cancel and balance their extra_methods name and reports W102" do
      cancel = operation(kind: "cancel", operation_id: "cancelPayout", path: "/payouts/{payout_id}/cancel")
      balance = operation(kind: "balance", operation_id: "getBalance", path: "/balance", method: "GET")

      assigned = assign([create, cancel, balance])

      aggregate_failures do
        expect(assigned.map(&:canonical_method)).to eq(%w[create_request cancel_request fetch_balance])
        expect(assigned.map(&:in_contract)).to eq([true, false, false])
        expect(assigned.drop(1).map(&:canonical_method))
          .to eq(canon.fetch("extra_methods").values_at("cancel", "balance"))
        expect(log.with_code("W102").map { |event| event.details.fetch("operation_id") })
          .to eq(%w[cancelPayout getBalance])
        expect(log.with_code("W102").first.message)
          .to eq("Operation cancelPayout (POST /payouts/{payout_id}/cancel) is outside the BaseService contract " \
                 "(kind cancel); generated as an extra method")
      end
    end

    it "names refund and list from extra_methods and leaves an unclassified operation without a method" do
      refund = operation(kind: "refund", operation_id: "refundPayout", path: "/payouts/{payout_id}/refund")
      listing = operation(kind: "list", operation_id: "listPayouts", path: "/payouts", method: "GET")
      mystery = operation(kind: "unknown", operation_id: "doThing", path: "/things")

      assigned = assign([refund, listing, mystery])

      aggregate_failures do
        expect(assigned.map(&:canonical_method)).to eq(["refund_request", "list_requests", nil])
        expect(assigned.map(&:in_contract)).to eq([false, false, false])
        expect(assigned.take(2).map(&:canonical_method))
          .to eq(canon.fetch("extra_methods").values_at("refund", "list"))
        expect(log.with_code("W102").map { |event| event.details.fetch("operation_id") })
          .to eq(%w[refundPayout listPayouts doThing])
        expect(log.with_code("W102").last.message)
          .to eq("Operation doThing (POST /things) is outside the BaseService contract (kind unknown); " \
                 "generated as an extra method")
      end
    end

    it "elects the highest-scoring candidate of a crowded role and demotes the rest" do
      card = operation(kind: "create", operation_id: "createCardPayout", path: "/payouts/card", score: 5)
      sbp = operation(kind: "create", operation_id: "createSbpPayout", path: "/payouts/sbp", score: 9)

      assigned = assign([card, sbp])

      aggregate_failures do
        expect(assigned.map(&:in_contract)).to eq([false, true])
        expect(assigned.map(&:canonical_method)).to eq([nil, "create_request"])
        expect(log.with_code("W102").map { |event| event.details.fetch("operation_id") }).to eq(["createCardPayout"])
      end
    end

    it "breaks a tie between candidates by spec order" do
      first = operation(kind: "create", operation_id: "createOne", path: "/one", score: 9)
      second = operation(kind: "create", operation_id: "createTwo", path: "/two", score: 9)

      assigned = assign([first, second])

      expect(assigned.map(&:in_contract)).to eq([true, false])
    end

    it "reports W101 only for a confidence below low_confidence_below" do
      sure = operation(kind: "create", operation_id: "createPayout", confidence: 0.6)
      unsure = operation(kind: "status", operation_id: "peek", path: "/peek/{id}", method: "GET", confidence: 0.14)

      assign([sure, unsure])

      aggregate_failures do
        expect(log.with_code("W101").map { |event| event.details.fetch("operation_id") }).to eq(["peek"])
        expect(log.with_code("W101").first.message)
          .to eq("Operation peek (GET /peek/{id}) classified as status with low confidence 0.14")
      end
    end
  end

  describe "#report_gaps" do
    it "reports E101, W106 and W304 for the contract roles nobody fills" do
      roles.report_gaps([operation(kind: "cancel", operation_id: "cancelPayout")])

      aggregate_failures do
        expect(log.to_a.map(&:code)).to eq(%w[E101 W106 W304])
        expect(log.with_code("E101").first.message).to eq("No create operation found; cannot generate create_request")
        expect(log.with_code("E101").first.details).to be_nil
        expect(log.error?).to be(true)
      end
    end

    it "does not report W304 when a webhook came from callbacks instead of an operation" do
      callback_webhook = ProviderIntegrator::Models::Webhook.from_h(ModelExamples::WEBHOOK)

      roles.report_gaps([create, status], webhook: callback_webhook)

      aggregate_failures do
        expect(log.include?("W304")).to be(false)
        expect(log).to be_empty
      end
    end

    it "leaves two operations of the same extra kind alone: only a contract role can be crowded" do
      first = operation(kind: "cancel", operation_id: "cancelOne", path: "/one/{id}/cancel")
      second = operation(kind: "cancel", operation_id: "cancelTwo", path: "/two/{id}/cancel")

      roles.report_gaps([create, status, webhook, first, second])

      aggregate_failures do
        expect(log.include?("W105")).to be(false)
        expect(log).to be_empty
      end
    end

    it "reports W105 once per crowded role, naming every candidate" do
      card = operation(kind: "create", operation_id: "createCardPayout", path: "/payouts/card", score: 5)
      sbp = operation(kind: "create", operation_id: "createSbpPayout", path: "/payouts/sbp", score: 9)
      assigned = assign([card, sbp, status, webhook])

      roles.report_gaps(assigned)

      aggregate_failures do
        expect(log.with_code("W105").size).to eq(1)
        expect(log.with_code("W105").first.details)
          .to eq({ "candidates" => %w[createCardPayout createSbpPayout], "kind" => "create",
                   "operation_id" => "createSbpPayout" })
        expect(log.with_code("W105").first.message)
          .to eq("Several create candidates (createCardPayout, createSbpPayout); createSbpPayout chosen, " \
                 "others generated as extra methods")
      end
    end
  end
end
