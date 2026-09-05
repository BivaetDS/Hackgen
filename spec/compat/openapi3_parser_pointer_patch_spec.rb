# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Compat::Openapi3ParserPointerPatch do
  let(:pointer) { Openapi3Parser::Source::Pointer }

  it "is prepended to MergePointers" do
    expect(pointer::MergePointers.ancestors).to include(described_class)
  end

  it "resolves '..' against a relative base pointer" do
    merged = pointer.merge_pointers(["paths", "/payouts", "post"], "#..")

    expect([merged.segments, merged.absolute]).to eq([["paths", "/payouts"], false])
  end

  it "appends segments and coerces numeric strings like Pointer.from_fragment" do
    merged = pointer.merge_pointers("#/paths/~1payouts/post", %w[responses 200])

    expect([merged.segments, merged.absolute]).to eq([["paths", "/payouts", "post", "responses", 200], true])
  end

  it "skips '.' segments and never climbs above the root" do
    merged = pointer.merge_pointers(["a"], [".", "..", "..", "b"])

    expect(merged.segments).to eq(["b"])
  end

  it "keeps an absolute new pointer as is" do
    merged = pointer.merge_pointers(["paths"], "#/components/schemas/Recipient")

    expect(merged.segments).to eq(%w[components schemas Recipient])
  end

  it "lets openapi3_parser reach operations of the NovaPay document" do
    document = Openapi3Parser.load(novapay_openapi_hash)

    expect(document).to be_valid
    expect(document.paths["/payouts"].post.operation_id).to eq("createPayout")
    expect(document.paths["/payouts/{payout_id}"].get.responses["200"].description).to eq("Статус выплаты")
    expect(document.components.schemas["Recipient"].properties["bank_code"].description)
      .to eq("БИК банка (обязателен для type=sbp)")
  end
end
