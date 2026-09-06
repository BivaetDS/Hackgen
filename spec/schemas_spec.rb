# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Schemas do
  describe ".path / .load / .schema" do
    it "knows exactly the five dictionaries, overrides, the IR and the OpenAPI subset" do
      expect(described_class::NAMES)
        .to eq(%i[canonical_contract operations fields statuses errors overrides provider_spec openapi_document])
    end

    it "resolves every schema to an existing draft 2020-12 document that validates against its meta-schema" do
      described_class::NAMES.each do |name|
        aggregate_failures(name.to_s) do
          expect(File).to exist(described_class.path(name))
          expect(described_class.load(name)["$schema"]).to eq("https://json-schema.org/draft/2020-12/schema")
          expect(described_class.schema(name).validate_schema.to_a).to eq([])
        end
      end
    end

    it "rejects unknown names instead of touching the file system" do
      expect { described_class.path(:novapay) }.to raise_error(ArgumentError, /unknown schema :novapay/)
    end

    it "memoizes loaded and compiled schemas across Symbol and String names" do
      loaded = described_class.load(:errors)
      compiled = described_class.schema(:errors)

      aggregate_failures do
        expect(described_class.load("errors")).to be(loaded)
        expect(described_class.schema("errors")).to be(compiled)
      end
    end
  end

  describe ".errors / .valid?" do
    it "returns human-readable messages naming the offending location" do
      errors = described_class.errors(:overrides, { "operations" => { "createPayout" => "payout" } })

      aggregate_failures do
        expect(errors.size).to eq(1)
        expect(errors.first).to include("/operations/createPayout")
        expect(described_class.valid?(:overrides, {})).to be(true)
      end
    end
  end

  describe "overrides.schema.json" do
    let(:overrides) do
      { "operations" => { "createPayout" => "create", "getBalance" => "balance" },
        "amount_unit" => { "CreatePayoutRequest.amount" => "minor" },
        "required_if" => [{ "field" => "recipient.bank_code", "when" => "recipient.type", "equals" => "sbp" }],
        "signature" => { "header" => "X-NovaPay-Signature", "algorithm" => "hmac-sha256", "encoding" => "hex",
                         "message" => "raw_body" },
        "status_map" => { "awaiting_compliance" => "in_progress", "7" => "rejected" },
        "error_actions" => { "amount_limit_exceeded" => "terminal_reject" } }
    end

    it "accepts the documented example with every section, and an empty file" do
      aggregate_failures do
        expect(described_class.errors(:overrides, overrides)).to eq([])
        expect(described_class.errors(:overrides, {})).to eq([])
        expect(described_class.errors(:overrides, overrides.slice("status_map"))).to eq([])
      end
    end

    it "accepts a body-field signature and rejects a signature with both or neither placement" do
      aggregate_failures do
        expect(described_class.valid?(:overrides, { "signature" => { "field" => "sign", "encoding" => "base64" } }))
          .to be(true)
        expect(described_class.valid?(:overrides, { "signature" => { "header" => "X-Sig", "field" => "sign" } }))
          .to be(false)
        expect(described_class.valid?(:overrides, { "signature" => { "algorithm" => "hmac-sha256" } })).to be(false)
      end
    end

    it "rejects unknown sections, unknown kinds, non-canonical statuses, actions and units" do
      aggregate_failures do
        expect(described_class.valid?(:overrides, { "fields" => {} })).to be(false)
        expect(described_class.valid?(:overrides, { "operations" => { "getBalance" => "extra" } })).to be(false)
        expect(described_class.valid?(:overrides, { "status_map" => { "done" => "completed" } })).to be(false)
        expect(described_class.valid?(:overrides, { "error_actions" => { "x" => "retry" } })).to be(false)
        expect(described_class.valid?(:overrides, { "amount_unit" => { "amount" => "minor" } })).to be(false)
        expect(described_class.valid?(:overrides, { "amount_unit" => { "Req.amount" => "cents" } })).to be(false)
        expect(described_class.valid?(:overrides, { "required_if" => [{ "field" => "a", "when" => "b" }] }))
          .to be(false)
      end
    end
  end

  # An override can only ask for values the IR can carry; the value domains live in provider_spec.schema.json.
  describe "overrides.schema.json vs provider_spec.schema.json" do
    let(:overrides) { described_class.load(:overrides).fetch("properties") }
    let(:ir_defs) { described_class.load(:provider_spec).fetch("$defs") }

    it "offers exactly the IR kinds, canonical statuses and actions" do
      aggregate_failures do
        expect(overrides.dig("operations", "additionalProperties", "enum")).to eq(ir_defs.dig("kind", "enum"))
        expect(overrides.dig("status_map", "additionalProperties", "enum"))
          .to eq(ir_defs.dig("canonicalStatus", "enum"))
        expect(overrides.dig("error_actions", "additionalProperties", "enum")).to eq(ir_defs.dig("action", "enum"))
      end
    end

    it "offers only the amount units the IR Conversion model knows" do
      expect(ir_defs.dig("Conversion", "properties", "unit_to", "enum"))
        .to include(*overrides.dig("amount_unit", "additionalProperties", "enum"))
    end

    it "offers signature values the IR Signature model accepts, never unknown" do
      signature = ir_defs.dig("Signature", "properties")

      %w[algorithm encoding message].each do |key|
        allowed = signature.dig(key, "enum") - ["unknown"]
        offered = overrides.dig("signature", "properties", key, "enum")

        expect(allowed).to include(*offered), "signature.#{key}: #{offered - allowed} not in the IR"
        expect(offered).not_to include("unknown")
      end
    end
  end
end
