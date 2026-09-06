# frozen_string_literal: true

# docs/IR_CONTRACT.md 2.10: the ProviderGateway names come from three facts of the create operation -
# the currency it pins, its default payout method and the direction of the money. Every fact read
# from a weaker source costs 0.3 of confidence, and a defaulted direction ends the evidence with
# "(default)", which is what makes the caller raise W405.
RSpec.describe ProviderIntegrator::Normalizer::GatewayConfigurator do
  subject(:configurator) { described_class.new }

  let(:request_methods) { ModelExamples::CORE["RequestMethods"] }
  let(:rub) { currency_field(constant: "RUB", enum: ["RUB"]) }

  # A create operation with nothing but the members the configurator reads.
  def operation(**changes)
    base = ModelExamples::OPERATION.merge(operation_id: "createPayout", path: "/payouts", tags: [], summary: nil,
                                          description: nil, request_fields: [], request_methods:)
    ProviderIntegrator::Models::Operation.from_h(base.merge(changes))
  end

  def currency_field(**changes)
    base = ModelExamples::FIELD.merge(provider_path: "currency", canonical: "currency", type: "string", enum: nil,
                                      constant: nil, example: nil, conversion: nil, conditional_required: nil,
                                      branch: nil)
    ProviderIntegrator::Models::FieldMapping.from_h(base.merge(changes))
  end

  describe "#call" do
    context "when the create operation states all three facts" do
      it "renders the withdraw templates and cites each fact" do
        config = configurator.call(operation: operation, fields: [rub], title: "NovaPay Payout API")

        expect(config).to have_attributes(
          external_method: "sbp_payout", gateway: "RUB_SBP_WITHDRAW", direction: "withdraw", currency: "RUB",
          method: "sbp", confidence: 0.9,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payout' in operationId createPayout)"]
        )
      end

      it "reads a deposit direction from the operationId and switches templates" do
        config = configurator.call(operation: operation(operation_id: "createDeposit", path: "/deposits"),
                                   fields: [rub], title: "Acme Payments API")

        expect(config).to have_attributes(
          external_method: "sbp_deposit", gateway: "RUB_SBP_DEPOSIT", direction: "deposit", confidence: 0.9,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: deposit (token 'deposit' in operationId createDeposit)"]
        )
      end

      it "reads the direction from the path when the operationId keeps quiet" do
        config = configurator.call(operation: operation(operation_id: "createOne", path: "/v1/payouts"),
                                   fields: [rub], title: "Acme Gateway API")

        expect(config).to have_attributes(
          direction: "withdraw", confidence: 0.9,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payouts' in path /v1/payouts)"]
        )
      end

      it "accepts a tag as a primary direction source" do
        config = configurator.call(operation: operation(operation_id: "makeOne", path: "/orders", tags: ["Payouts"]),
                                   fields: [rub], title: "Acme Gateway API")

        expect(config).to have_attributes(
          direction: "withdraw", confidence: 0.9,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payouts' in tag Payouts)"]
        )
      end
    end

    context "when a fact comes from a weaker source" do
      it "keeps a currency that is only an example, but pays 0.3 for it" do
        config = configurator.call(operation: operation, fields: [currency_field(example: "usd")],
                                   title: "NovaPay Payout API")

        expect(config).to have_attributes(
          gateway: "USD_SBP_WITHDRAW", currency: "usd", confidence: 0.6,
          evidence: ["currency: usd (example)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payout' in operationId createPayout)"]
        )
      end

      it "calls the payout method \"default\" when the request has no requisite type" do
        config = configurator.call(operation: operation(request_methods: nil), fields: [rub],
                                   title: "NovaPay Payout API")

        expect(config).to have_attributes(
          external_method: "default_payout", gateway: "RUB_DEFAULT_WITHDRAW", method: "default", confidence: 0.6,
          evidence: ["currency: RUB (enum constant)",
                     "request method: default (no requisite type)",
                     "direction: withdraw (token 'payout' in operationId createPayout)"]
        )
      end

      it "reads the summary before the description, and pays for either" do
        config = configurator.call(
          operation: operation(operation_id: "makeOne", path: "/orders", summary: "Create a payout",
                               description: "Deposit money into the wallet"),
          fields: [rub], title: "Acme Gateway API"
        )

        expect(config).to have_attributes(
          direction: "withdraw", confidence: 0.6,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payout' in summary)"]
        )
      end

      it "reads the description when everything above it is silent" do
        config = configurator.call(
          operation: operation(operation_id: "makeOne", path: "/orders",
                               description: "Deposit money into the wallet"),
          fields: [rub], title: "Acme Gateway API"
        )

        expect(config).to have_attributes(
          direction: "deposit", gateway: "RUB_SBP_DEPOSIT", confidence: 0.6,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: deposit (token 'deposit' in description)"]
        )
      end

      it "takes the direction from info.title only after the operation itself is silent" do
        config = configurator.call(operation: operation(operation_id: "makeOne", path: "/orders"), fields: [rub],
                                   title: "PayoutHub API")

        expect(config).to have_attributes(
          direction: "withdraw", confidence: 0.6,
          evidence: ["currency: RUB (enum constant)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payouthub' in info.title)"]
        )
      end

      it "renders XXX when no field pins the currency" do
        config = configurator.call(operation: operation, fields: [], title: "NovaPay Payout API")

        expect(config).to have_attributes(
          gateway: "XXX_SBP_WITHDRAW", currency: nil, confidence: 0.6,
          evidence: ["currency: unknown (unknown)",
                     "request method: sbp (default of recipient.type)",
                     "direction: withdraw (token 'payout' in operationId createPayout)"]
        )
      end
    end

    context "when nothing says which way the money goes" do
      let(:config) do
        configurator.call(operation: operation(operation_id: "makeOne", path: "/orders", request_methods: nil),
                          fields: [], title: "Acme Gateway API")
      end

      it "falls back to the dictionary default and marks the evidence, so the caller raises W405" do
        aggregate_failures do
          expect(config).to have_attributes(external_method: "default_payout", gateway: "XXX_DEFAULT_WITHDRAW",
                                            direction: "withdraw", currency: nil, method: "default")
          expect(config.evidence).to eq(["currency: unknown (unknown)",
                                         "request method: default (no requisite type)",
                                         "direction: withdraw (default)"])
          expect(config.evidence.last).to end_with("(default)")
        end
      end

      it "never drops below the floor confidence, however little it knows" do
        expect(config.confidence).to eq(0.3)
      end
    end
  end

  describe "a deposit spec end to end" do
    let(:parsed) { ProviderIntegrator::Parser.call(path: fixture_path("specs", "rublepay.yaml")) }

    it "derives the deposit gateway and reports it (I403)" do
      aggregate_failures do
        expect(parsed.spec.gateway_config).to have_attributes(external_method: "card_deposit",
                                                              gateway: "RUB_CARD_DEPOSIT", direction: "deposit",
                                                              currency: "RUB", method: "card", confidence: 0.9)
        expect(parsed.spec.events.map(&:code)).to include("I403")
        expect(parsed.spec.events.map(&:code)).not_to include("W405")
      end
    end
  end
end
