# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::RefResolver do
  let(:log) { ProviderIntegrator::EventLog.new }
  let(:resolver) { described_class.new(root:, log:) }
  let(:event) { log.to_a.first }
  let(:recipient) { { "type" => "object", "properties" => { "bank_code" => { "type" => "string" } } } }
  let(:terminus) { { "type" => "object", "title" => "Terminus" } }
  # Hop0 -> Hop1 -> ... -> Hop32, every component distinct and every target present: the chain trips
  # MAX_HOPS by length alone, which is the half of the E006 guard the mutual cycle below never reaches.
  let(:chain) do
    (0...described_class::MAX_HOPS)
      .to_h { |hop| ["Hop#{hop}", { "$ref" => "#/components/schemas/Hop#{hop + 1}" }] }
      .merge("Hop#{described_class::MAX_HOPS}" => terminus)
  end
  let(:root) do
    { "paths" => { "/payouts" => { "post" => { "operationId" => "createPayout" } } },
      "definitions" => { "Payment" => { "type" => "object" } },
      "components" => { "schemas" => {
        "Recipient" => recipient,
        "RecipientAlias" => { "$ref" => "#/components/schemas/Recipient" },
        "Loop" => { "$ref" => "#/components/schemas/Mirror" },
        "Mirror" => { "$ref" => "#/components/schemas/Loop" },
        "Ouroboros" => { "$ref" => "#/components/schemas/Ouroboros" }
      }.merge(chain) } }
  end

  describe ".ref?" do
    it "recognizes a $ref wrapper only when the value is a String" do
      aggregate_failures do
        expect(described_class.ref?({ "$ref" => "#/components/schemas/Recipient" })).to be(true)
        expect(described_class.ref?({ "$ref" => { "url" => "x" } })).to be(false)
        expect(described_class.ref?({ "type" => "object" })).to be(false)
        expect(described_class.ref?("#/components/schemas/Recipient")).to be(false)
        expect(described_class.ref?(nil)).to be(false)
      end
    end
  end

  describe "#resolve" do
    context "with a resolvable local reference" do
      it "returns the component, its pointer and its schema name" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Recipient" },
                                    "#/paths/~1payouts/post/requestBody/content/application~1json/schema")

        aggregate_failures do
          expect(resolved.node).to eq(recipient)
          expect(resolved.pointer).to eq("#/components/schemas/Recipient")
          expect(resolved.schema_name).to eq("Recipient")
          expect(log).to be_empty
        end
      end

      it "follows a chain of $refs and keeps the name of the last component" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/RecipientAlias" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to eq(recipient)
          expect(resolved.pointer).to eq("#/components/schemas/Recipient")
          expect(resolved.schema_name).to eq("Recipient")
          expect(log).to be_empty
        end
      end

      it "names components under definitions too, for converted Swagger 2.0 documents" do
        resolved = resolver.resolve({ "$ref" => "#/definitions/Payment" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to eq({ "type" => "object" })
          expect(resolved.schema_name).to eq("Payment")
        end
      end

      it "reports no schema name for a target outside components and definitions" do
        resolved = resolver.resolve({ "$ref" => "#/paths/~1payouts/post" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to eq({ "operationId" => "createPayout" })
          expect(resolved.pointer).to eq("#/paths/~1payouts/post")
          expect(resolved.schema_name).to be_nil
        end
      end

      it "returns a node that is not a $ref unchanged, with the pointer it was addressed by" do
        resolved = resolver.resolve({ "type" => "string" }, "#/components/schemas/Recipient/properties/bank_code")

        aggregate_failures do
          expect(resolved.node).to eq({ "type" => "string" })
          expect(resolved.pointer).to eq("#/components/schemas/Recipient/properties/bank_code")
          expect(resolved.schema_name).to be_nil
          expect(log).to be_empty
        end
      end
    end

    context "when the target does not exist" do
      let(:location) { "#/components/schemas/Recipient/properties/payee" }

      it "reports E005 at the pointer that holds the $ref" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Missing" }, location)

        aggregate_failures do
          expect(resolved.node).to be_nil
          expect(resolved.pointer).to eq("#/components/schemas/Missing")
          expect(log.to_a.map(&:code)).to eq(["E005"])
          expect(event.message).to eq("Unresolvable $ref #/components/schemas/Missing")
          expect(event.location).to eq(location)
          expect(event.details).to eq({ "ref" => "#/components/schemas/Missing" })
        end
      end

      it "reports E005 when the pointer walks through a scalar" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Recipient/properties/bank_code/type/deep" },
                                    location)

        expect(resolved.node).to be_nil
        expect(event.code).to eq("E005")
      end
    end

    context "with a reference to another file" do
      it "refuses the reference with E008 and keeps the original pointer" do
        resolved = resolver.resolve({ "$ref" => "common.yaml#/Recipient" }, "#/components/schemas/Payout")

        aggregate_failures do
          expect(resolved.node).to be_nil
          expect(resolved.pointer).to eq("#/components/schemas/Payout")
          expect(resolved.schema_name).to be_nil
          expect(log.to_a.map(&:code)).to eq(["E008"])
          expect(event.message).to eq("External $ref common.yaml#/Recipient is not supported; " \
                                      "only local #/ references are resolved")
          expect(event.location).to eq("#/components/schemas/Payout")
        end
      end

      it "refuses a URL reference too" do
        resolved = resolver.resolve({ "$ref" => "https://example.test/schemas.yaml#/Recipient" }, "#/x")

        expect(resolved.node).to be_nil
        expect(event.details).to eq({ "ref" => "https://example.test/schemas.yaml#/Recipient" })
      end
    end

    context "with a reference cycle" do
      it "reports E006 at the pointer of the last hop instead of looping" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Loop" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to be_nil
          expect(resolved.pointer).to eq("#/components/schemas/Mirror")
          expect(resolved.schema_name).to eq("Mirror")
          expect(log.to_a.map(&:code)).to eq(["E006"])
          expect(event.message).to eq("$ref cycle deeper than 32 levels at #/components/schemas/Loop")
          expect(event.location).to eq("#/components/schemas/Mirror")
          expect(event.details).to eq({ "ref" => "#/components/schemas/Loop", "limit" => 32 })
        end
      end

      it "reports E006 once the chain is MAX_HOPS long, even though no reference repeats" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Hop0" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to be_nil
          expect(resolved.pointer).to eq("#/components/schemas/Hop31")
          expect(resolved.schema_name).to eq("Hop31")
          expect(log.to_a.map(&:code)).to eq(["E006"])
          expect(event.message).to eq("$ref cycle deeper than 32 levels at #/components/schemas/Hop32")
          expect(event.location).to eq("#/components/schemas/Hop31")
          expect(event.details).to eq({ "ref" => "#/components/schemas/Hop32", "limit" => 32 })
        end
      end

      it "resolves a chain of exactly MAX_HOPS hops without calling it a cycle" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Hop1" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to eq(terminus)
          expect(resolved.pointer).to eq("#/components/schemas/Hop32")
          expect(resolved.schema_name).to eq("Hop32")
          expect(log).to be_empty
        end
      end

      it "reports E006 for a component that references itself" do
        resolved = resolver.resolve({ "$ref" => "#/components/schemas/Ouroboros" }, "#/x")

        aggregate_failures do
          expect(resolved.node).to be_nil
          expect(event.code).to eq("E006")
          expect(event.location).to eq("#/components/schemas/Ouroboros")
          expect(described_class::MAX_HOPS).to eq(32)
        end
      end
    end
  end

  describe "#node" do
    it "returns the resolved node, or nil when it cannot be resolved" do
      aggregate_failures do
        expect(resolver.node({ "$ref" => "#/components/schemas/Recipient" }, "#/x")).to eq(recipient)
        expect(resolver.node({ "$ref" => "#/components/schemas/Missing" }, "#/x")).to be_nil
        expect(log.to_a.map(&:code)).to eq(["E005"])
      end
    end
  end
end
