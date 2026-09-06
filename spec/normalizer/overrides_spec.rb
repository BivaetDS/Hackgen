# frozen_string_literal: true

require "tmpdir"

RSpec.describe ProviderIntegrator::Normalizer::Overrides do
  let(:log) { ProviderIntegrator::EventLog.new }
  let(:dir) { Dir.mktmpdir("provider-integrator-overrides") }
  let(:path) { File.join(dir, "overrides.yml") }

  after { FileUtils.rm_rf(dir) }

  def overrides_for(yaml)
    ProviderIntegrator::Files.write(path, yaml)
    described_class.load(path:, log:)
  end

  describe ".load with every documented section" do
    subject(:overrides) { overrides_for(yaml) }

    let(:yaml) do
      <<~YAML
        operations:
          createPayout: create
        amount_unit:
          CreatePayoutRequest.amount: minor
        required_if:
          - field: recipient.bank_code
            when: recipient.type
            equals: sbp
        signature:
          header: X-Sign
          algorithm: hmac-sha512
          encoding: hex
          message: raw_body
        status_map:
          processing: in_progress
        error_actions:
          bank_unavailable: retry_later
      YAML
    end

    # Every reader, in the order the pipeline calls them.
    def applied_values(hints)
      [hints.kind_for("createPayout"), hints.amount_unit("CreatePayoutRequest", "amount"),
       hints.required_if("recipient.bank_code"), hints.signature, hints.status_for("processing"),
       hints.record_error_action("bank_unavailable")]
    end

    it "hands each analyzer the value the file pins" do
      expect(applied_values(overrides)).to eq(
        ["create", "minor", { when: "recipient.type", equals: "sbp" },
         { location: "header", name: "X-Sign", algorithm: "hmac-sha512", encoding: "hex", message: "raw_body" },
         "in_progress", "retry_later"]
      )
    end

    it "records every hit as an OverrideApplied in application order" do
      applied_values(overrides)

      expect(overrides.applied.map(&:to_h)).to eq(
        [{ "key" => "operations", "target" => "createPayout", "value" => "create", "note" => nil },
         { "key" => "amount_unit", "target" => "CreatePayoutRequest.amount", "value" => "minor", "note" => nil },
         { "key" => "required_if", "target" => "recipient.bank_code", "note" => nil,
           "value" => { "equals" => "sbp", "when" => "recipient.type" } },
         { "key" => "signature", "target" => "X-Sign", "note" => nil,
           "value" => { "algorithm" => "hmac-sha512", "encoding" => "hex", "location" => "header",
                        "message" => "raw_body", "name" => "X-Sign" } },
         { "key" => "status_map", "target" => "processing", "value" => "in_progress", "note" => nil },
         { "key" => "error_actions", "target" => "bank_unavailable", "value" => "retry_later", "note" => nil }]
      )
    end

    it "reports every hit as I601 so the report shows what was not inferred" do
      applied_values(overrides)

      expect(log.with_code("I601").map(&:message)).to eq(
        ["Override operations applied to createPayout: create",
         "Override amount_unit applied to CreatePayoutRequest.amount: minor",
         "Override required_if applied to recipient.bank_code: equals -> sbp, when -> recipient.type",
         "Override signature applied to X-Sign: algorithm -> hmac-sha512, encoding -> hex, location -> header, " \
         "message -> raw_body, name -> X-Sign",
         "Override status_map applied to processing: in_progress",
         "Override error_actions applied to bank_unavailable: retry_later"]
      )
    end

    it "declares the error actions as written and is not empty" do
      aggregate_failures do
        expect(overrides.error_actions).to eq("bank_unavailable" => "retry_later")
        expect(overrides.empty?).to be(false)
      end
    end

    it "returns nil and records nothing for a target the file does not mention" do
      values = [overrides.kind_for("getBalance"), overrides.amount_unit("BalanceResponse", "balance"),
                overrides.required_if("recipient.card_number"), overrides.status_for("completed"),
                overrides.record_error_action("internal_error")]

      aggregate_failures do
        expect(values).to eq([nil, nil, nil, nil, nil])
        expect(overrides.applied).to be_empty
        expect(log).to be_empty
      end
    end
  end

  describe ".load on the other shapes the schema allows" do
    it "pins a body signature by field and leaves what it does not say to the analyzer" do
      overrides = overrides_for("signature:\n  field: sign\n  algorithm: hmac-md5\n")

      expect(overrides.signature).to eq(location: "body", name: "sign", algorithm: "hmac-md5")
    end

    it "reads a non-string equals as the string the analyzer compares against" do
      overrides = overrides_for("required_if:\n  - field: recipient.inn\n    when: resident\n    equals: false\n")

      expect(overrides.required_if("recipient.inn")).to eq(when: "resident", equals: "false")
    end
  end

  describe ".load on a file the schema rejects" do
    it "reports E001 when the signature pins both a header and a field" do
      overrides = overrides_for("signature:\n  header: X-Sign\n  field: sign\n")

      aggregate_failures do
        expect(log.include?("E001")).to be(true)
        expect(overrides.signature).to be_nil
        expect(overrides.empty?).to be(true)
      end
    end

    it "reports E001 with the offending pointer and applies nothing" do
      overrides = overrides_for("operations:\n  createPayout: reconcile\n")

      aggregate_failures do
        expect(log.with_code("E001").map { |event| event.details["reason"] })
          .to all(start_with("overrides #{path}: ").and(include("/operations/createPayout")))
        expect(overrides.kind_for("createPayout")).to be_nil
        expect(overrides.empty?).to be(true)
        expect(overrides.applied).to be_empty
      end
    end

    it "reports E001 for a key that is not part of the fixed set" do
      overrides = overrides_for("amount_units:\n  CreatePayoutRequest.amount: minor\n")

      aggregate_failures do
        expect(log.include?("E001")).to be(true)
        expect(overrides.empty?).to be(true)
      end
    end

    it "reports E001 when the file is not a mapping" do
      overrides = overrides_for("- createPayout\n")

      aggregate_failures do
        expect(log.with_code("E001").map { |event| event.details["reason"] })
          .to eq(["overrides #{path} is not a mapping"])
        expect(overrides.empty?).to be(true)
      end
    end

    it "reports E001 instead of raising when the file is missing" do
      described_class.load(path: File.join(dir, "absent.yml"), log:)

      expect(log.with_code("E001").first.details["reason"]).to start_with("overrides #{File.join(dir, "absent.yml")}")
    end
  end

  describe ".load without a path" do
    subject(:overrides) { described_class.load(path: nil, log:) }

    it "is an empty, silent set of hints" do
      aggregate_failures do
        expect(overrides.empty?).to be(true)
        expect(overrides.applied).to be_empty
        expect(overrides.signature).to be_nil
        expect(overrides.error_actions).to eq({})
        expect(overrides.kind_for("createPayout")).to be_nil
        expect(log).to be_empty
      end
    end
  end
end
