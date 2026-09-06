# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::Validator do
  let(:log) { ProviderIntegrator::EventLog.new }

  def loaded(document, openapi: "3.0.3")
    ProviderIntegrator::Parser::Loader::Loaded.new(document:, openapi:, swagger: nil)
  end

  def loaded_fixture(name)
    ProviderIntegrator::Parser::Loader.call(path: fixture_path("specs", name), log:)
  end

  def validate(document, openapi: "3.0.3")
    described_class.call(loaded: loaded(document, openapi:), log:)
  end

  # A small but complete document: one operation, one component, one resolvable $ref.
  def valid_document
    { "openapi" => "3.0.3", "info" => { "title" => "Tiny Pay", "version" => "1.0.0" },
      "servers" => [{ "url" => "https://api.tiny.example/v1", "description" => "Sandbox" }],
      "paths" => { "/payouts" => { "post" => { "operationId" => "createPayout", "responses" => {
        "201" => { "description" => "Created", "content" => { "application/json" => {
          "schema" => { "$ref" => "#/components/schemas/Payout" }
        } } }
      } } } },
      "components" => { "schemas" => { "Payout" => { "type" => "object",
                                                     "properties" => { "id" => { "type" => "string" } } } } } }
  end

  # Valid against the subset schema, invalid 3.0: only the openapi3_parser cross-check sees it.
  def document_without_response_description
    operation = { "operationId" => "createPayout", "responses" => { "201" => { "content" => {} } } }
    valid_document.merge("paths" => { "/payouts" => { "post" => operation } })
  end

  describe ".call on a usable document" do
    it "accepts it without a single event" do
      aggregate_failures do
        expect(validate(valid_document)).to be(true)
        expect(log.to_a).to eq([])
      end
    end

    it "does not cross-check a 3.1 document, which openapi3_parser only half understands" do
      document = document_without_response_description.merge("openapi" => "3.1.0")

      aggregate_failures do
        expect(validate(document, openapi: "3.1.0")).to be(true)
        expect(log.to_a).to eq([])
      end
    end
  end

  describe ".call on a document the pipeline cannot use" do
    it "reports E003 when the document declares no paths" do
      result = described_class.call(loaded: loaded_fixture("invalid_no_paths.yaml"), log:)

      aggregate_failures do
        expect(result).to be(false)
        expect(log.to_a.map(&:code)).to eq(["E003"])
        expect(log.with_code("E003").first.message).to eq("Document has no paths; nothing to integrate")
      end
    end

    it "reports E003 when paths is present but empty" do
      expect(validate(valid_document.merge("paths" => {}))).to be(false)
      expect(log.to_a.map(&:code)).to eq(["E003"])
    end

    it "reports E004 when info.title is missing" do
      document = valid_document.merge("info" => { "version" => "1.0.0" })

      aggregate_failures do
        expect(validate(document)).to be(false)
        expect(log.to_a.map(&:code)).to eq(["E004"])
        expect(log.with_code("E004").first.message).to eq("Document has no info.title")
      end
    end

    it "reports E005 with the pointer of the reference that does not resolve" do
      result = described_class.call(loaded: loaded_fixture("invalid_bad_ref.yaml"), log:)

      aggregate_failures do
        expect(result).to be(false)
        expect(log.with_code("E005").map(&:message))
          .to eq(["Unresolvable $ref #/components/schemas/PayeeAccount"])
        expect(log.with_code("E005").first.location)
          .to eq("#/components/schemas/DisbursementRequest/properties/payee")
      end
    end

    it "reports E009 when the declared version is outside the supported grammar" do
      document = valid_document.merge("openapi" => "3.0.3-beta")

      aggregate_failures do
        expect(described_class.call(loaded: loaded(document, openapi: "3.0.3-beta"), log:)).to be(false)
        expect(log.to_a.map(&:code)).to eq(["E009"])
        expect(log.with_code("E009").first.details["reason"]).to include("openapi")
      end
    end

    it "reports E009 when a server entry has no url" do
      document = valid_document.merge("servers" => [{ "description" => "Sandbox" }])

      aggregate_failures do
        expect(validate(document)).to be(false)
        expect(log.to_a.map(&:code)).to eq(["E009"])
        expect(log.with_code("E009").first.details["reason"]).to include("url")
      end
    end

    it "reports E009 from the 3.0 cross-check for a rule the subset schema does not carry" do
      aggregate_failures do
        expect(validate(document_without_response_description)).to be(false)
        expect(log.to_a.map(&:code)).to eq(["E009"])
        expect(log.with_code("E009").first.details["reason"]).to eq("Missing required fields: description")
      end
    end

    it "reports both E004 and E003 when the document has neither title nor paths" do
      expect(validate({ "openapi" => "3.0.3", "info" => {} })).to be(false)
      expect(log.to_a.map(&:code)).to eq(%w[E004 E003])
    end
  end
end
