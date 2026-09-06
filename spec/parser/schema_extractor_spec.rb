# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::SchemaExtractor do
  let(:log) { ProviderIntegrator::EventLog.new }

  # An extractor over a document whose components.schemas are +schemas+. Specs build the schemas as
  # raw Hashes so that a failing example points at exactly one rule of docs/IR_CONTRACT.md.
  def extractor_for(schemas)
    root = { "components" => { "schemas" => schemas } }
    described_class.new(ProviderIntegrator::Parser::Document.new(root:, log:, spec_format: "3.0.3"))
  end

  def ref(name) = { "$ref" => "#/components/schemas/#{name}" }

  def fields_of(schemas, name) = extractor_for(schemas).call(ref(name), "#/components/schemas/#{name}")

  # [provider_path, required, branch value] per flattened field: the three members the rules below
  # are about.
  def rows(fields) = fields.map { |field| [field.path, field.required, field.branch&.value] }

  describe "#call" do
    context "with a nested object schema" do
      let(:schemas) do
        {
          "Payout" => {
            "type" => "object", "required" => %w[amount recipient],
            "properties" => {
              "amount" => { "type" => "integer" },
              "recipient" => ref("Recipient"),
              "items" => { "type" => "array", "items" => ref("Item") }
            }
          },
          "Recipient" => {
            "type" => "object", "required" => %w[type],
            "properties" => { "type" => { "type" => "string" }, "bank_code" => { "type" => "string" } }
          },
          "Item" => {
            "type" => "object", "required" => %w[sku],
            "properties" => { "sku" => { "type" => "string" }, "qty" => { "type" => "integer" } }
          }
        }
      end
      let(:fields) { fields_of(schemas, "Payout") }

      it "walks depth first, emitting the container before its children" do
        expect(fields.map(&:path)).to eq(["amount", "recipient", "recipient.type", "recipient.bank_code",
                                          "items", "items[].sku", "items[].qty"])
      end

      it "flattens array items under '<path>[]'" do
        expect(fields.map(&:path).grep(/\Aitems/)).to eq(["items", "items[].sku", "items[].qty"])
      end

      it "reads 'required' from the enclosing object, not from the root" do
        expect(rows(fields)).to eq([["amount", true, nil], ["recipient", true, nil], ["recipient.type", true, nil],
                                    ["recipient.bank_code", false, nil], ["items", false, nil],
                                    ["items[].sku", true, nil], ["items[].qty", false, nil]])
      end

      it "keeps the property name and the pointer of the node each field came from" do
        aggregate_failures do
          expect(fields.map(&:name)).to eq(%w[amount recipient type bank_code items sku qty])
          expect(fields.map(&:pointer)).to eq(["#/components/schemas/Payout/properties/amount",
                                               "#/components/schemas/Recipient",
                                               "#/components/schemas/Recipient/properties/type",
                                               "#/components/schemas/Recipient/properties/bank_code",
                                               "#/components/schemas/Payout/properties/items",
                                               "#/components/schemas/Item/properties/sku",
                                               "#/components/schemas/Item/properties/qty"])
          expect(fields.first.schema).to eq({ "type" => "integer" })
        end
      end
    end

    context "with allOf" do
      let(:schemas) do
        {
          "Base" => {
            "type" => "object", "required" => %w[id],
            "properties" => { "id" => { "type" => "string" }, "amount" => { "type" => "integer" } }
          },
          "Payout" => {
            "allOf" => [ref("Base"),
                        { "type" => "object", "required" => %w[amount currency],
                          "properties" => { "currency" => { "type" => "string" } } }]
          }
        }
      end

      it "unions the properties in first-seen order and unions the required lists" do
        expect(rows(fields_of(schemas, "Payout")))
          .to eq([["id", true, nil], ["amount", true, nil], ["currency", true, nil]])
      end

      it "merges the members into one node and drops the allOf keyword" do
        merged = extractor_for(schemas).flatten(ref("Payout"), "#/components/schemas/Payout")

        aggregate_failures do
          expect(merged["properties"].keys).to eq(%w[id amount currency])
          expect(merged["required"]).to eq(%w[id amount currency])
          expect(merged["type"]).to eq("object")
          expect(merged).not_to have_key("allOf")
        end
      end

      it "lets the outer node override a member's property without moving it" do
        outer = { "Base" => { "type" => "object", "required" => %w[id],
                              "properties" => { "id" => { "type" => "string" },
                                                "amount" => { "type" => "integer" } } },
                  "Payout" => { "type" => "object", "allOf" => [ref("Base")],
                                "properties" => { "amount" => { "type" => "string" } } } }
        fields = fields_of(outer, "Payout")

        aggregate_failures do
          expect(rows(fields)).to eq([["amount", false, nil], ["id", true, nil]])
          expect(fields.first.schema).to eq({ "type" => "string" })
        end
      end
    end

    context "with oneOf and a discriminator" do
      let(:schemas) do
        {
          "Requisite" => {
            "oneOf" => [ref("Sbp"), ref("Card")],
            "discriminator" => { "propertyName" => "type",
                                 "mapping" => { "sbp" => "#/components/schemas/Sbp",
                                                "card" => "#/components/schemas/Card" } }
          },
          "Sbp" => { "type" => "object", "required" => %w[type phone comment],
                     "properties" => { "type" => { "type" => "string" }, "phone" => { "type" => "string" },
                                       "comment" => { "type" => "string" } } },
          "Card" => { "type" => "object", "required" => %w[type pan],
                      "properties" => { "type" => { "type" => "string" }, "pan" => { "type" => "string" },
                                        "comment" => { "type" => "string" } } }
        }
      end
      let(:fields) { fields_of(schemas, "Requisite") }

      it "keeps the branch of a field that lives in exactly one member" do
        expect(rows(fields).select(&:last)).to eq([["phone", true, "sbp"], ["pan", true, "card"]])
      end

      it "drops the branch of a shared field and requires it only when every member requires it" do
        expect(rows(fields)).to eq([["type", true, nil], ["phone", true, "sbp"],
                                    ["comment", false, nil], ["pan", true, "card"]])
      end

      it "names the branch by its mapping key and repeats the discriminator path on every field" do
        branch = fields.find { |field| field.path == "phone" }.branch

        expect([branch.discriminator_path, branch.value]).to eq(%w[type sbp])
      end
    end

    context "with oneOf and no discriminator" do
      let(:schemas) do
        {
          "Requisite" => { "oneOf" => [ref("Sbp"), ref("Card")] },
          "Sbp" => { "type" => "object", "required" => %w[phone],
                     "properties" => { "phone" => { "type" => "string" } } },
          "Card" => { "type" => "object", "required" => %w[pan],
                      "properties" => { "pan" => { "type" => "string" } } }
        }
      end

      it "collects every member but tags no branch: nothing says which value selects one" do
        expect(rows(fields_of(schemas, "Requisite"))).to eq([["phone", true, nil], ["pan", true, nil]])
      end
    end

    context "with anyOf instead of oneOf" do
      let(:schemas) do
        {
          "Requisite" => { "anyOf" => [ref("Sbp"), ref("Card")],
                           "discriminator" => { "propertyName" => "type" } },
          "Sbp" => { "type" => "object", "required" => %w[type phone],
                     "properties" => { "type" => { "type" => "string" }, "phone" => { "type" => "string" } } },
          "Card" => { "type" => "object", "required" => %w[type pan],
                      "properties" => { "type" => { "type" => "string" }, "pan" => { "type" => "string" } } }
        }
      end

      it "branches on anyOf the same way as on oneOf" do
        expect(rows(fields_of(schemas, "Requisite")))
          .to eq([["type", true, nil], ["phone", true, "sbp"], ["pan", true, "card"]])
      end
    end

    context "with a $ref cycle" do
      let(:schemas) do
        {
          "Node" => {
            "type" => "object", "required" => %w[id],
            "properties" => { "id" => { "type" => "string" }, "parent" => ref("Node"),
                              "children" => { "type" => "array", "items" => ref("Node") } }
          }
        }
      end

      it "stops at a pointer already on the stack instead of recursing" do
        aggregate_failures do
          expect(fields_of(schemas, "Node").map(&:path))
            .to eq(["id", "parent", "parent.id", "parent.parent", "parent.children",
                    "children", "children[].id", "children[].parent", "children[].children"])
          expect(log).to be_empty
        end
      end
    end

    context "when nothing can be flattened" do
      it "returns no fields and reports the unresolvable $ref (E005)" do
        fields = extractor_for({}).call(ref("Missing"), "#/components/schemas/Missing")

        aggregate_failures do
          expect(fields).to eq([])
          expect(log.to_a.map(&:code)).to eq(%w[E005])
          expect(log.to_a.first.message).to eq("Unresolvable $ref #/components/schemas/Missing")
          expect(log.to_a.first.location).to eq("#/components/schemas/Missing")
        end
      end

      it "skips the member it cannot resolve and keeps the one it can" do
        schemas = { "Requisite" => { "oneOf" => [ref("Sbp"), ref("Gone")],
                                     "discriminator" => { "propertyName" => "type" } },
                    "Sbp" => { "type" => "object", "required" => %w[phone],
                               "properties" => { "phone" => { "type" => "string" } } } }

        aggregate_failures do
          expect(rows(fields_of(schemas, "Requisite"))).to eq([["phone", true, "sbp"]])
          expect(log.to_a.map(&:code)).to eq(%w[E005])
        end
      end

      it "returns no fields for a scalar schema" do
        expect(extractor_for({}).call({ "type" => "string" }, "#/s")).to eq([])
      end
    end
  end

  describe "#variants" do
    it "reads the values from the discriminator mapping (source 'discriminator')" do
      schemas = { "Requisite" => { "oneOf" => [ref("Sbp"), ref("Card")],
                                   "discriminator" => { "propertyName" => "type",
                                                        "mapping" => { "sbp" => "#/components/schemas/Sbp",
                                                                       "card" => "#/components/schemas/Card" } } },
                  "Sbp" => { "type" => "object" }, "Card" => { "type" => "object" } }

      expect(extractor_for(schemas).variants(ref("Requisite"), "#/components/schemas/Requisite"))
        .to eq({ discriminator_path: "type", values: %w[sbp card], source: "discriminator" })
    end

    it "falls back to the snake_cased component names when the discriminator has no mapping" do
      schemas = { "Requisite" => { "oneOf" => [ref("SbpRequisite"), ref("CardRequisite")],
                                   "discriminator" => { "propertyName" => "type" } },
                  "SbpRequisite" => { "type" => "object" }, "CardRequisite" => { "type" => "object" } }

      expect(extractor_for(schemas).variants(ref("Requisite"), "#/components/schemas/Requisite"))
        .to eq({ discriminator_path: "type", values: %w[sbp_requisite card_requisite], source: "discriminator" })
    end

    it "reports source 'one_of' with no discriminator path when nothing switches the branches" do
      schemas = { "Requisite" => { "oneOf" => [ref("SbpRequisite"), ref("CardRequisite")] },
                  "SbpRequisite" => { "type" => "object" }, "CardRequisite" => { "type" => "object" } }

      expect(extractor_for(schemas).variants(ref("Requisite"), "#/components/schemas/Requisite"))
        .to eq({ discriminator_path: nil, values: %w[sbp_requisite card_requisite], source: "one_of" })
    end

    it "reads anyOf as a composition too, not only oneOf" do
      schemas = { "Requisite" => { "anyOf" => [ref("Sbp"), ref("Card")],
                                   "discriminator" => { "propertyName" => "type" } },
                  "Sbp" => { "type" => "object" }, "Card" => { "type" => "object" } }

      expect(extractor_for(schemas).variants(ref("Requisite"), "#/components/schemas/Requisite"))
        .to eq({ discriminator_path: "type", values: %w[sbp card], source: "discriminator" })
    end

    it "finds a composition one level down and prefixes the discriminator with the property path" do
      schemas = { "Payout" => { "type" => "object",
                                "properties" => { "amount" => { "type" => "integer" },
                                                  "recipient" => ref("Requisite") } },
                  "Requisite" => { "oneOf" => [ref("Sbp"), ref("Card")],
                                   "discriminator" => { "propertyName" => "type" } },
                  "Sbp" => { "type" => "object" }, "Card" => { "type" => "object" } }

      expect(extractor_for(schemas).variants(ref("Payout"), "#/components/schemas/Payout"))
        .to eq({ discriminator_path: "recipient.type", values: %w[sbp card], source: "discriminator" })
    end

    it "numbers inline members, which have no component name to borrow" do
      schemas = { "Requisite" => { "oneOf" => [{ "type" => "object" }, { "type" => "object" }],
                                   "discriminator" => { "propertyName" => "type" } } }

      expect(extractor_for(schemas).variants(ref("Requisite"), "#/components/schemas/Requisite")[:values])
        .to eq(%w[0 1])
    end

    it "returns nil when the schema has no oneOf or anyOf anywhere" do
      schemas = { "Payout" => { "type" => "object", "properties" => { "amount" => { "type" => "integer" } } } }

      expect(extractor_for(schemas).variants(ref("Payout"), "#/components/schemas/Payout")).to be_nil
    end
  end

  describe "#if_then_rules" do
    it "reads a top-level if/then, taking the condition value from const" do
      schemas = { "Payout" => { "type" => "object",
                                "properties" => { "type" => { "type" => "string" },
                                                  "phone" => { "type" => "string" } },
                                "if" => { "properties" => { "type" => { "const" => "sbp" } } },
                                "then" => { "required" => %w[phone] } } }

      expect(extractor_for(schemas).if_then_rules(ref("Payout"), "#/components/schemas/Payout"))
        .to eq([{ path: "phone", when: "type", equals: "sbp" }])
    end

    it "finds every if/then that sits side by side inside allOf" do
      schemas = { "Payout" => { "allOf" => [
        { "type" => "object", "properties" => { "type" => { "type" => "string" },
                                                "phone" => { "type" => "string" },
                                                "pan" => { "type" => "string" } } },
        { "if" => { "properties" => { "type" => { "const" => "sbp" } } }, "then" => { "required" => %w[phone] } },
        { "if" => { "properties" => { "type" => { "enum" => %w[card] } } }, "then" => { "required" => %w[pan] } }
      ] } }

      expect(extractor_for(schemas).if_then_rules(ref("Payout"), "#/components/schemas/Payout"))
        .to eq([{ path: "phone", when: "type", equals: "sbp" },
                { path: "pan", when: "type", equals: "card" }])
    end

    it "emits one rule per field the branch requires, all under the same condition" do
      schemas = { "Payout" => { "type" => "object",
                                "properties" => { "type" => { "type" => "string" } },
                                "if" => { "properties" => { "type" => { "const" => "sbp" } } },
                                "then" => { "required" => %w[phone bank_code] } } }

      expect(extractor_for(schemas).if_then_rules(ref("Payout"), "#/components/schemas/Payout"))
        .to eq([{ path: "phone", when: "type", equals: "sbp" },
                { path: "bank_code", when: "type", equals: "sbp" }])
    end

    it "prefixes a rule nested in a property object with that property's path" do
      schemas = { "Payout" => { "type" => "object", "properties" => { "recipient" => ref("Recipient") } },
                  "Recipient" => { "type" => "object",
                                   "properties" => { "type" => { "type" => "string" },
                                                     "bank_code" => { "type" => "string" } },
                                   "if" => { "properties" => { "type" => { "const" => "sbp" } } },
                                   "then" => { "required" => %w[bank_code] } } }

      expect(extractor_for(schemas).if_then_rules(ref("Payout"), "#/components/schemas/Payout"))
        .to eq([{ path: "recipient.bank_code", when: "recipient.type", equals: "sbp" }])
    end

    it "ignores a rule whose condition pins no value or whose branch requires nothing" do
      schemas = { "Open" => { "type" => "object", "properties" => { "type" => { "type" => "string" } },
                              "if" => { "properties" => { "type" => { "type" => "string" } } },
                              "then" => { "required" => %w[phone] } },
                  "Loose" => { "type" => "object", "properties" => { "type" => { "type" => "string" } },
                               "if" => { "properties" => { "type" => { "const" => "sbp" } } },
                               "then" => { "description" => "then what?" } } }
      extractor = extractor_for(schemas)

      aggregate_failures do
        expect(extractor.if_then_rules(ref("Open"), "#/components/schemas/Open")).to eq([])
        expect(extractor.if_then_rules(ref("Loose"), "#/components/schemas/Loose")).to eq([])
      end
    end
  end

  describe "#schema_name" do
    it "returns the component name of a $ref and nil for an inline schema" do
      extractor = extractor_for({ "Payout" => { "type" => "object" } })

      aggregate_failures do
        expect(extractor.schema_name(ref("Payout"), "#/x")).to eq("Payout")
        expect(extractor.schema_name({ "type" => "object" }, "#/x")).to be_nil
      end
    end
  end
end
