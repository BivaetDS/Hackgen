# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Models::Base do
  let(:models) { ProviderIntegrator::Models }

  describe ".from_h" do
    it "accepts String and Symbol keys interchangeably" do
      from_strings = models::Server.from_h({ "url" => "https://x", "description" => nil, "environment" => "sandbox" })
      from_symbols = models::Server.from_h({ url: "https://x", description: nil, environment: "sandbox" })

      expect(from_strings).to eq(from_symbols)
    end

    it "rejects unknown keys" do
      expect { models::Server.from_h({ url: "u", description: nil, environment: "x", extra: 1 }) }
        .to raise_error(ArgumentError, /unknown keys \[extra\]/)
    end

    it "rejects missing keys (absent keys are not part of the canonical form)" do
      expect { models::Server.from_h({ url: "u" }) }
        .to raise_error(ArgumentError, /missing keys \[description, environment\]/)
    end

    it "rejects non-Hash input and non-Array lists" do
      aggregate_failures do
        expect { models::Server.from_h([]) }.to raise_error(ArgumentError, /expects a Hash/)
        expect do
          models::Response.from_h(http: 200, description: nil, schema_name: nil, kind: "success",
                                  content_type: nil, example: nil, headers: nil)
        end
          .to raise_error(ArgumentError, /headers must be an Array/)
      end
    end

    it "builds nested models and leaves nil nested members nil" do
      header = { name: "Retry-After", type: "integer", description: nil, canonical: "retry_after" }
      response = models::Response.from_h(http: 429, description: "d", schema_name: "E", kind: "error",
                                         content_type: "a/j", example: nil, headers: [header])

      expect(response.headers.first).to eq(models::ResponseHeader.new(name: "Retry-After", type: "integer",
                                                                      description: nil, canonical: "retry_after"))
      expect(models::FieldMapping.nested_members.keys).to eq(%i[conversion conditional_required branch])
    end
  end

  describe "#to_h" do
    it "returns a deep plain Hash with String keys, converting nested models and Symbol-keyed hashes" do
      event = models::Event.new(code: "I101", level: "info", message: "m", location: nil, details: { kind: :create })
      result = event.to_h

      expect(result).to eq({ "code" => "I101", "level" => "info", "message" => "m", "location" => nil,
                             "details" => { "kind" => :create } })
      expect(result.keys).to all(be_a(String))
    end
  end

  describe "#to_canonical_json" do
    it "serializes through JsonCanon" do
      server = models::Server.new(url: "u", description: nil, environment: "unknown")

      expect(server.to_canonical_json)
        .to eq("{\n  \"description\": null,\n  \"environment\": \"unknown\",\n  \"url\": \"u\"\n}\n")
    end
  end
end
