# frozen_string_literal: true

# Rules under test: docs/IR_CONTRACT.md 2.6 - override, if/then, oneOf discriminator and, last,
# a rule read out of a description. A condition read from prose names the sibling field
# ("recipient.type"), because the generated code reads the condition out of the body by path.
RSpec.describe ProviderIntegrator::Normalizer::ConditionalRequired do
  subject(:analyzer) { described_class.new }

  # Every path of the request body, as OperationBuilder hands them over.
  let(:paths) { %w[amount currency recipient recipient.type recipient.bank_code recipient.card_number] }

  def field(path, description: nil, required: false, branch: nil)
    schema = description.nil? ? { "type" => "string" } : { "type" => "string", "description" => description }
    ProviderIntegrator::Parser::SchemaExtractor::Field.new(
      path:, name: path.split(".").last, schema:, required:, branch:,
      pointer: "#/components/schemas/Recipient/properties/#{path.split(".").last}"
    )
  end

  def branch(value, discriminator_path: "recipient.type")
    ProviderIntegrator::Parser::SchemaExtractor::BranchInfo.new(discriminator_path:, value:)
  end

  describe "#call" do
    context "when only the description states the rule" do
      # NovaPay: "БИК банка (обязателен для type=sbp)" on recipient.bank_code.
      it "reads a Russian description and resolves the condition to the sibling path" do
        found = analyzer.call(field: field("recipient.bank_code",
                                           description: "БИК банка (обязателен для type=sbp)"), paths:)

        aggregate_failures do
          expect(found.when).to eq("recipient.type")
          expect(found.equals).to eq("sbp")
          expect(found.source).to eq("description")
          expect(found.confidence).to eq(0.6)
          expect(found.evidence).to eq(["description: обязателен для type=sbp"])
        end
      end

      it "reads an English description the same way" do
        found = analyzer.call(field: field("recipient.card_number",
                                           description: "Card PAN. Required for type=card"), paths:)

        aggregate_failures do
          expect(found.when).to eq("recipient.type")
          expect(found.equals).to eq("card")
          expect(found.source).to eq("description")
          expect(found.evidence).to eq(["description: Required for type=card"])
        end
      end

      it "tolerates the punctuation and spacing providers actually write" do
        comma = analyzer.call(field: field("recipient.bank_code", description: "Обязателен, если type = sbp"),
                              paths:)
        only = analyzer.call(field: field("recipient.card_number", description: "Only for type = card"), paths:)

        aggregate_failures do
          expect(comma.when).to eq("recipient.type")
          expect(comma.evidence).to eq(["description: Обязателен, если type = sbp"])
          expect(only.when).to eq("recipient.type")
          expect(only.equals).to eq("card")
        end
      end

      # CardPay writes "Обязателен, если type = card." - the sentence's full stop is not part of the value.
      it "drops the sentence punctuation after the value" do
        found = analyzer.call(field: field("recipient.card_number",
                                           description: "Номер карты получателя. Обязателен, если type = card."),
                              paths:)

        aggregate_failures do
          expect(found.equals).to eq("card")
          expect(found.evidence).to eq(["description: Обязателен, если type = card."])
        end
      end

      it "keeps the plain name when the condition field is a top-level field of a flat schema" do
        found = analyzer.call(field: field("bank_code", description: "Обязателен, если payment_type = account"),
                              paths: %w[amount payment_type bank_code card_number])

        aggregate_failures do
          expect(found.when).to eq("payment_type")
          expect(found.equals).to eq("account")
          expect(found.source).to eq("description")
        end
      end

      # 2.6: the name is resolved as a sibling, and "if there is no such field - as is". Inventing
      # "recipient.payout_method" would read as a real path in the generated code; it is not one.
      it "leaves the name as the description wrote it when the schema has no such field at all" do
        found = analyzer.call(field: field("recipient.bank_code",
                                           description: "Обязателен, если payout_method = sbp"), paths:)

        aggregate_failures do
          expect(found.when).to eq("payout_method")
          expect(found.equals).to eq("sbp")
          expect(found.source).to eq("description")
          expect(found.confidence).to eq(0.6)
          expect(found.evidence).to eq(["description: Обязателен, если payout_method = sbp"])
        end
      end
    end

    context "when the schema states the rule structurally" do
      it "prefers an if/then rule over the description and trusts it" do
        found = analyzer.call(field: field("recipient.bank_code", description: "Обязателен, если type = sbp"),
                              paths:, if_then: { path: "recipient.bank_code", when: "recipient.type",
                                                 equals: "sbp" })

        aggregate_failures do
          expect(found.when).to eq("recipient.type")
          expect(found.equals).to eq("sbp")
          expect(found.source).to eq("if_then")
          expect(found.confidence).to eq(0.95)
          expect(found.evidence).to eq(["if/then: recipient.type = sbp"])
        end
      end

      it "records a value of any type as a String" do
        found = analyzer.call(field: field("card_number"), paths:,
                              if_then: { path: "card_number", when: "payment_type", equals: 2 })

        expect(found.equals).to eq("2")
      end

      it "takes a required field of a discriminated oneOf branch from the branch itself" do
        found = analyzer.call(field: field("recipient.phone", required: true, branch: branch("sbp")), paths:)

        aggregate_failures do
          expect(found.when).to eq("recipient.type")
          expect(found.equals).to eq("sbp")
          expect(found.source).to eq("discriminator")
          expect(found.confidence).to eq(0.95)
          expect(found.evidence).to eq(["discriminator recipient.type = sbp"])
        end
      end

      it "leaves an optional field of a branch unconditional" do
        expect(analyzer.call(field: field("recipient.phone", branch: branch("sbp")), paths:)).to be_nil
      end
    end

    context "when overrides.yml pins the rule" do
      it "wins over the description and is fully trusted" do
        found = analyzer.call(field: field("recipient.bank_code", description: "Обязателен, если type = sbp"),
                              paths:, override: { when: "recipient.type", equals: "sbp" })

        aggregate_failures do
          expect(found.source).to eq("override")
          expect(found.confidence).to eq(1.0)
          expect(found.when).to eq("recipient.type")
          expect(found.evidence).to eq(["overrides.yml: required when recipient.type = sbp"])
        end
      end
    end

    context "when nothing states a rule" do
      it "returns nil rather than inventing a condition" do
        aggregate_failures do
          expect(analyzer.call(field: field("recipient.bank_code", description: "БИК банка получателя"),
                               paths:)).to be_nil
          expect(analyzer.call(field: field("recipient.bank_code", description: "Required for SBP payouts"),
                               paths:)).to be_nil
          expect(analyzer.call(field: field("recipient.bank_code"), paths:)).to be_nil
        end
      end
    end
  end
end
