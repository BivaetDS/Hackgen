# frozen_string_literal: true

# The five dictionaries are the only home of domain knowledge; their JSON schemas pin the shape
# and the canon enums, and the checks below keep the dictionaries consistent with each other and
# with the value domains of the IR schema (docs/IR_CONTRACT.md).
RSpec.describe "dictionaries against their schemas" do
  let(:dictionaries) { ProviderIntegrator::Dictionaries }
  let(:schemas) { ProviderIntegrator::Schemas }
  let(:canon) { dictionaries.canonical_contract }
  let(:ir_schema) { schemas.load(:provider_spec) }

  def ir_enum(name)
    ir_schema.fetch("$defs").fetch(name).fetch("enum")
  end

  def dictionary_enum(schema_name, definition)
    schemas.load(schema_name).fetch("$defs").fetch(definition).fetch("enum")
  end

  ProviderIntegrator::Dictionaries::NAMES.each do |name|
    describe "#{name}.yml" do
      it "loads with Psych.safe_load_file and validates against #{name}.schema.json" do
        data = Psych.safe_load_file(dictionaries.path(name), permitted_classes: [Symbol])

        expect(schemas.errors(name, data)).to eq([])
      end
    end
  end

  it "reports no errors from Schemas.dictionary_errors (rake lint:dictionaries)" do
    expect(schemas.dictionary_errors).to eq(dictionaries::NAMES.to_h { |name| [name, []] })
  end

  describe "errors.yml vs canonical_contract.yml" do
    let(:errors) { dictionaries.errors }
    let(:code_mappings) { errors["http"].values + errors["provider_codes"] }
    let(:guard) { errors["http_guard"] }

    it "uses only actions declared in canonical_contract.yml" do
      expect(canon["actions"].keys).to include(*code_mappings.map { |mapping| mapping["action"] }.uniq)
    end

    it "uses only canonical error codes declared in canonical_contract.yml" do
      expect(canon["error_codes"].keys).to include(*code_mappings.map { |mapping| mapping["canonical"] }.uniq)
    end

    it "keeps the error-code and action enums of errors.schema.json equal to the canon" do
      aggregate_failures do
        expect(dictionary_enum(:errors, "canonicalErrorCode")).to match_array(canon["error_codes"].keys)
        expect(dictionary_enum(:errors, "action")).to match_array(canon["actions"].keys)
      end
    end

    it "names every provider_codes entry uniquely" do
      names = errors["provider_codes"].map { |entry| entry["name"] }

      expect(names).to eq(names.uniq)
    end

    it "guards only transport statuses whose HTTP default retries, against actions the canon calls final" do
      default_action = lambda do |status|
        mapping = errors["http"].fetch(status) { errors["http"].fetch("default_#{status[0]}xx") }
        canon["actions"].fetch(mapping["action"])
      end

      aggregate_failures do
        expect(canon["actions"].keys).to include(*guard["terminal_actions"])
        expect(guard["terminal_actions"].map { |action| canon["actions"].dig(action, "retry") }).to all(be(false))
        expect(guard["statuses"].map { |status| default_action.call(status)["retry"] }).to all(be(true))
      end
    end
  end

  describe "operations.yml vs canonical_contract.yml" do
    let(:operations) { dictionaries.operations }
    let(:kinds) { operations["kinds"] }

    it "keeps in_contract, structural and synonym kinds within kinds" do
      aggregate_failures do
        expect(kinds).to include(*operations["in_contract"])
        expect(kinds).to include(*operations["structural"].keys)
        expect(operations["synonyms"].keys).to match_array(kinds)
      end
    end

    it "matches the kinds enum of provider_spec.schema.json (kinds plus unknown)" do
      aggregate_failures do
        expect(ir_enum("kind")).to eq(kinds + ["unknown"])
        expect(dictionary_enum(:operations, "kind")).to eq(kinds)
        expect(ir_schema.dig("$defs", "Classification", "properties", "scores", "required")).to eq(kinds)
      end
    end

    it "maps contract_roles exactly onto the in_contract kinds" do
      expect(canon["contract_roles"].keys).to match_array(operations["in_contract"])
    end

    it "maps extra_methods exactly onto the kinds outside the contract" do
      expect(canon["extra_methods"].keys).to match_array(kinds - operations["in_contract"])
    end

    it "names contract methods declared in base_service.methods" do
      expect(canon["base_service"]["methods"]).to include(*canon["contract_roles"].values)
    end

    it "orders the thresholds so unknown < low confidence and the structural-only cap stays below full confidence" do
      thresholds = operations["thresholds"]

      aggregate_failures do
        expect(thresholds["unknown_below"]).to be < thresholds["low_confidence_below"]
        expect(thresholds["structural_only_cap"]).to be < 1.0
      end
    end
  end

  describe "statuses.yml vs canonical_contract.yml" do
    let(:statuses) { dictionaries.statuses }

    it "declares the same canonical statuses as the canon, in the same order" do
      expect(statuses["canonical"]).to eq(canon["statuses"])
    end

    it "agrees with the canon on the default status" do
      expect(statuses["default"]).to eq(canon["default_status"])
    end

    it "has synonym and description_words sections for exactly the canonical statuses" do
      aggregate_failures do
        expect(statuses["synonyms"].keys).to match_array(canon["statuses"])
        expect(statuses["description_words"].keys).to match_array(canon["statuses"])
        expect(canon["statuses"]).to include(*statuses["numeric"].values.uniq)
      end
    end

    it "checks description words in the documented order: negations first, then approved, then in_progress" do
      expect(statuses["description_words"].keys).to eq(%w[rejected approved in_progress])
    end

    it "matches the canonical status enum of provider_spec.schema.json" do
      aggregate_failures do
        expect(ir_enum("canonicalStatus")).to eq(canon["statuses"])
        expect(dictionary_enum(:statuses, "canonicalStatus")).to eq(canon["statuses"])
      end
    end

    it "does not map one provider status to two canonical statuses" do
      all_synonyms = statuses["synonyms"].values.flatten

      expect(all_synonyms).to eq(all_synonyms.uniq)
    end
  end

  describe "canonical_contract.yml vs provider_spec.schema.json" do
    it "keeps the canonical error codes and actions equal to the IR enums" do
      aggregate_failures do
        expect(ir_enum("canonicalErrorCode")).to eq(canon["error_codes"].keys)
        expect(ir_enum("action")).to eq(canon["actions"].keys)
      end
    end

    it "uses signature defaults the IR Signature model accepts" do
      signature = ir_schema.dig("$defs", "Signature", "properties")
      defaults = canon["signature_defaults"]

      aggregate_failures do
        expect(signature.dig("algorithm", "enum")).to include(defaults["algorithm"])
        expect(signature.dig("encoding", "enum")).to include(defaults["encoding"])
        expect(signature.dig("message", "enum")).to include(defaults["message"])
        expect(defaults["secret"]).to eq(canon["credentials"]["callback_secret"])
      end
    end

    it "declares credentials for every authentication type that needs them" do
      needing_credentials = ir_enum("authType") - %w[none unknown]

      expect(canon["credentials"].keys).to include(*needing_credentials)
    end

    it "has gateway templates for exactly the directions the IR allows" do
      directions = ir_schema.dig("$defs", "GatewayConfig", "properties", "direction", "enum")

      aggregate_failures do
        expect(canon["gateway_config"].keys).to match_array(directions)
        expect(dictionaries.operations["direction"].keys - ["default"]).to match_array(directions)
        expect(directions).to include(dictionaries.operations["direction"]["default"])
      end
    end

    it "returns failures only through the four symbols the BaseService contract knows" do
      failures = (canon["error_codes"].values + canon["service_codes"].values).map { |code| code["failure"] }.uniq

      aggregate_failures do
        expect(dictionary_enum(:canonical_contract, "failureSymbol"))
          .to match_array(%w[unprocessable_entity unauthorized too_many_requests provider_error])
        expect(dictionary_enum(:canonical_contract, "failureSymbol")).to include(*failures)
      end
    end

    it "sends every request-body media type through a keyword the client helpers accept" do
      client = canon["helpers"]["client"]
      keywords = [client["post"], client["post_form"]].flat_map { |call| call.scan(/(\w+):/).flatten }

      expect(keywords).to include(*client["content_types"].values.uniq)
    end
  end

  describe "fields.yml" do
    let(:fields) { dictionaries.fields }
    let(:canonical) { fields["canonical"] }
    let(:containers) { canonical.select { |_, entry| entry["container"] } }

    it "gives every container a children list and children only to containers" do
      canonical.each do |name, entry|
        expect(entry.key?("children")).to eq(entry["container"] == true), "#{name}: container/children mismatch"
      end
    end

    it "maps no field name to two top-level canonical fields" do
      all_synonyms = canonical.values.flat_map { |entry| entry["synonyms"] }

      expect(all_synonyms).to eq(all_synonyms.uniq)
    end

    it "keeps flat requisite/error fields within the children of their container" do
      aggregate_failures do
        expect(containers["requisite"]["children"].keys).to include(*fields["flat"]["requisite"].keys)
        expect(containers["error"]["children"].keys).to include(*fields["flat"]["error"].keys)
        expect(containers["error"]["children"].keys).to include(*fields["flat"]["error_context"].keys)
      end
    end

    it "hands the provider-id names to external_id in request bodies, where provider_operation_id is out of scope" do
      provider_id = canonical["provider_operation_id"]

      aggregate_failures do
        expect(provider_id["synonyms"]).to include(*canonical["external_id"]["request_synonyms"])
        expect(provider_id["scope"]).not_to include("request")
      end
    end

    it "agrees with canonical_contract.yml on the credentials key of merchant_account" do
      expect(canonical["merchant_account"]["credentials_key"]).to eq(canon["credentials"]["merchant_account"])
    end

    it "declares the webhook and parameter roles the IR schema knows" do
      aggregate_failures do
        expect(ir_schema.dig("$defs", "Parameter", "properties", "canonical", "enum"))
          .to include(*fields["parameters"].keys)
        expect(fields["webhook"].keys).to eq(%w[event_field status_field signature_field])
        expect(canonical["status"]["synonyms"]).to include(*fields["webhook"]["status_field"])
      end
    end

    it "lists in the IR canonicalField enum exactly the names it can produce, with a fallback only for containers" do
      produced = canonical.flat_map do |name, entry|
        [name] + (entry["children"] || {}).keys.map { |child| "#{name}.#{child}" }
      end
      canonical_field = schemas.schema(:provider_spec).ref("#/$defs/canonicalField")
      fallback = ->(name) { canonical_field.valid?("#{name}.zzz_unlisted") }

      aggregate_failures do
        expect(ir_schema.dig("$defs", "canonicalField", "anyOf", 0, "enum")).to match_array(produced)
        expect(containers.keys.map(&fallback)).to all(be(true))
        expect((canonical.keys - containers.keys).map(&fallback)).to all(be(false))
        expect(canonical_field.valid?(nil)).to be(true)
      end
    end

    it "keeps the money-unit thresholds reachable with the declared weights" do
      minor = fields["money_units"]["minor"]
      major = fields["money_units"]["major"]

      aggregate_failures do
        expect(minor["description_weight"] + minor["error_example_weight"] + minor["minimum_weight"])
          .to be >= fields["money_units"]["minor_threshold"]
        expect(major["description_weight"] + major["format_weight"] + major["pattern_weight"] +
               major["multiple_of_fraction_weight"] + major["string_type_weight"])
          .to be >= fields["money_units"]["major_threshold"]
      end
    end
  end
end
