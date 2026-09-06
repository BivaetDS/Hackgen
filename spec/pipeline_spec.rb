# frozen_string_literal: true

require "tmpdir"

# The pipeline is the product's one pass: parse, generate, write. Every way it can end has a
# status, nothing raises past it, and what lands on disk is exactly what the generator produced.
RSpec.describe ProviderIntegrator::Pipeline do
  let(:novapay) { fixture_path("specs", "novapay.yaml") }
  let(:golden_dir) { repo_path("spec", "golden", "novapay") }

  # A recording observer: [[:parsed], [:generating, slug, dir], [:generated]] in call order.
  let(:observer) do
    Class.new do
      attr_reader :calls

      def initialize = @calls = []
      def parsed(result) = @calls << [:parsed, result.class]
      def generating(slug, output_dir) = @calls << [:generating, slug, output_dir]
      def generated(result) = @calls << [:generated, result.class]
    end.new
  end

  def run(dir, **options)
    described_class.call(path: novapay, output: dir, **options)
  end

  def files_in(dir)
    Dir.glob("**/*", base: dir).select { |entry| File.file?(File.join(dir, entry)) }.sort
  end

  it "writes the five generated files under <output>/<slug>/, byte-identical to the golden copy" do
    Dir.mktmpdir("pipeline") do |dir|
      result = run(dir, provider: "novapay")

      aggregate_failures do
        expect(result).to be_success
        expect(result.status).to eq(:ok)
        expect(result.output_dir).to eq(File.join(dir, "novapay"))
        expect(files_in(dir)).to eq(%w[INTEGRATION.md base_contract.rb fixtures.json generation_report.json
                                       novapay_service.rb].map { |name| "novapay/#{name}" })
        result.files.each do |file|
          expect(ProviderIntegrator::Files.read(file.path))
            .to eq(ProviderIntegrator::Files.read(File.join(golden_dir, file.name)))
        end
      end
    end
  end

  it "defaults the slug to the IR slug and overwrites its own output on a second run" do
    Dir.mktmpdir("pipeline") do |dir|
      first = run(dir)
      second = run(dir)

      aggregate_failures do
        expect(first.output_dir).to eq(File.join(dir, "novapay"))
        expect(second.files.map(&:sha256)).to eq(first.files.map(&:sha256))
        expect(files_in(dir).size).to eq(5)
      end
    end
  end

  it "merges the analysis events into the result and reports each stage to the observer" do
    Dir.mktmpdir("pipeline") do |dir|
      result = run(dir, observer:)

      aggregate_failures do
        expect(result.events.map(&:code)).to include("W301", "W402", "I401")
        expect(result.warnings.size).to eq(3)
        expect(result.spec.provider.slug).to eq("novapay")
        expect(observer.calls).to eq([[:parsed, ProviderIntegrator::Models::ParseResult],
                                      [:generating, "novapay", File.join(dir, "novapay")],
                                      [:generated, ProviderIntegrator::Models::GenerationResult]])
      end
    end
  end

  it "stops after the analysis under analyze_only and writes nothing" do
    Dir.mktmpdir("pipeline") do |dir|
      result = run(dir, analyze_only: true, observer:)

      aggregate_failures do
        expect(result.status).to eq(:ok)
        expect(result.spec).not_to be_nil
        expect(result.files).to be_empty
        expect(result.output_dir).to be_nil
        expect(files_in(dir)).to be_empty
        expect(observer.calls.map(&:first)).to eq([:parsed])
      end
    end
  end

  it "returns :spec with the error events for an unusable document and creates no directory" do
    Dir.mktmpdir("pipeline") do |dir|
      result = described_class.call(path: fixture_path("specs", "invalid_bad_ref.yaml"), output: dir)

      aggregate_failures do
        expect(result.status).to eq(:spec)
        expect(result).to be_failure
        expect(result.spec).to be_nil
        expect(result.errors.map(&:code)).to eq(["E005"])
        expect(Dir.children(dir)).to be_empty
      end
    end
  end

  it "returns :generation and writes nothing when the output fails validation" do
    failed = ProviderIntegrator::Models::GenerationResult.new(
      value: [], validation: { "ok" => false, "checks" => [] },
      events: [ProviderIntegrator::Events.build("E201", file: "novapay_service.rb", reason: "syntax")]
    )
    allow(ProviderIntegrator::Generator).to receive(:call).and_return(failed)

    Dir.mktmpdir("pipeline") do |dir|
      result = run(dir)

      aggregate_failures do
        expect(result.status).to eq(:generation)
        expect(result.errors.map(&:code)).to eq(["E201"])
        expect(result.events.map(&:code)).to include("W301")
        expect(result.files).to be_empty
        expect(Dir.children(dir)).to be_empty
      end
    end
  end

  it "returns :write with the OS reason when the output root is a file" do
    Dir.mktmpdir("pipeline") do |dir|
      blocker = File.join(dir, "blocker")
      File.write(blocker, "not a directory")
      result = run(blocker)

      aggregate_failures do
        expect(result.status).to eq(:write)
        expect(result.error).to be_a(ProviderIntegrator::WriteError)
        expect(result.error.message).to start_with("cannot write #{File.join(blocker, "novapay")}: ")
        expect(result.error.message).not_to include(" @ ")
        expect(result.files).to be_empty
      end
    end
  end

  it "returns :internal with the exception instead of raising" do
    allow(ProviderIntegrator::Parser).to receive(:call).and_raise(RuntimeError, "boom")

    result = described_class.call(path: novapay, output: "unused")

    aggregate_failures do
      expect(result.status).to eq(:internal)
      expect(result.error).to be_a(RuntimeError).and(have_attributes(message: "boom"))
      expect(result.events).to be_empty
      expect(result.spec).to be_nil
    end
  end

  it "rejects an unsafe provider slug before doing anything (a caller bug, so it raises)" do
    expect { described_class.call(path: novapay, provider: "../x") }
      .to raise_error(ArgumentError, /not a safe identifier/)
  end

  it "ignores a silent default observer" do
    expect(described_class::NullObserver.new.generating("x", "y")).to be_nil
  end
end
