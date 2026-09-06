# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Generator::RubyFormatter do
  let(:source) do
    "# frozen_string_literal: true\n\nclass Provider\n  class XService\n    A = {\"a\"=>1,\n \"bb\" => 2}\n  end\nend\n"
  end

  it "formats in memory to the generated-code style (single quotes, table rockets) with LF endings" do
    formatted = described_class.format(source, name: "x_service.rb")

    aggregate_failures do
      expect(formatted).to include("'a'  => 1,", "'bb' => 2")
      expect(formatted).not_to include("\r")
      expect(formatted).to end_with("}.freeze\n  end\nend\n")
      expect(described_class.offenses(formatted, name: "x_service.rb")).to eq([])
    end
  end

  it "is a fixed point: formatting the formatted source changes nothing" do
    formatted = described_class.format(source, name: "x_service.rb")

    expect(described_class.format(formatted, name: "x_service.rb")).to eq(formatted)
  end

  it "reports the offenses left in a source it cannot fix" do
    offenses = described_class.offenses("# frozen_string_literal: true\n\ndef a(x)\n  1\nend\n", name: "a.rb")

    expect(offenses).to all(match(%r{\A[A-Z][A-Za-z]+/[A-Za-z]+:\d+ }))
  end
end
