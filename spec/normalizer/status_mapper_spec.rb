# frozen_string_literal: true

# docs/IR_CONTRACT.md 2.7: statuses.yml decides first, the enum description explains its own values
# before the numeric convention is applied, and an unmapped value falls back to the canon default
# (the caller turns "default" into W201 and "numeric_default" into W204).
RSpec.describe ProviderIntegrator::Normalizer::StatusMapper do
  subject(:mapper) { described_class.new }

  # Only the keys the mapper reads, with a vocabulary the shipped dictionary does not know.
  let(:custom_dictionary) do
    { "canonical" => %w[in_progress approved rejected], "default" => "in_progress",
      "confidence" => { "dictionary" => 0.95, "token" => 0.85, "description" => 0.7, "numeric_default" => 0.5,
                        "default" => 0.3, "override" => 1.0 },
      "synonyms" => { "in_progress" => [], "approved" => ["ausgefuehrt"], "rejected" => ["storniert"] },
      "numeric" => {}, "description_patterns" => [], "description_words" => {} }
  end

  describe "#call" do
    context "when statuses.yml lists the value" do
      it "maps it with the dictionary confidence and cites the rule" do
        expect(mapper.call("completed")).to have_attributes(
          provider: "completed", canonical: "approved", confidence: 0.95, source: "dictionary",
          evidence: ["statuses.yml: completed -> approved"]
        )
      end

      it "ignores case and separators and cites the normalized value" do
        aggregate_failures do
          expect(mapper.call("IN-PROGRESS")).to have_attributes(
            provider: "IN-PROGRESS", canonical: "in_progress", source: "dictionary",
            evidence: ["statuses.yml: in_progress -> in_progress"]
          )
          expect(mapper.call("In Progress").canonical).to eq("in_progress")
          expect(mapper.call("Cancelled")).to have_attributes(canonical: "rejected", source: "dictionary")
        end
      end

      it "keeps the provider value as a String, so a numeric enum stays quotable" do
        expect(mapper.call(1, description: "1 — успешно")).to have_attributes(provider: "1", canonical: "approved")
      end

      it "reads the synonyms from the dictionary it is given, not from a hard-coded table" do
        aggregate_failures do
          expect(described_class.new(dictionary: custom_dictionary).call("Ausgefuehrt")).to have_attributes(
            canonical: "approved", source: "dictionary", evidence: ["statuses.yml: ausgefuehrt -> approved"]
          )
          expect(mapper.call("ausgefuehrt")).to have_attributes(canonical: "in_progress", source: "default")
        end
      end
    end

    context "when the enum description explains the value" do
      let(:description) { "0 — в обработке, 1 — успешно, 2 — отклонено" }

      it "maps by the description text and quotes the sentence it read" do
        expect(mapper.call("1", description:)).to have_attributes(
          provider: "1", canonical: "approved", confidence: 0.7, source: "description",
          evidence: ["description: 1 — успешно"]
        )
      end

      it "matches a description word as a token prefix" do
        expect(mapper.call("2", description:)).to have_attributes(
          canonical: "rejected", source: "description", evidence: ["description: 2 — отклонено"]
        )
      end

      it "is tried before the numeric convention, so the provider's own words win" do
        aggregate_failures do
          expect(mapper.call("1", description: "1 — отклонено, 2 — успешно")).to have_attributes(
            canonical: "rejected", confidence: 0.7, source: "description"
          )
          expect(mapper.call("1")).to have_attributes(canonical: "approved", source: "numeric_default")
        end
      end

      it "falls through when the description says nothing about this value" do
        expect(mapper.call("7", description:)).to have_attributes(canonical: "in_progress", source: "default")
      end
    end

    context "when only a token of a compound value is known" do
      it "maps by the token with the token confidence" do
        expect(mapper.call("rejected_by_bank")).to have_attributes(
          provider: "rejected_by_bank", canonical: "rejected", confidence: 0.85, source: "token",
          evidence: ["statuses.yml token: rejected_by_bank -> rejected"]
        )
      end

      it "refuses to read a negated value as its positive word" do
        expect(mapper.call("not_completed")).to have_attributes(
          canonical: "in_progress", confidence: 0.3, source: "default", evidence: ["default: in_progress"]
        )
      end
    end

    context "when the value is numeric and undescribed" do
      it "applies the convention of statuses.yml with the convention confidence" do
        aggregate_failures do
          expect(mapper.call("0")).to have_attributes(
            canonical: "in_progress", confidence: 0.5, source: "numeric_default",
            evidence: ["statuses.yml numeric: 0 -> in_progress"]
          )
          expect(mapper.call("-1")).to have_attributes(canonical: "rejected", source: "numeric_default")
        end
      end
    end

    context "when nothing matches" do
      it "falls back to the canon default at the lowest confidence" do
        expect(mapper.call("quantum_flux")).to have_attributes(
          provider: "quantum_flux", canonical: "in_progress", confidence: 0.3, source: "default",
          evidence: ["default: in_progress"]
        )
      end
    end

    context "when overrides.yml pins the value" do
      it "takes the override verbatim at confidence 1.0" do
        expect(mapper.call("completed", override: "rejected")).to have_attributes(
          canonical: "rejected", confidence: 1.0, source: "override",
          evidence: ["overrides.yml: completed -> rejected"]
        )
      end
    end
  end

  describe "#for_event" do
    it "maps a webhook event by its last token" do
      expect(mapper.for_event("payout.completed")).to have_attributes(
        provider: "payout.completed", canonical: "approved", confidence: 0.95, source: "dictionary",
        evidence: ["statuses.yml: completed -> approved"]
      )
    end

    it "accepts an earlier token with less confidence" do
      expect(mapper.for_event("payout.failed.notification")).to have_attributes(
        canonical: "rejected", confidence: 0.85, source: "token", evidence: ["statuses.yml: failed -> rejected"]
      )
    end

    it "returns nil when no token means a status, so the caller can raise W203" do
      aggregate_failures do
        expect(mapper.for_event("payout.updated")).to be_nil
        expect(mapper.for_event("")).to be_nil
      end
    end
  end

  describe "the canon it exposes" do
    it "answers with the three Space Payments statuses and their default" do
      aggregate_failures do
        expect(mapper.canonical_statuses).to eq(%w[in_progress approved rejected])
        expect(mapper.default_status).to eq("in_progress")
      end
    end
  end

  describe "a spec whose statuses are numeric codes" do
    let(:parsed) { ProviderIntegrator::Parser.call(path: fixture_path("specs", "numstatus.yaml")) }
    let(:statuses) { parsed.spec.statuses }

    it "reads the described codes from the description and reports the undescribed one (W204)" do
      aggregate_failures do
        expect(statuses.map(&:provider)).to eq(%w[0 1 2 3 4 -1])
        expect(statuses.map(&:canonical)).to eq(%w[in_progress approved rejected rejected rejected rejected])
        expect(statuses.first).to have_attributes(source: "description", confidence: 0.7,
                                                  evidence: ["description: 0 — в обработке"])
        expect(statuses.last).to have_attributes(source: "numeric_default", confidence: 0.5,
                                                 evidence: ["statuses.yml numeric: -1 -> rejected"])
        expect(parsed.spec.events.select { |event| event.code == "W204" }.map(&:message))
          .to eq(["Numeric status -1 mapped by convention to rejected; confirm with the provider"])
      end
    end
  end

  describe "a spec with a status no dictionary knows" do
    let(:parsed) { ProviderIntegrator::Parser.call(path: fixture_path("specs", "cardpay.yaml")) }

    it "defaults it to in_progress and the caller raises W201" do
      mapping = parsed.spec.statuses.find { |status| status.provider == "in_flight" }

      aggregate_failures do
        expect(mapping).to have_attributes(canonical: "in_progress", confidence: 0.3, source: "default",
                                           evidence: ["default: in_progress"])
        expect(parsed.spec.events.select { |event| event.code == "W201" }.map(&:message))
          .to eq(["Status in_flight has no canonical mapping; defaulting to in_progress"])
      end
    end
  end
end
