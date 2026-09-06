# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Normalizer::SignatureAnalyzer do
  subject(:analyzer) { described_class.new }

  # The declaration the webhook analyzer hands over: a header parameter or a payload field.
  def header_source(name: "X-NovaPay-Signature", description: nil)
    described_class::Source.new(location: "header", name:, label: "parameter #{name} (header)", description:,
                                source: "parameter")
  end

  def body_source(path: "sign", description: nil)
    described_class::Source.new(location: "body", name: path, label: "field #{path}", description:, source: "field")
  end

  def algorithm_for(description)
    analyzer.call(source: header_source(description:)).algorithm
  end

  def encoding_for(description)
    analyzer.call(source: header_source(description:)).encoding
  end

  def message_for(description)
    analyzer.call(source: header_source(description:)).message
  end

  def body_message_for(description)
    analyzer.call(source: body_source(description:)).message
  end

  describe "#call" do
    context "with the NovaPay header parameter" do
      subject(:signature) do
        analyzer.call(source: header_source(description: "HMAC-SHA256 подпись тела запроса"),
                      summary: "Webhook уведомление о смене статуса", description: operation_description)
      end

      let(:operation_description) do
        "NovaPay отправляет POST-запрос на URL, указанный при регистрации.\n" \
          "Подпись передаётся в заголовке X-NovaPay-Signature (HMAC-SHA256)."
      end

      it "reads the algorithm and the message, leaves the encoding unknown and trusts the find" do
        aggregate_failures do
          expect(signature.location).to eq("header")
          expect(signature.name).to eq("X-NovaPay-Signature")
          expect(signature.algorithm).to eq("hmac-sha256")
          expect(signature.encoding).to eq("unknown")
          expect(signature.message).to eq("raw_body")
          expect(signature.secret).to eq("callback_secret")
          expect(signature.confidence).to eq(0.9)
          expect(signature.source).to eq("parameter")
        end
      end

      it "quotes the declaration and the one sentence of the description that names the algorithm" do
        expect(signature.evidence).to eq(
          ["parameter X-NovaPay-Signature (header): HMAC-SHA256 подпись тела запроса",
           "operation description: Подпись передаётся в заголовке X-NovaPay-Signature (HMAC-SHA256)"]
        )
      end
    end

    context "with a payload field that carries the signature" do
      subject(:signature) do
        analyzer.call(source: body_source(description:), summary: "Payment notification")
      end

      let(:description) { "Base64 of HMAC-SHA512 over the concatenated values of payment_id, order_id and sum" }

      it "reads algorithm, encoding and message from the field description" do
        aggregate_failures do
          expect(signature.location).to eq("body")
          expect(signature.name).to eq("sign")
          expect(signature.algorithm).to eq("hmac-sha512")
          expect(signature.encoding).to eq("base64")
          expect(signature.message).to eq("concatenated_fields")
          expect(signature.source).to eq("field")
          expect(signature.evidence).to eq(["field sign: #{description}"])
        end
      end
    end

    context "when only the operation summary names the algorithm" do
      subject(:signature) { analyzer.call(source: header_source(name: "X-Sign"), summary: "Callback signed SHA-256") }

      it "still finds the algorithm and quotes the summary" do
        aggregate_failures do
          expect(signature.algorithm).to eq("sha256")
          expect(signature.encoding).to eq("unknown")
          expect(signature.message).to eq("unknown")
          expect(signature.confidence).to eq(0.9)
          expect(signature.evidence).to eq(["operation summary: Callback signed SHA-256"])
        end
      end
    end

    context "when no text names an algorithm" do
      subject(:signature) do
        analyzer.call(source: header_source(name: "X-Signature", description: "Request signature"),
                      summary: "Status notification",
                      description: "The signing convention is documented in the merchant guide, not here.")
      end

      it "keeps the place, marks the algorithm unknown and halves the confidence" do
        aggregate_failures do
          expect(signature.algorithm).to eq("unknown")
          expect(signature.encoding).to eq("unknown")
          expect(signature.message).to eq("unknown")
          expect(signature.confidence).to eq(0.5)
          expect(signature.evidence).to eq(["parameter X-Signature (header)"])
          expect(signature.source).to eq("parameter")
        end
      end
    end

    it "returns nil when the spec declares no signature at all" do
      expect(analyzer.call(source: nil, summary: "Webhook", description: "Signed with HMAC-SHA256")).to be_nil
    end
  end

  describe "algorithm precedence" do
    it "takes the most specific name and reads a bare HMAC as hmac-sha256" do
      aggregate_failures do
        expect(algorithm_for("HMAC-SHA512; legacy contracts still use HMAC-SHA256")).to eq("hmac-sha512")
        expect(algorithm_for("HMAC подпись тела запроса")).to eq("hmac-sha256")
        expect(algorithm_for("HMAC256 of the payload")).to eq("hmac-sha256")
        expect(algorithm_for("HMAC-SHA1 of the payload")).to eq("hmac-sha1")
        expect(algorithm_for("HMAC-MD5 checksum")).to eq("hmac-md5")
        expect(algorithm_for("SHA-512 digest")).to eq("sha512")
        expect(algorithm_for("SHA-256 digest")).to eq("sha256")
        expect(algorithm_for("SHA-1 digest")).to eq("sha1")
        expect(algorithm_for("MD5 checksum of the request")).to eq("md5")
        expect(algorithm_for("RSA signature over the request")).to eq("rsa-sha256")
        expect(algorithm_for("Ed25519 signature")).to eq("ed25519")
      end
    end

    it "reads the encoding from the same texts and leaves it open when none says it" do
      aggregate_failures do
        expect(encoding_for("HMAC-SHA256, hex digest")).to eq("hex")
        expect(encoding_for("HMAC-SHA256 hexdigest of the body")).to eq("hex")
        expect(encoding_for("HMAC-SHA256, подпись в шестнадцатеричном виде")).to eq("hex")
        expect(encoding_for("HMAC-SHA256 в base64")).to eq("base64")
        expect(encoding_for("HMAC-SHA256 подпись тела запроса")).to eq("unknown")
      end
    end

    # A header carries a signature over something, so any body stem means the raw body; a signature
    # that travels inside the payload only counts the unambiguous ones (IR_CONTRACT 2.9).
    it "reads what is hashed and trusts fewer stems for a signature that travels in the body" do
      aggregate_failures do
        expect(message_for("HMAC-SHA256 of the raw body")).to eq("raw_body")
        expect(message_for("HMAC-SHA256 of the payload")).to eq("raw_body")
        expect(message_for("HMAC-SHA256 конкатенации полей")).to eq("concatenated_fields")
        expect(body_message_for("HMAC-SHA256 over the raw bytes")).to eq("raw_body")
        expect(body_message_for("HMAC-SHA256 of the payload")).to eq("unknown")
        expect(body_message_for("HMAC-SHA256 подпись")).to eq("unknown")
      end
    end
  end

  describe "overrides" do
    subject(:signature) do
      analyzer.call(source: body_source(description: "MD5 of the concatenated fields"),
                    description: "Signed with MD5", override:)
    end

    let(:override) do
      { location: "header", name: "X-Sign", algorithm: "hmac-sha512", encoding: "hex", message: "raw_body" }
    end

    it "replaces every inferred value and says so in the evidence" do
      aggregate_failures do
        expect(signature.to_h).to include("location" => "header", "name" => "X-Sign", "algorithm" => "hmac-sha512",
                                          "encoding" => "hex", "message" => "raw_body", "confidence" => 0.9)
        expect(signature.evidence).to eq(["overrides.yml: signature X-Sign (header)"])
        expect(signature.source).to eq("override")
      end
    end

    it "applies even when the spec declares no signature" do
      forced = analyzer.call(source: nil, override:)

      expect([forced.name, forced.source]).to eq(%w[X-Sign override])
    end
  end

  describe "#defaults" do
    it "hands the generator the canon defaults for what the spec left open" do
      expect(analyzer.defaults).to eq("algorithm" => "hmac-sha256", "encoding" => "hex", "message" => "raw_body",
                                      "secret" => "callback_secret")
    end

    it "reads the secret name from the canonical contract it was given" do
      canon = { "credentials" => { "callback_secret" => "notification_key" },
                "signature_defaults" => { "encoding" => "base64", "message" => "raw_body" } }
      signature = described_class.new(canon:).call(source: header_source(description: "HMAC-SHA256"))

      expect([signature.secret, described_class.new(canon:).defaults["encoding"]])
        .to eq(%w[notification_key base64])
    end
  end
end
