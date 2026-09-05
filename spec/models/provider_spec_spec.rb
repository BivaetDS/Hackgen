# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Models::ProviderSpec do
  let(:spec) { described_class.from_h(ModelExamples.all["ProviderSpec"]) }

  it "finds contract operations by canonical method and operations by kind" do
    aggregate_failures do
      expect(spec.contract_operations.map(&:operation_id)).to eq(["createPayout"])
      expect(spec.operation_for("create_request").operation_id).to eq("createPayout")
      expect(spec.operation_for("fetch_status")).to be_nil
      expect(spec.operations_of_kind("create").size).to eq(1)
      expect(spec.operations_of_kind("balance")).to be_empty
    end
  end

  it "reports its ir_version" do
    expect(spec.ir_version).to eq(1)
  end
end
