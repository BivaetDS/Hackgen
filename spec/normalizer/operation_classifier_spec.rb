# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Normalizer::OperationClassifier do
  subject(:classifier) { described_class.new }

  let(:kinds) { ProviderIntegrator::Dictionaries.operations.fetch("kinds") }
  let(:thresholds) { ProviderIntegrator::Normalizer::Confidence.thresholds }

  # The classifier reads only these fields of an operation, so a bare OperationRef is enough.
  def operation_ref(path:, http_method: "post", node: {})
    pointer = ProviderIntegrator::Parser::Pointer.build("paths", path, http_method)
    ProviderIntegrator::Parser::Document::OperationRef.new(path:, http_method:, node:, pointer:, path_item: {})
  end

  def classify(path:, operation_id: nil, http_method: "post", has_body: false, node: {})
    classifier.call(operation: operation_ref(path:, http_method:, node:), operation_id:, has_body:)
  end

  # The scores Hash the IR expects: every kind of operations.yml, zeros included.
  def scores(**awarded)
    kinds.to_h { |kind| [kind, awarded[kind.to_sym] || 0] }
  end

  describe "the NovaPay spec" do
    let(:log) { ProviderIntegrator::EventLog.new }
    let(:document) do
      ProviderIntegrator::Parser::Document.new(root: novapay_openapi_hash, log:, spec_format: "3.0.3")
    end
    let(:expected) { novapay_ir_hash["operations"] }
    let(:verdicts) do
      document.operations.map do |ref|
        classifier.call(operation: ref, operation_id: ref.node["operationId"], has_body: body?(ref))
      end
    end

    def body?(ref)
      pointer = ProviderIntegrator::Parser::Pointer.join(ref.pointer, "requestBody")
      node = document.deref(ref.node["requestBody"], pointer).node
      node.is_a?(Hash) && node["content"].is_a?(Hash) && !node["content"].empty?
    end

    it "classifies all five operations exactly as the IR fixture records" do
      expect(verdicts.map { |verdict| [verdict.kind, verdict.confidence] })
        .to eq([["create", 0.9], ["status", 0.9], ["cancel", 0.9], ["webhook", 0.92], ["balance", 0.9]])
    end

    it "reproduces the scores, evidence and source of the IR fixture" do
      actual = verdicts.map do |verdict|
        { "confidence" => verdict.confidence, "evidence" => verdict.evidence, "scores" => verdict.scores,
          "source" => verdict.source }
      end

      expect(actual).to eq(expected.map { |operation| operation["classification"] })
    end

    it "scores every one of the seven kinds, zeros included" do
      aggregate_failures do
        expect(kinds).to eq(%w[create status cancel balance webhook refund list])
        expect(verdicts.map { |verdict| verdict.scores.keys }).to all(eq(kinds))
        expect(verdicts.first.scores).to eq(scores(create: 9))
      end
    end

    it "names the signals of the webhook operation in source order" do
      webhook = verdicts.find { |verdict| verdict.kind == "webhook" }

      aggregate_failures do
        expect(webhook.evidence).to eq(["operationId token 'webhook' -> webhook (+5)",
                                        "path token 'webhooks' -> webhook (+3)",
                                        "tag 'Webhooks' -> webhook (+2)",
                                        "text 'webhook' -> webhook (+1)"])
        expect(webhook.scores).to eq(scores(webhook: 11))
      end
    end
  end

  describe "#call" do
    context "with a weak operationId stem" do
      it "counts it when the same kind also has a structural signal" do
        verdict = classify(operation_id: "payout", path: "/v1/operations", has_body: true)

        aggregate_failures do
          expect(verdict.kind).to eq("create")
          expect(verdict.scores).to eq(scores(create: 5))
          expect(verdict.confidence).to eq(0.83)
          expect(verdict.evidence).to eq(["operationId token 'payout' -> create (+2)",
                                          "structure POST with body and no path id -> create (+3)"])
        end
      end

      it "ignores it without a structural or path signal for that kind" do
        verdict = classify(operation_id: "payoutRequest", path: "/payouts/{payout_id}/confirm", has_body: true)

        aggregate_failures do
          expect(verdict.scores).to eq(scores)
          expect(verdict.kind).to eq("unknown")
          expect(verdict.evidence).to be_empty
        end
      end

      it "ignores it once any kind matched a strong stem" do
        verdict = classify(operation_id: "webhookPayout", path: "/payouts", has_body: true)

        aggregate_failures do
          expect(verdict.kind).to eq("webhook")
          expect(verdict.scores).to eq(scores(webhook: 5, create: 3))
          expect(verdict.evidence).to eq(["operationId token 'webhook' -> webhook (+5)"])
        end
      end
    end

    context "with exclude_tokens" do
      it "scores a state token as status" do
        verdict = classify(operation_id: "fetchState", path: "/machines/state", http_method: "get")

        aggregate_failures do
          expect(verdict.kind).to eq("status")
          expect(verdict.scores).to eq(scores(status: 8))
          expect(verdict.evidence).to eq(["operationId token 'state' -> status (+5)",
                                          "path token 'state' -> status (+3)"])
        end
      end

      it "never lets statement match the state stem of status" do
        verdict = classify(operation_id: "fetchStatement", path: "/machines/statement", http_method: "get")

        aggregate_failures do
          expect(verdict.scores).to eq(scores)
          expect(verdict.kind).to eq("unknown")
          expect(verdict.confidence).to eq(0.0)
        end
      end
    end

    context "with a webhook exclude_operation_id_token" do
      it "classifies an incoming notification as webhook" do
        verdict = classify(operation_id: "payoutWebhook", path: "/webhooks/payout", has_body: true)

        aggregate_failures do
          expect(verdict.kind).to eq("webhook")
          expect(verdict.scores).to eq(scores(webhook: 8))
        end
      end

      it "zeroes every webhook point of registerWebhook, a webhook management call" do
        verdict = classify(operation_id: "registerWebhook", path: "/webhooks", has_body: true)

        aggregate_failures do
          expect(verdict.scores).to eq(scores)
          expect(verdict.kind).to eq("unknown")
          expect(verdict.evidence).to be_empty
        end
      end
    end

    context "when the request shape is the only signal" do
      it "caps the confidence at thresholds.structural_only_cap" do
        verdict = classify(operation_id: nil, path: "/v1/operations", has_body: true)

        aggregate_failures do
          expect(verdict.kind).to eq("create")
          expect(verdict.scores).to eq(scores(create: 3))
          expect(verdict.structural_only).to be(true)
          expect(verdict.confidence).to eq(0.5)
          expect(verdict.confidence).to eq(thresholds.fetch("structural_only_cap"))
        end
      end

      it "reads a DELETE with a path id as cancel and a bare GET as list" do
        cancel = classify(operation_id: nil, path: "/operations/{id}", http_method: "delete")
        listing = classify(operation_id: nil, path: "/operations", http_method: "get")

        aggregate_failures do
          expect(cancel.kind).to eq("cancel")
          expect(cancel.scores).to eq(scores(cancel: 3))
          expect(cancel.evidence).to eq(["structure DELETE with path id -> cancel (+3)"])
          expect(listing.kind).to eq("list")
          expect(listing.scores).to eq(scores(list: 3))
          expect(listing.evidence).to eq(["structure GET without path id -> list (+3)"])
          expect([cancel.confidence, listing.confidence]).to eq([0.5, 0.5])
        end
      end

      it "keeps the shape rule away from the paths excluded_path_stems names" do
        listing = classify(operation_id: nil, path: "/statements", http_method: "get")
        created = classify(operation_id: nil, path: "/auth/token", has_body: true)

        aggregate_failures do
          expect(listing.scores).to eq(scores)
          expect(listing.kind).to eq("unknown")
          expect(created.scores).to eq(scores)
          expect(created.kind).to eq("unknown")
        end
      end
    end

    context "with a tag" do
      it "lets a tag introduce a kind and scores only the first tag that names it" do
        verdict = classify(operation_id: "doThing", path: "/things",
                           node: { "tags" => ["Balance", "Balance Funds"] })

        aggregate_failures do
          expect(verdict.kind).to eq("balance")
          expect(verdict.scores).to eq(scores(balance: 2))
          expect(verdict.evidence).to eq(["tag 'Balance' -> balance (+2)"])
          expect(verdict.confidence).to eq(0.67)
        end
      end
    end

    context "when free text is the only signal" do
      it "confirms a scored kind but never introduces one" do
        node = { "summary" => "Создать выплату",
                 "description" => "Отменить" }
        verdict = classify(operation_id: "doThing", path: "/things/{id}/apply", http_method: "put",
                           has_body: true, node:)

        aggregate_failures do
          expect(verdict.scores).to eq(scores)
          expect(verdict.kind).to eq("unknown")
          expect(verdict.evidence).to be_empty
        end
      end
    end

    context "when two kinds tie for the lead" do
      it "refuses to decide and reports every signal it saw" do
        verdict = classify(operation_id: "refundCancel", path: "/operations/{id}", has_body: true)

        aggregate_failures do
          expect(verdict.kind).to eq("unknown")
          expect(verdict.confidence).to eq(0.0)
          expect(verdict.scores).to eq(scores(cancel: 5, refund: 5))
          expect(verdict.evidence).to eq(["operationId token 'cancel' -> cancel (+5)",
                                          "operationId token 'refund' -> refund (+5)"])
        end
      end
    end

    context "when the lead is narrower than thresholds.unknown_below" do
      it "downgrades the kind to unknown and keeps every signal as evidence" do
        summary = "Отменить операцию"
        verdict = classify(operation_id: "refundCancel", path: "/operations/{id}", has_body: true,
                           node: { "summary" => summary })

        aggregate_failures do
          expect(verdict.confidence).to eq(0.14)
          expect(verdict.confidence).to be < thresholds.fetch("unknown_below")
          expect(verdict.kind).to eq("unknown")
          expect(verdict.scores).to eq(scores(cancel: 6, refund: 5))
          expect(verdict.evidence).to eq(["operationId token 'cancel' -> cancel (+5)",
                                          "operationId token 'refund' -> refund (+5)",
                                          "text 'отменить' -> cancel (+1)"])
        end
      end
    end

    context "with a custom dictionary" do
      subject(:classifier) { described_class.new(dictionary:) }

      let(:dictionary) do
        { "kinds" => %w[create webhook],
          "weights" => { "operation_id_strong" => 5, "operation_id_weak" => 2, "path" => 3, "tag" => 2, "text" => 1 },
          "synonyms" => { "create" => { "strong" => %w[enrol], "path" => %w[enrolment] }, "webhook" => {} },
          "structural" => {} }
      end

      it "scores the stems of that dictionary and nothing else" do
        known = classify(operation_id: "enrolMember", path: "/enrolments", has_body: true)
        unknown = classify(operation_id: "createPayout", path: "/payouts", has_body: true)

        aggregate_failures do
          expect(known.kind).to eq("create")
          expect(known.scores).to eq({ "create" => 8, "webhook" => 0 })
          expect(known.evidence).to eq(["operationId token 'enrol' -> create (+5)",
                                        "path token 'enrolments' -> create (+3)"])
          expect(unknown.kind).to eq("unknown")
          expect(unknown.scores).to eq({ "create" => 0, "webhook" => 0 })
        end
      end
    end
  end
end
