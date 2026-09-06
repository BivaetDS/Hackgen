# frozen_string_literal: true

# spec/golden/<spec>/ holds the byte-exact output of the generator for the fixture specs. Any
# change of the output shows up here as a diff; `rake golden:update` regenerates the directories.
RSpec.describe ProviderIntegrator::Golden do
  it "maintains golden output for every regression spec" do
    expect(described_class.present).to eq(%w[bearerpay cardpay legacy_swagger2 novapay numstatus rublepay])
  end

  described_class.present.each do |name|
    describe "spec/golden/#{name}" do
      let(:directory) { File.join(described_class::GOLDEN_DIR, name) }
      let(:result) { described_class.generate(name) }

      it "matches the current generator output byte for byte" do
        expect(result).to be_success
        expect(result.files.map(&:name).sort).to eq(Dir.children(directory).sort)
        result.files.each do |file|
          expected = ProviderIntegrator::Files.read(File.join(directory, file.name))
          expect(file.content).to eq(expected), "#{name}/#{file.name} differs from the golden copy " \
                                                "(run `rake golden:update` if the change is intended)"
        end
      end
    end
  end
end
