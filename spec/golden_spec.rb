# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Golden do
  it "is not implemented before the generator exists" do
    expect { described_class.update! }
      .to raise_error(NotImplementedError, "golden regeneration arrives with the generator in wave 1/2")
  end
end
