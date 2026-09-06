# frozen_string_literal: true

# Rules under test: docs/IR_CONTRACT.md 2.3 - the resolution order (override, container child,
# exact synonym, flat schema, "*_id" suffix, nothing), plus parameter roles and path parameters.
# The real fields.yml drives every example: the dictionary is the behaviour, not a detail to stub.
RSpec.describe ProviderIntegrator::Normalizer::FieldMapper do
  subject(:mapper) { described_class.new }

  # One field exactly as Parser::SchemaExtractor hands it over; only path, name and schema are read here.
  def field(path, schema = {}, name: nil)
    ProviderIntegrator::Parser::SchemaExtractor::Field.new(
      path:, name: name || path.split(".").last, schema:, required: false, branch: nil,
      pointer: "#/components/schemas/Body/properties/#{path}"
    )
  end

  # The mapping of the last field; earlier fields are mapped first so containers are already known.
  def mapping_for(fields, context: "request", **options)
    mapper.call(fields, context:, **options).fetch(fields.last.path)
  end

  def object = { "type" => "object" }
  def string = { "type" => "string" }

  describe "#call" do
    context "when overrides.yml names the field" do
      it "wins over the dictionary and records the override as evidence" do
        mapping = mapping_for([field("amount", string)], overrides: { "amount" => "fee" })

        aggregate_failures do
          expect(mapping.canonical).to eq("fee")
          expect(mapping.confidence).to eq(1.0)
          expect(mapping.source).to eq("override")
          expect(mapping.evidence).to eq(["overrides.yml: amount -> fee"])
          expect(mapping).to be_mapped
        end
      end
    end

    context "when the nearest mapped ancestor is a container" do
      let(:recipient) { field("recipient", object) }

      it "maps a child listed under the container to <container>.<child>" do
        mapping = mapping_for([recipient, field("recipient.bank_code", string)])

        aggregate_failures do
          expect(mapping.canonical).to eq("requisite.bank_code")
          expect(mapping.confidence).to eq(1.0)
          expect(mapping.source).to eq("dictionary")
          expect(mapping.evidence).to eq(["fields.yml: requisite child bank_code -> requisite.bank_code"])
        end
      end

      it "normalizes a camelCase child name before looking it up" do
        mapping = mapping_for([recipient, field("recipient.bankCode", string, name: "bankCode")])

        aggregate_failures do
          expect(mapping.canonical).to eq("requisite.bank_code")
          expect(mapping.evidence).to eq(["fields.yml: requisite child bank_code -> requisite.bank_code"])
        end
      end

      it "keeps a child that is not in the children list under the container, with lower confidence" do
        mapping = mapping_for([recipient, field("recipient.tax_residency", string)])

        aggregate_failures do
          expect(mapping.canonical).to eq("requisite.tax_residency")
          expect(mapping.confidence).to eq(0.5)
          expect(mapping.source).to eq("container")
          expect(mapping.evidence).to eq(["container requisite: tax_residency -> requisite.tax_residency"])
        end
      end

      it "applies no further step to a container child, so a generic name stays in the container" do
        mapping = mapping_for([field("error", object), field("error.reason", string)], context: "response")

        aggregate_failures do
          expect(mapping.canonical).to eq("error.code")
          expect(mapping.evidence).to eq(["fields.yml: error child reason -> error.code"])
        end
      end

      it "keeps a child in the container even when its own name is canonical elsewhere" do
        described = mapping_for([field("error", object), field("error.description", string)], context: "response")
        status = mapping_for([recipient, field("recipient.status", string)])

        aggregate_failures do
          expect(described.canonical).to eq("error.message")
          expect(described.confidence).to eq(1.0)
          expect(described.evidence).to eq(["fields.yml: error child description -> error.message"])
          expect(status.canonical).to eq("requisite.status")
          expect(status.confidence).to eq(0.5)
          expect(status.evidence).to eq(["container requisite: status -> requisite.status"])
        end
      end

      it "stops at an ancestor that is mapped to something other than a container" do
        mapping = mapping_for([field("status", object), field("status.code", string)], context: "response")

        aggregate_failures do
          expect(mapping.canonical).to be_nil
          expect(mapping.source).to eq("none")
        end
      end

      it "asks the nearest mapped ancestor only, so a mapped non-container ends the walk" do
        fields = [recipient, field("recipient.details", object), field("recipient.details.bank_code", string)]
        mapped = mapper.call(fields, context: "request")
        mapping = mapped.fetch("recipient.details.bank_code")

        aggregate_failures do
          expect(mapped.fetch("recipient.details").canonical).to eq("requisite.details")
          expect(mapping.canonical).to eq("requisite.bank_code")
          expect(mapping.confidence).to eq(0.8)
          expect(mapping.source).to eq("dictionary")
          expect(mapping.evidence).to eq(["fields.yml: flat bank_code -> requisite.bank_code"])
        end
      end

      it "looks past an unmapped ancestor and applies the ordinary rules" do
        mapping = mapping_for([field("payload", object), field("payload.bank_code", string)])

        aggregate_failures do
          expect(mapping.canonical).to eq("requisite.bank_code")
          expect(mapping.confidence).to eq(0.8)
          expect(mapping.evidence).to eq(["fields.yml: flat bank_code -> requisite.bank_code"])
        end
      end
    end

    context "when the name is an exact synonym" do
      it "maps it with confidence 1.0 and names the dictionary" do
        mapping = mapping_for([field("amount", { "type" => "integer" })])

        aggregate_failures do
          expect(mapping.canonical).to eq("amount")
          expect(mapping.confidence).to eq(1.0)
          expect(mapping.source).to eq("dictionary")
          expect(mapping.evidence).to eq(["fields.yml: amount -> amount"])
        end
      end

      it "reads the same name per scope: an id is our reference in a request, theirs in a response" do
        request = mapping_for([field("id", string)], context: "request")
        response = mapping_for([field("id", string)], context: "response")

        aggregate_failures do
          expect(request.canonical).to eq("external_id")
          expect(request.evidence).to eq(["fields.yml: id -> external_id"])
          expect(response.canonical).to eq("provider_operation_id")
          expect(response.evidence).to eq(["fields.yml: id -> provider_operation_id"])
        end
      end

      it "leaves a name listed in exclude unmapped" do
        mapping = mapping_for([field("old_status", string)], context: "webhook")

        aggregate_failures do
          expect(mapping.canonical).to be_nil
          expect(mapping.source).to eq("none")
          expect(mapping_for([field("status", string)], context: "webhook").canonical).to eq("status")
        end
      end

      it "accepts a container synonym only for an object" do
        composed = mapping_for([field("destination", { "oneOf" => [] })])

        aggregate_failures do
          expect(mapping_for([field("recipient", object)]).canonical).to eq("requisite")
          expect(composed.canonical).to eq("requisite")
          expect(mapping_for([field("recipient", string)]).canonical).to be_nil
        end
      end
    end

    context "when the provider keeps requisites and errors flat" do
      it "maps the payout-method switch to requisite.type" do
        mapping = mapping_for([field("payment_method", string)])

        aggregate_failures do
          expect(mapping.canonical).to eq("requisite.type")
          expect(mapping.confidence).to eq(1.0)
          expect(mapping.evidence).to eq(["fields.yml: flat payment_method -> requisite.type"])
        end
      end

      it "maps a top-level requisite child with flat_requisite confidence" do
        mapping = mapping_for([field("bank_code", string)])

        aggregate_failures do
          expect(mapping.canonical).to eq("requisite.bank_code")
          expect(mapping.confidence).to eq(0.8)
          expect(mapping.source).to eq("dictionary")
          expect(mapping.evidence).to eq(["fields.yml: flat bank_code -> requisite.bank_code"])
        end
      end

      it "maps a prefixed error field anywhere with exact confidence" do
        mapping = mapping_for([field("error_message", string)], context: "response")

        aggregate_failures do
          expect(mapping.canonical).to eq("error.message")
          expect(mapping.confidence).to eq(1.0)
          expect(mapping.evidence).to eq(["fields.yml: flat error_message -> error.message"])
        end
      end

      it "maps a bare code or message only inside an error response or a webhook payload" do
        in_error = mapping_for([field("code", string)], context: "response", error_context: true)
        in_webhook = mapping_for([field("message", string)], context: "webhook")
        in_success = mapping_for([field("code", string)], context: "response")

        aggregate_failures do
          expect(in_error.canonical).to eq("error.code")
          expect(in_error.confidence).to eq(0.8)
          expect(in_error.evidence).to eq(["fields.yml: flat code -> error.code"])
          expect(in_webhook.canonical).to eq("error.message")
          expect(in_webhook.confidence).to eq(0.8)
          expect(in_success.canonical).to be_nil
        end
      end

      it "reads a scalar named error as the code itself" do
        mapping = mapping_for([field("error", string)], context: "response")

        aggregate_failures do
          expect(mapping.canonical).to eq("error.code")
          expect(mapping.confidence).to eq(1.0)
          expect(mapping.evidence).to eq(["fields.yml: flat error -> error.code"])
        end
      end
    end

    context "when a name ends with an id suffix" do
      it "reads it as the provider's own id in a response or a webhook payload" do
        mapping = mapping_for([field("session_id", string)], context: "response")
        in_webhook = mapping_for([field("session_uuid", string)], context: "webhook")

        aggregate_failures do
          expect(mapping.canonical).to eq("provider_operation_id")
          expect(mapping.confidence).to eq(0.8)
          expect(mapping.source).to eq("dictionary")
          expect(mapping.evidence).to eq(["fields.yml: suffix _id -> provider_operation_id"])
          expect(in_webhook.canonical).to eq("provider_operation_id")
          expect(in_webhook.confidence).to eq(0.8)
          expect(in_webhook.evidence).to eq(["fields.yml: suffix _uuid -> provider_operation_id"])
        end
      end

      it "does not apply the suffix rule to a request field" do
        expect(mapping_for([field("session_id", string)]).canonical).to be_nil
      end
    end

    context "when nothing matches" do
      # The caller (OperationBuilder) turns an unmapped required request field into W403.
      it "leaves the field unmapped instead of guessing" do
        mapping = mapping_for([field("weather", string)])

        aggregate_failures do
          expect(mapping.canonical).to be_nil
          expect(mapping.confidence).to eq(0.0)
          expect(mapping.evidence).to eq([])
          expect(mapping.source).to eq("none")
          expect(mapping).not_to be_mapped
        end
      end
    end

    it "returns one mapping per field, keyed by provider_path in field order" do
      fields = [field("recipient", object), field("recipient.phone", string), field("amount", string)]

      expect(mapper.call(fields, context: "request").keys).to eq(["recipient", "recipient.phone", "amount"])
    end
  end

  describe "#parameter_role" do
    it "matches a stem against any token of the snake_case name" do
      aggregate_failures do
        expect(mapper.parameter_role("Idempotency-Key")).to eq("idempotency_key")
        expect(mapper.parameter_role("X-Payout-Signature")).to eq("signature")
        expect(mapper.parameter_role("Authorization")).to eq("auth")
      end
    end

    it "matches an entry that contains an underscore against the whole name only" do
      aggregate_failures do
        expect(mapper.parameter_role("X-Request-Id")).to eq("idempotency_key")
        expect(mapper.parameter_role("X-Api-Key")).to eq("auth")
        expect(mapper.parameter_role("request")).to be_nil
      end
    end

    it "returns nil for a header with no role" do
      expect(mapper.parameter_role("Content-Type")).to be_nil
    end
  end

  describe "#path_parameter_canonical" do
    it "reads a trailing id stem as the provider's operation id" do
      aggregate_failures do
        expect(mapper.path_parameter_canonical("payout_id")).to eq("provider_operation_id")
        expect(mapper.path_parameter_canonical("uuid")).to eq("provider_operation_id")
        expect(mapper.path_parameter_canonical("transaction_number")).to eq("provider_operation_id")
      end
    end

    it "reads an external_id synonym as our own reference" do
      expect(mapper.path_parameter_canonical("order_id")).to eq("external_id")
    end

    it "refuses to read someone else's id as the provider's" do
      aggregate_failures do
        expect(mapper.path_parameter_canonical("merchant_id")).to be_nil
        expect(mapper.path_parameter_canonical("customer_uuid")).to be_nil
        expect(mapper.path_parameter_canonical("slug")).to be_nil
      end
    end
  end

  describe "#container? and #money?" do
    it "answers from the dictionary, not from a hardcoded list" do
      aggregate_failures do
        expect(mapper.container?("requisite")).to be(true)
        expect(mapper.container?("amount")).to be(false)
        expect(mapper.money?("amount")).to be(true)
        expect(mapper.money?("balance")).to be(true)
        expect(mapper.money?("currency")).to be(false)
        expect(mapper.money?(nil)).to be(false)
      end
    end
  end
end
