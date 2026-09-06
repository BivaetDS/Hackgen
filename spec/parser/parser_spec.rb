# frozen_string_literal: true

# The acceptance test of wave 1 part A (docs/PLAN.md 10): Parser.call on the case study spec must
# reproduce the hand-written IR in spec/fixtures/normalized_novapay.json exactly, raise exactly the
# events docs/IR_CONTRACT.md 3 lists for NovaPay, and behave sanely on every other fixture spec.
RSpec.describe ProviderIntegrator::Parser do
  let(:json) { ProviderIntegrator::JsonCanon }

  def parse(name) = described_class.call(path: fixture_path("specs", name))

  describe "NovaPay, the case study spec" do
    subject(:result) { described_class.call(path: repo_path("docs", "provider_api.yaml")) }

    it "succeeds and returns a ProviderSpec" do
      aggregate_failures do
        expect(result).to be_success
        expect(result.spec).to be_a(ProviderIntegrator::Models::ProviderSpec)
        expect(result.spec.ir_version).to eq(1)
      end
    end

    it "produces the golden IR byte for byte" do
      expect(json.generate(result.spec.to_h)).to eq(read_fixture("normalized_novapay.json"))
    end

    it "produces an IR that validates against provider_spec.schema.json" do
      expect(ProviderIntegrator::Schemas.errors(:provider_spec, result.spec.to_h)).to eq([])
    end

    it "reads the same spec from spec/fixtures/specs/novapay.yaml" do
      expect(json.generate(parse("novapay.yaml").spec.to_h)).to eq(read_fixture("normalized_novapay.json"))
    end

    # Two runs of the same input must be indistinguishable: no time, no rand, no object identity.
    it "is deterministic across runs" do
      first = json.sha256(json.generate(result.spec.to_h))
      second = json.sha256(json.generate(described_class.call(path: repo_path("docs", "provider_api.yaml"))
                                                     .spec.to_h))
      expect(first).to eq(second)
    end

    describe "the events docs/IR_CONTRACT.md 3 requires" do
      let(:codes) { result.events.map(&:code).tally }

      it "raises every expected code the expected number of times" do
        expect(codes).to eq("I101" => 5, "I201" => 1, "I301" => 1, "I401" => 1, "I403" => 1,
                            "W102" => 2, "W301" => 1, "W402" => 2)
      end

      it "raises nothing that would mean the analysis fell short" do
        expect(codes.keys).not_to include("W302", "W502", "W403", "W201", "W204", "W405", "W106", "W101")
      end

      it "reports the amount units with all three signals (I401)" do
        event = result.events.find { |item| item.code == "I401" }

        aggregate_failures do
          expect(event.details["unit"]).to eq("minor")
          expect(event.details["multiplier"]).to eq(100)
          expect(event.details["signals"])
            .to eq(["description: копейках", "error example (422): kopecks", "minimum: 100000"])
        end
      end

      it "warns that the HMAC canonicalization is not specified (W301)" do
        event = result.events.find { |item| item.code == "W301" }

        aggregate_failures do
          expect(event.message).to include("X-NovaPay-Signature", "hex", "raw_body")
          expect(event.location).to eq("#/paths/~1webhooks~1payout/post/parameters/0")
        end
      end

      it "warns about both conditional requirements read from a description (W402)" do
        fields = result.events.select { |item| item.code == "W402" }.map { |item| item.details["field"] }

        expect(fields).to contain_exactly("recipient.bank_code", "recipient.card_number")
      end

      it "reports cancel and balance as outside the contract (W102)" do
        ids = result.events.select { |item| item.code == "W102" }.map { |item| item.details["operation_id"] }

        expect(ids).to contain_exactly("cancelPayout", "getBalance")
      end
    end
  end

  # Universality: the same code, the same dictionaries, four deliberately different providers.
  describe "other provider specs" do
    {
      "bearerpay.yaml" => { auth: "http_bearer", webhook: nil },
      "rublepay.yaml" => { auth: "api_key", webhook: "path_heuristic" },
      "numstatus.yaml" => { auth: "oauth2_client_credentials", webhook: "callbacks" },
      "cardpay.yaml" => { auth: "api_key", webhook: "path_heuristic" },
      "legacy_swagger2.yaml" => { auth: "api_key", webhook: "path_heuristic" }
    }.each do |name, expected|
      it "parses #{name} into a create operation, an auth scheme and a status map" do
        spec = parse(name).spec

        aggregate_failures do
          expect(spec.operation_for("create_request")).not_to be_nil
          expect(spec.authentication.type).to eq(expected[:auth])
          expect(spec.webhook&.source).to eq(expected[:webhook])
          expect(spec.statuses).not_to be_empty
          expect(ProviderIntegrator::Schemas.errors(:provider_spec, spec.to_h)).to eq([])
        end
      end
    end

    it "announces the Swagger 2.0 conversion (W103)" do
      expect(parse("legacy_swagger2.yaml").events.map(&:code)).to include("W103")
    end

    it "keeps every spec deterministic" do
      %w[bearerpay.yaml rublepay.yaml numstatus.yaml cardpay.yaml legacy_swagger2.yaml].each do |name|
        digests = Array.new(2) { json.sha256(json.generate(parse(name).spec.to_h)) }

        expect(digests.uniq.size).to eq(1), "#{name} parsed differently on the second run"
      end
    end
  end

  # A spec is untrusted input: it must fail with a code and a sentence, never with a stack trace.
  describe "unusable documents" do
    {
      "invalid_broken_yaml.yaml" => "E001",
      "invalid_no_paths.yaml" => "E003",
      "invalid_bad_ref.yaml" => "E005"
    }.each do |name, code|
      it "reports #{code} for #{name} without raising" do
        result = parse(name)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.errors.map(&:code)).to eq([code])
          expect(result.spec).to be_nil
          expect(result.errors.first.message).not_to be_empty
        end
      end
    end

    it "reports E101 when no operation can create anything" do
      result = parse("invalid_no_create.yaml")

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.errors.map(&:code)).to eq(["E101"])
        expect(result.spec).not_to be_nil
      end
    end

    it "reports E001 for a file that does not exist" do
      result = described_class.call(path: fixture_path("specs", "no_such_file.yaml"))

      expect(result.errors.map(&:code)).to eq(["E001"])
    end
  end

  describe ".call!" do
    it "returns the IR for a usable document" do
      expect(described_class.call!(path: fixture_path("specs", "novapay.yaml")).provider.slug).to eq("novapay")
    end

    it "raises SpecError with the messages for an unusable one" do
      expect { described_class.call!(path: fixture_path("specs", "invalid_no_paths.yaml")) }
        .to raise_error(ProviderIntegrator::SpecError, /no paths/)
    end
  end
end
