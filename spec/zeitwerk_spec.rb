# frozen_string_literal: true

RSpec.describe ProviderIntegrator do
  it "eager loads every constant without errors (Zeitwerk layout is consistent)" do
    expect { described_class.loader.eager_load(force: true) }.not_to raise_error
  end

  it "exposes the version" do
    expect(ProviderIntegrator::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "keeps the compat shim outside the autoloader but loaded" do
    expect(ProviderIntegrator::Compat::Openapi3ParserPointerPatch).to be_a(Module)
  end
end
