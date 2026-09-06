# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Parser::Document do
  let(:log) { ProviderIntegrator::EventLog.new }
  let(:document) { described_class.new(root:, log:, spec_format: "3.0.3") }
  let(:idempotency_key) do
    { "name" => "Idempotency-Key", "in" => "header", "required" => false, "schema" => { "type" => "string" } }
  end
  let(:api_key_scheme) { { "type" => "apiKey", "in" => "header", "name" => "X-API-Key" } }
  let(:root) do
    { "openapi" => "3.0.3",
      1 => "a YAML mapping may be keyed by something other than a String",
      "x-space-payments-operation" => "create",
      "x-vendor" => { "team" => "integrations" },
      "info" => { "title" => "MiniPay Payout API", "version" => 1.0, "description" => "  Payouts for MiniPay.  " },
      "servers" => [{ "url" => "https://api.sandbox.minipay.example/v1", "description" => "Sandbox" },
                    "https://api.minipay.example/v1"],
      "security" => [{ "ApiKeyAuth" => [] }],
      "paths" => {
        "x-internal-note" => "paths may carry extensions",
        "/payouts" => {
          "summary" => "Payout collection",
          "parameters" => [{ "$ref" => "#/components/parameters/IdempotencyKey" },
                           { "name" => "trace_id", "in" => "header", "required" => false,
                             "schema" => { "type" => "string" } }],
          "post" => { "operationId" => "createPayout",
                      "parameters" => [{ "name" => "trace_id", "in" => "header", "required" => true,
                                         "schema" => { "type" => "string" } },
                                       { "name" => "dry_run", "in" => "query",
                                         "schema" => { "type" => "boolean" } }] },
          "get" => { "operationId" => "listPayouts" },
          "x-rate-limit" => 100
        },
        "/payouts/{payout_id}" => { "get" => { "operationId" => "getPayout" } },
        "/aliased" => { "$ref" => "#/components/pathItems/Aliased" },
        "/broken" => "not a mapping"
      },
      "components" => {
        "parameters" => { "IdempotencyKey" => idempotency_key },
        "pathItems" => { "Aliased" => { "delete" => { "operationId" => "cancelPayout" } } },
        "securitySchemes" => { "ApiKeyAuth" => api_key_scheme,
                               "LegacyApiKey" => { "$ref" => "#/components/securitySchemes/ApiKeyAuth" } }
      } }
  end

  describe "#operations" do
    it "returns every operation in document order with its verb and JSON pointer" do
      expect(document.operations.map { |operation| [operation.path, operation.verb, operation.pointer] })
        .to eq([["/payouts", "POST", "#/paths/~1payouts/post"],
                ["/payouts", "GET", "#/paths/~1payouts/get"],
                ["/payouts/{payout_id}", "GET", "#/paths/~1payouts~1{payout_id}/get"],
                ["/aliased", "DELETE", "#/paths/~1aliased/delete"]])
    end

    it "carries the operation node, the lowercase method and the path item, skipping non-method keys" do
      create = document.operations.first

      aggregate_failures do
        expect(create.http_method).to eq("post")
        expect(create.node).to be(root["paths"]["/payouts"]["post"])
        expect(create.path_item).to be(root["paths"]["/payouts"])
        expect(document.operations.map { |operation| operation.node["operationId"] })
          .to eq(%w[createPayout listPayouts getPayout cancelPayout])
        expect(log).to be_empty
      end
    end

    context "when paths is missing" do
      let(:root) { { "openapi" => "3.0.3" } }

      it "returns no operations and no path items" do
        aggregate_failures do
          expect(document.operations).to eq([])
          expect(document.path_items).to eq([])
          expect(log).to be_empty
        end
      end
    end

    context "when a method key does not carry an object" do
      let(:root) do
        { "paths" => { "/payouts" => { "post" => "createPayout", "get" => { "operationId" => "listPayouts" } } } }
      end

      it "skips it silently instead of building an operation without a node" do
        aggregate_failures do
          expect(document.operations.map { |operation| [operation.verb, operation.pointer] })
            .to eq([["GET", "#/paths/~1payouts/get"]])
          expect(log).to be_empty
        end
      end
    end
  end

  describe "#path_items" do
    it "keeps only keys that address a path and resolves a $ref path item" do
      aggregate_failures do
        expect(document.path_items.map(&:first)).to eq(["/payouts", "/payouts/{payout_id}", "/aliased"])
        expect(document.path_items.last.last).to eq({ "delete" => { "operationId" => "cancelPayout" } })
      end
    end
  end

  describe "#parameters_for" do
    it "merges path-item and operation parameters, the operation winning on the same name and location" do
      merged = document.parameters_for(document.operations.first)

      aggregate_failures do
        expect(merged.map { |node, _| [node["name"], node["in"]] })
          .to eq([%w[Idempotency-Key header], %w[trace_id header], %w[dry_run query]])
        expect(merged.map(&:last)).to eq(["#/components/parameters/IdempotencyKey",
                                          "#/paths/~1payouts/post/parameters/0",
                                          "#/paths/~1payouts/post/parameters/1"])
        expect(merged[1].first["required"]).to be(true)
      end
    end

    it "gives an operation without parameters of its own the path-item ones, at their own pointers" do
      merged = document.parameters_for(document.operations[1])

      aggregate_failures do
        expect(merged.map { |node, _| node["name"] }).to eq(%w[Idempotency-Key trace_id])
        expect(merged.map(&:last)).to eq(["#/components/parameters/IdempotencyKey",
                                          "#/paths/~1payouts/parameters/1"])
        expect(merged.first.first).to eq(idempotency_key)
      end
    end

    it "returns an empty list when neither the operation nor its path item declares parameters" do
      expect(document.parameters_for(document.operations.last)).to eq([])
    end

    context "when parameters is not a list" do
      let(:root) do
        { "paths" => { "/payouts" => { "parameters" => { "name" => "trace_id" },
                                       "post" => { "parameters" => "Idempotency-Key" } } } }
      end

      it "ignores it rather than reading the mapping as one parameter" do
        aggregate_failures do
          expect(document.parameters_for(document.operations.first)).to eq([])
          expect(log).to be_empty
        end
      end
    end

    context "when a parameter $ref cannot be resolved" do
      let(:root) do
        { "paths" => { "/payouts" => { "post" => { "parameters" => [
          { "$ref" => "#/components/parameters/Absent" },
          { "name" => "dry_run", "in" => "query" }
        ] } } } }
      end

      it "drops the parameter and reports E005 at the pointer of the reference" do
        merged = document.parameters_for(document.operations.first)

        aggregate_failures do
          expect(merged.map { |node, _| node["name"] }).to eq(["dry_run"])
          expect(log.to_a.map(&:code)).to eq(["E005"])
          expect(log.to_a.first.location).to eq("#/paths/~1payouts/post/parameters/0")
        end
      end
    end
  end

  describe "#security_schemes" do
    it "dereferences every scheme and keeps the declaration order" do
      aggregate_failures do
        expect(document.security_schemes.keys).to eq(%w[ApiKeyAuth LegacyApiKey])
        expect(document.security_schemes["ApiKeyAuth"]).to eq(api_key_scheme)
        expect(document.security_schemes["LegacyApiKey"]).to eq(api_key_scheme)
        expect(log).to be_empty
      end
    end

    context "when a scheme cannot be dereferenced" do
      let(:root) do
        { "components" => { "securitySchemes" => { "GhostAuth" => { "$ref" => "#/components/securitySchemes/Absent" },
                                                   "ApiKeyAuth" => { "type" => "apiKey" } } } }
      end

      it "drops the scheme and reports E005 at its pointer" do
        aggregate_failures do
          expect(document.security_schemes).to eq({ "ApiKeyAuth" => { "type" => "apiKey" } })
          expect(log.to_a.map(&:code)).to eq(["E005"])
          expect(log.to_a.first.location).to eq("#/components/securitySchemes/GhostAuth")
        end
      end
    end

    context "when the document declares no components" do
      let(:root) { { "openapi" => "3.0.3" } }

      it "returns no schemes and an empty components object" do
        aggregate_failures do
          expect(document.security_schemes).to eq({})
          expect(document.components).to eq({})
          expect(document.global_security).to eq([])
        end
      end
    end
  end

  describe "#servers" do
    it "keeps the declared order and drops entries that are not objects" do
      expect(document.servers).to eq([{ "url" => "https://api.sandbox.minipay.example/v1",
                                        "description" => "Sandbox" }])
    end

    context "when servers is absent" do
      let(:root) { { "openapi" => "3.0.3" } }

      it "returns an empty list" do
        expect(document.servers).to eq([])
      end
    end
  end

  describe "#extensions" do
    it "returns the root-level x- keys unchanged, ignoring keys that are not Strings" do
      expect(document.extensions).to eq({ "x-space-payments-operation" => "create",
                                          "x-vendor" => { "team" => "integrations" } })
    end
  end

  describe "#info" do
    it "reads the info object, stringifying the version and stripping the description" do
      aggregate_failures do
        expect(document.title).to eq("MiniPay Payout API")
        expect(document.version).to eq("1.0")
        expect(document.description).to eq("Payouts for MiniPay.")
        expect(document.info["title"]).to eq("MiniPay Payout API")
        expect(document.global_security).to eq([{ "ApiKeyAuth" => [] }])
        expect(document.spec_format).to eq("3.0.3")
      end
    end

    it "treats an info that is not an object as absent" do
      other = described_class.new(root: { "openapi" => "3.0.3", "info" => "MiniPay Payout API" }, log:,
                                  spec_format: "3.0.3")

      aggregate_failures do
        expect(other.info).to eq({})
        expect(other.title).to be_nil
        expect(other.version).to be_nil
        expect(other.description).to be_nil
      end
    end

    context "when info is absent or blank" do
      let(:root) { { "openapi" => "3.0.3", "info" => { "description" => "   " } } }

      it "returns nil for the missing pieces rather than an empty String" do
        aggregate_failures do
          expect(document.info).to eq({ "description" => "   " })
          expect(document.title).to be_nil
          expect(document.version).to be_nil
          expect(document.description).to be_nil
        end
      end
    end
  end

  describe "#deref" do
    it "resolves a reference against the document root and names the component" do
      resolved = document.deref({ "$ref" => "#/components/parameters/IdempotencyKey" }, "#/x")

      aggregate_failures do
        expect(resolved.node).to eq(idempotency_key)
        expect(resolved.pointer).to eq("#/components/parameters/IdempotencyKey")
        expect(resolved.schema_name).to eq("IdempotencyKey")
        expect(document.node_at({ "$ref" => "#/components/parameters/IdempotencyKey" }, "#/x")).to eq(idempotency_key)
        expect(document.root).to be(root)
      end
    end
  end
end
