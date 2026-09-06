# frozen_string_literal: true

# The message and digest expressions are the one source of truth for the signature arithmetic:
# verify_signature! in the service and the signing helper of the generated spec both print them.
RSpec.describe ProviderIntegrator::TemplateData::SignatureVerifier do
  let(:spec) { GenerationHelpers.novapay_spec }
  let(:service) { ProviderIntegrator::TemplateData::Service.new(ProviderIntegrator::Generator::Context.new(spec:)) }
  let(:signature) { spec.webhook.signature }

  def verifier(**changes)
    described_class.new(service, signature.with(**changes))
  end

  it "applies the canon defaults to the NovaPay signature and caps the confidence at 0.6" do
    subject = verifier

    aggregate_failures do
      expect([subject.algorithm, subject.encoding, subject.message]).to eq(%w[hmac-sha256 hex raw_body])
      expect([subject.location, subject.name]).to eq(%w[header X-NovaPay-Signature])
      expect(subject.confidence).to eq(0.6)
      expect(subject).not_to be_asymmetric
      expect(subject.message_expression("body")).to eq("JSON.generate(body)")
      expect(subject.digest_expression(secret: "secret", message: "message"))
        .to eq("OpenSSL::HMAC.hexdigest('SHA256', secret, message)")
    end
  end

  it "concatenates the sorted values without the signature field and encodes base64 when asked" do
    concatenated = verifier(location: "body", name: "sign", algorithm: "hmac-sha512", encoding: "base64",
                            message: "concatenated_fields")

    aggregate_failures do
      expect(concatenated.message_expression("body"))
        .to eq("body.reject { |key, _| key == 'sign' }.sort.map { |_, value| value.to_s }.join")
      expect(concatenated.digest_expression(secret: "s", message: "m"))
        .to eq("[OpenSSL::HMAC.digest('SHA512', s, m)].pack('m0')")
      expect(concatenated.confidence).to eq(0.5)
      expect(concatenated.method_data.source).to include("signature = callback_body(payload)['sign'].to_s")
    end
  end

  it "mixes the secret into a plain digest and stubs asymmetric algorithms" do
    plain = verifier(algorithm: "md5", encoding: "hex", message: "concatenated_fields")
    asymmetric = verifier(algorithm: "rsa-sha256", encoding: "base64", message: "raw_body")

    aggregate_failures do
      expect(plain.digest_expression(secret: "s", message: "m"))
        .to eq("OpenSSL::Digest.hexdigest('MD5', \"\#{m}\#{s}\")")
      expect(plain.confidence).to eq(0.4)
      expect(asymmetric).to be_asymmetric
      expect(asymmetric.method_data.source).to include("raise NotImplementedError")
    end
  end
end
