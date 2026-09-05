# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Events do
  let(:registry) { described_class::REGISTRY }

  it "registers each code once with a valid level and a template" do
    aggregate_failures do
      expect(described_class::ROWS.map(&:first)).to match_array(described_class.codes)
      expect(described_class.codes).to all(match(/\A[EWI]\d{3}\z/))
      registry.each_value do |definition|
        expect(described_class::LEVELS).to include(definition.level)
        expect(definition.template).not_to be_empty
        expect(definition.summary).not_to be_empty
      end
    end
  end

  it "uses error for E*, info for I*, and warning for W* except the documented info-level W102/W103" do
    registry.each_value do |definition|
      expected = case definition.code
                 when /\AE/ then "error"
                 when /\AI/, "W102", "W103" then "info"
                 else "warning"
                 end
      expect(definition.level).to eq(expected), "#{definition.code} should be #{expected}"
    end
  end

  it "documents every placeholder of every template" do
    registry.each_value do |definition|
      in_template = definition.template.scan(described_class::PLACEHOLDER).flatten.map(&:to_sym).uniq
      expect(definition.placeholders).to match_array(in_template)
    end
  end

  describe ".build" do
    it "renders the message from details and keeps details canonicalized" do
      event = described_class.build("W402", location: "#/components/schemas/Recipient/properties/bank_code",
                                            operation_id: "createPayout", field: "recipient.bank_code",
                                            when: "recipient.type", equals: :sbp)

      aggregate_failures do
        expect(event).to be_a(ProviderIntegrator::Models::Event)
        expect(event.code).to eq("W402")
        expect(event.level).to eq("warning")
        expect(event).to be_warning
        expect(event.message).to eq("Conditional requirement inferred from description: recipient.bank_code " \
                                    "is required when recipient.type equals sbp (createPayout)")
        expect(event.location).to eq("#/components/schemas/Recipient/properties/bank_code")
        expect(event.details).to eq({ "equals" => "sbp", "field" => "recipient.bank_code",
                                      "operation_id" => "createPayout", "when" => "recipient.type" })
      end
    end

    it "renders arrays and hashes readably" do
      units = described_class.build("I401", operation_id: "createPayout", field: "amount", unit: "minor",
                                            multiplier: 100, score: 8,
                                            signals: ["description: kopecks", "minimum: 100000"])
      statuses = described_class.build("I201", count: 2, mapping: { "pending" => "in_progress", "done" => "approved" })

      expect(units.message).to end_with("signals: description: kopecks, minimum: 100000")
      expect(statuses.message).to eq("Status mapping recorded (2 statuses): pending -> in_progress, done -> approved")
    end

    it "leaves details nil and location nil when nothing is given" do
      event = described_class.build("E003")

      expect(event.to_h).to eq({ "code" => "E003", "level" => "error",
                                 "message" => "Document has no paths; nothing to integrate",
                                 "location" => nil, "details" => nil })
    end

    it "fails loudly on a missing placeholder or an unknown code" do
      aggregate_failures do
        expect { described_class.build("W402", field: "x") }.to raise_error(ArgumentError, /W402: missing placeholder/)
        expect { described_class.build("X999") }.to raise_error(ArgumentError, /unknown event code/)
      end
    end

    it "accepts symbols as codes" do
      expect(described_class.build(:W104).code).to eq("W104")
    end
  end
end
