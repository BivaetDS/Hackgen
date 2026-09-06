# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Inflector do
  describe ".snake_case" do
    it "handles camelCase, kebab-case, acronyms and separators" do
      expect(described_class.snake_case("createPayout")).to eq("create_payout")
      expect(described_class.snake_case("X-NovaPay-Signature")).to eq("x_nova_pay_signature")
      expect(described_class.snake_case("SBP")).to eq("sbp")
      expect(described_class.snake_case("getHTTPStatus")).to eq("get_http_status")
      expect(described_class.snake_case("  payout id ")).to eq("payout_id")
    end
  end

  describe ".camel_case / .constant_case / .class_name" do
    it "derives class and constant names from a slug" do
      expect(described_class.camel_case("nova_pay")).to eq("NovaPay")
      expect(described_class.camel_case("novapay")).to eq("Novapay")
      expect(described_class.constant_case("novapay")).to eq("NOVAPAY")
      expect(described_class.class_name("1pay")).to eq("N1pay")
      expect(described_class.class_name("Сбербанк")).to eq("Provider")
    end
  end

  describe ".identifier" do
    it "returns safe method names for spec-derived strings" do
      aggregate_failures do
        expect(described_class.identifier("sbp")).to eq("sbp")
        expect(described_class.identifier("bank-card")).to eq("bank_card")
        expect(described_class.identifier("class")).to eq("class_field")
        expect(described_class.identifier("send")).to eq("send_field")
        expect(described_class.identifier("3ds")).to eq("_3ds")
        expect(described_class.identifier("СБП", fallback: "method")).to eq("method_field")
        expect(described_class.identifier("", fallback: "default")).to eq("default")
      end
    end
  end

  describe ".slug?" do
    it "accepts lower-case slugs only" do
      expect(described_class.slug?("novapay")).to be(true)
      expect(described_class.slug?("nova_pay2")).to be(true)
      expect(%w[NovaPay 1pay nova-pay].map { |slug| described_class.slug?(slug) }).to all(be(false))
      expect(described_class.slug?("../etc")).to be(false)
      expect(described_class.slug?(nil)).to be(false)
    end
  end

  describe ".ruby_string / .ruby_literal" do
    it "prefers single quotes and escapes when needed" do
      expect(described_class.ruby_string("RUB")).to eq("'RUB'")
      expect(described_class.ruby_string("Сбербанк")).to eq("'Сбербанк'")
      expect(described_class.ruby_string("it's")).to eq('"it\'s"')
      expect(described_class.ruby_string("a\nb")).to eq('"a\nb"')
    end

    it "renders nested JSON-like values as Ruby" do
      literal = described_class.ruby_literal({ "amount" => 1500, "recipient" => { "type" => "sbp", "ok" => true },
                                               "tags" => ["a", nil, 1.5] })

      expect(literal).to eq("{ 'amount' => 1500, 'recipient' => { 'type' => 'sbp', 'ok' => true }, " \
                            "'tags' => ['a', nil, 1.5] }")
      expect(described_class.ruby_literal({})).to eq("{}")
    end
  end
end
