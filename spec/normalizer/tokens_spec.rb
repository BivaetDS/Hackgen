# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Normalizer::Tokens do
  describe ".identifier" do
    it "splits an operationId on camelCase boundaries, separators and digit runs" do
      aggregate_failures do
        expect(described_class.identifier("createPayout")).to eq(%w[create payout])
        expect(described_class.identifier("createPayout2")).to eq(%w[create payout 2])
        expect(described_class.identifier("get-payout-status")).to eq(%w[get payout status])
        expect(described_class.identifier("payouts.create_v1")).to eq(%w[payouts create v 1])
        expect(described_class.identifier("HTTPResponse")).to eq(%w[http response])
      end
    end

    it "lower-cases every token so a dictionary never lists case variants" do
      expect(described_class.identifier("CancelPayoutBySBP")).to eq(%w[cancel payout by sbp])
    end

    it "returns no tokens when the spec declared no operationId" do
      aggregate_failures do
        expect(described_class.identifier(nil)).to eq([])
        expect(described_class.identifier("__")).to eq([])
      end
    end
  end

  describe ".path" do
    it "drops the placeholder segments and splits what is left further" do
      aggregate_failures do
        expect(described_class.path("/payouts/{payout_id}/cancel")).to eq(%w[payouts cancel])
        expect(described_class.path("/v1/payment-methods/{id}")).to eq(%w[v1 payment methods])
        expect(described_class.path("/Webhooks/Payout.Status")).to eq(%w[webhooks payout status])
      end
    end

    it "returns no tokens for a path without named segments" do
      aggregate_failures do
        expect(described_class.path("/")).to eq([])
        expect(described_class.path("/{id}")).to eq([])
      end
    end
  end

  describe ".tag" do
    it "splits a tag on whitespace, underscores and dashes" do
      aggregate_failures do
        expect(described_class.tag("Payout Webhooks")).to eq(%w[payout webhooks])
        expect(described_class.tag("payout_notifications")).to eq(%w[payout notifications])
        expect(described_class.tag("Webhook-Events")).to eq(%w[webhook events])
        expect(described_class.tag(nil)).to eq([])
      end
    end
  end

  describe ".words" do
    it "keeps Cyrillic words, which the dictionaries match on" do
      expect(described_class.words("Создать выплату (payout) 100 руб.")).to eq(%w[создать выплату payout 100 руб])
    end

    it "splits free text on every non-letter, non-digit character" do
      aggregate_failures do
        expect(described_class.words("Amount in kopecks; min. 1000 RUB")).to eq(%w[amount in kopecks min 1000 rub])
        expect(described_class.words(nil)).to eq([])
      end
    end
  end

  describe ".stem?" do
    it "is a prefix test, not a substring test" do
      aggregate_failures do
        expect(described_class.stem?("cents", "cent")).to be(true)
        expect(described_class.stem?("cent", "cent")).to be(true)
        expect(described_class.stem?("percent", "cent")).to be(false)
        expect(described_class.stem?("создать", "созда")).to be(true)
      end
    end
  end

  describe ".match" do
    it "returns the first token that starts with any of the stems" do
      aggregate_failures do
        expect(described_class.match(%w[get payout status], %w[status state])).to eq("status")
        expect(described_class.match(%w[payouts cancel], %w[cancel void])).to eq("cancel")
        expect(described_class.match(%w[payouts confirm], %w[cancel void])).to be_nil
      end
    end

    it "never matches a token listed in exclude, even when it starts with a stem" do
      aggregate_failures do
        expect(described_class.match(%w[get statement], ["state"])).to eq("statement")
        expect(described_class.match(%w[get statement], ["state"], exclude: %w[statement statements])).to be_nil
        expect(described_class.match(%w[get statement state], ["state"], exclude: %w[statement])).to eq("state")
      end
    end
  end

  describe ".match_stem" do
    it "treats a stem without a space as a token prefix and returns the whole token" do
      aggregate_failures do
        expect(described_class.match_stem("Amount in cents", ["cent"])).to eq("cents")
        expect(described_class.match_stem("Сумма в копейках", ["коп"])).to eq("копейках")
        expect(described_class.match_stem("Percentage of the fee", ["cent"])).to be_nil
      end
    end

    it "treats a stem with a space as a plain substring and returns the stem itself" do
      aggregate_failures do
        expect(described_class.match_stem("Amount in minor units", ["minor unit"])).to eq("minor unit")
        expect(described_class.match_stem("Amount in MINOR UNITS", ["minor unit"])).to eq("minor unit")
        expect(described_class.match_stem("Minorities", ["minor unit"])).to be_nil
      end
    end

    it "honours the order of the stems, not the order of the text" do
      expect(described_class.match_stem("cents and kopecks", %w[kopeck cent])).to eq("kopecks")
    end

    it "returns nil when there is no text to search" do
      aggregate_failures do
        expect(described_class.match_stem(nil, ["cent"])).to be_nil
        expect(described_class.match_stem("", ["cent"])).to be_nil
      end
    end
  end

  describe ".path_id?" do
    it "is true only when the path declares a template parameter" do
      aggregate_failures do
        expect(described_class.path_id?("/payouts/{payout_id}")).to be(true)
        expect(described_class.path_id?("/payouts")).to be(false)
        expect(described_class.path_id?(nil)).to be(false)
      end
    end
  end
end
