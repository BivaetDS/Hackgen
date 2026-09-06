# frozen_string_literal: true

# Rules under test: docs/IR_CONTRACT.md 2.4 - which signals score for minor and for major units,
# in which order they enter evidence, and what happens when they tie or say nothing at all.
# A wrong verdict here moves 100x the money, so the fallback must be "unknown", never a guess.
RSpec.describe ProviderIntegrator::Normalizer::MoneyUnits do
  subject(:units) { described_class.new }

  def field(schema, path: "amount")
    ProviderIntegrator::Parser::SchemaExtractor::Field.new(
      path:, name: path.split(".").last, schema:, required: true, branch: nil,
      pointer: "#/components/schemas/CreatePayoutRequest/properties/amount"
    )
  end

  describe "#call" do
    context "when the description, an error example and the minimum all say minor" do
      # NovaPay: "Сумма в копейках", minimum 100000, and a 422 example that spells out kopecks.
      let(:amount) do
        field({ "type" => "integer", "description" => "Сумма в копейках", "minimum" => 100_000,
                "example" => 1_500_000 })
      end
      let(:error_examples) do
        [[400, { "error" => { "code" => "invalid_request", "message" => "Missing required field" } }],
         [422, { "error" => { "code" => "validation_error",
                              "message" => "Amount must be at least 100000 kopecks" } }]]
      end

      it "multiplies by the ISO exponent of the currency and lists every signal in order" do
        verdict = units.call(field: amount, error_examples:, currency: "RUB")

        aggregate_failures do
          expect(verdict.unit).to eq("minor")
          expect(verdict.type).to eq("multiply")
          expect(verdict.value).to eq(100)
          expect(verdict.multiplier).to eq(100)
          expect(verdict.confidence).to eq(0.89)
          expect(verdict.scores).to eq({ "minor" => 8, "major" => 0 })
          expect(verdict.evidence).to eq(["description: копейках", "error example (422): kopecks",
                                          "minimum: 100000"])
        end
      end

      it "counts the error examples once, naming the first response that matched" do
        repeated = error_examples + [[500, { "error" => { "message" => "kopecks" } }]]
        verdict = units.call(field: amount, error_examples: repeated, currency: "RUB")

        aggregate_failures do
          expect(verdict.evidence.grep(/error example/)).to eq(["error example (422): kopecks"])
          expect(verdict.scores.fetch("minor")).to eq(8)
        end
      end
    end

    context "when the amount is a decimal string in rubles" do
      let(:amount) do
        field({ "type" => "string", "pattern" => '^\d+\.\d{2}$',
                "description" => "Сумма депозита в рублях: строка с двумя знаками после десятичной точки." })
      end

      it "keeps major units and formats the string instead of multiplying" do
        verdict = units.call(field: amount, currency: "RUB")

        aggregate_failures do
          expect(verdict.unit).to eq("major")
          expect(verdict.type).to eq("to_decimal_string")
          expect(verdict.value).to be_nil
          expect(verdict.multiplier).to eq(1)
          expect(verdict.confidence).to eq(0.86)
          expect(verdict.scores).to eq({ "minor" => 0, "major" => 6 })
          expect(verdict.evidence).to eq(["description: рублях", 'pattern: ^\d+\.\d{2}$', "type: string"])
        end
      end

      it "leaves a numeric major amount alone" do
        verdict = units.call(field: field({ "type" => "number", "multipleOf" => 0.01 }))

        aggregate_failures do
          expect(verdict.unit).to eq("major")
          expect(verdict.type).to eq("identity")
          expect(verdict.value).to be_nil
          expect(verdict.multiplier).to eq(1)
          expect(verdict.confidence).to eq(0.67)
          expect(verdict.scores).to eq({ "minor" => 0, "major" => 2 })
          expect(verdict.evidence).to eq(["multipleOf: 0.01"])
        end
      end
    end

    context "when the spec carries no unit signal at all" do
      # The caller (MoneyBuilder) turns this verdict into W401; the parser never invents a factor.
      it "returns unknown units with an identity conversion" do
        verdict = units.call(field: field({ "type" => "integer" }))

        aggregate_failures do
          expect(verdict.unit).to eq("unknown")
          expect(verdict.type).to eq("identity")
          expect(verdict.value).to eq(1)
          expect(verdict.multiplier).to eq(1)
          expect(verdict.confidence).to eq(0.0)
          expect(verdict.scores).to eq({ "minor" => 0, "major" => 0 })
          expect(verdict.evidence).to eq([])
        end
      end

      it "keeps a single weak minor signal below the threshold unknown" do
        verdict = units.call(field: field({ "type" => "integer", "minimum" => 100_000 }))

        aggregate_failures do
          expect(verdict.unit).to eq("unknown")
          expect(verdict.type).to eq("identity")
          expect(verdict.value).to eq(1)
          expect(verdict.scores).to eq({ "minor" => 2, "major" => 0 })
          expect(verdict.evidence).to eq(["minimum: 100000"])
          # The unit is unknown, but the one signal that scored is still reported honestly:
          # confidence is the margin between the two scores (2.4), not a verdict on the unit.
          expect(verdict.confidence).to eq(0.67)
        end
      end
    end

    context "when minor and major score equally" do
      it "refuses to pick a side and keeps both signals as evidence" do
        amount = field({ "type" => "string", "format" => "decimal", "description" => "Amount in cents" })
        verdict = units.call(field: amount, currency: "USD")

        aggregate_failures do
          expect(verdict.scores).to eq({ "minor" => 3, "major" => 3 })
          expect(verdict.unit).to eq("unknown")
          expect(verdict.type).to eq("identity")
          expect(verdict.value).to eq(1)
          expect(verdict.confidence).to eq(0.0)
          expect(verdict.evidence).to eq(["description: cents", "format: decimal", "type: string"])
        end
      end
    end
  end

  describe "#exponent_for" do
    it "uses the ISO 4217 exponent of the currency, falling back to the dictionary default" do
      aggregate_failures do
        expect(units.exponent_for("JPY")).to eq(1)
        expect(units.exponent_for("KWD")).to eq(1000)
        expect(units.exponent_for("rub")).to eq(100)
        expect(units.exponent_for("ZZZ")).to eq(100)
        expect(units.exponent_for(nil)).to eq(100)
      end
    end

    it "feeds the verdict, so a minor amount in yen is multiplied by 1" do
      verdict = units.call(field: field({ "type" => "integer", "description" => "Amount in minor units" }),
                           currency: "JPY")

      aggregate_failures do
        expect(verdict.unit).to eq("minor")
        expect(verdict.type).to eq("multiply")
        expect(verdict.value).to eq(1)
        expect(verdict.multiplier).to eq(1)
        expect(verdict.confidence).to eq(0.75)
        expect(verdict.scores).to eq({ "minor" => 3, "major" => 0 })
        expect(verdict.evidence).to eq(["description: minor"])
      end
    end
  end

  # The analyzer only decides; MoneyBuilder is what records the decision in the report.
  describe "reporting through Normalizer::MoneyBuilder" do
    let(:log) { ProviderIntegrator::EventLog.new }
    let(:context) do
      ProviderIntegrator::Normalizer::Context.new(
        document: nil, log:, overrides: ProviderIntegrator::Normalizer::Overrides.load(path: nil, log:)
      )
    end
    let(:builder) do
      ProviderIntegrator::Normalizer::MoneyBuilder.new(context:, operation_id: "createPayout", error_examples: [],
                                                       schema_name: "CreatePayoutRequest")
    end

    it "records I401 for a settled verdict and no warning" do
      conversion = builder.call(field: field({ "type" => "integer", "description" => "Сумма в копейках" }),
                                currency: "RUB")

      aggregate_failures do
        expect(conversion.to_h).to include("type" => "multiply", "value" => 100, "unit_from" => "major",
                                           "unit_to" => "minor", "source" => "scoring")
        expect(log.to_a.map(&:code)).to eq(["I401"])
        expect(log.to_a.first.message).to eq("Amount field amount in createPayout uses minor units " \
                                             "(multiplier 100, score 3); signals: description: копейках")
      end
    end

    it "takes the unit from overrides.yml when the spec cannot say it, and trusts it fully" do
      pinned = ProviderIntegrator::Normalizer::Overrides.new(
        { "amount_unit" => { "CreatePayoutRequest.amount" => "minor" } }, log
      )
      pinned_context = ProviderIntegrator::Normalizer::Context.new(document: nil, log:, overrides: pinned)
      conversion = ProviderIntegrator::Normalizer::MoneyBuilder.new(
        context: pinned_context, operation_id: "createPayout", error_examples: [],
        schema_name: "CreatePayoutRequest"
      ).call(field: field({ "type" => "integer" }), currency: "RUB")

      aggregate_failures do
        expect(conversion.to_h).to include("type" => "multiply", "value" => 100, "unit_to" => "minor",
                                           "source" => "override", "confidence" => 1.0)
        expect(conversion.evidence).to eq(["overrides.yml: amount_unit CreatePayoutRequest.amount -> minor"])
        expect(log.with_code("W401")).to be_empty
      end
    end

    it "warns with W401 when the signals did not settle the unit" do
      conversion = builder.call(field: field({ "type" => "integer" }))

      aggregate_failures do
        expect(conversion.to_h).to include("type" => "identity", "value" => 1, "unit_to" => "major")
        expect(log.to_a.map(&:code)).to eq(%w[I401 W401])
        expect(log.with_code("W401").first.message).to eq("Amount units for amount in createPayout could not " \
                                                          "be determined (score 0); multiplier 1 assumed")
      end
    end
  end
end
