# frozen_string_literal: true

# The output validator is the last gate before files are written (docs/PLAN.md 8): every kind of
# broken output must come back as a failed check and, when fatal, an E201 event.
RSpec.describe ProviderIntegrator::Generator::OutputValidator do
  let(:context) { ProviderIntegrator::Generator::Context.new(spec: GenerationHelpers.novapay_spec) }
  let(:generated) { GenerationHelpers.novapay_generation.files }

  def file(kind, content)
    original = generated.find { |item| item.kind == kind.to_s }
    ProviderIntegrator::Models::GeneratedFile.build(kind:, name: original.name, path: original.path, content:)
  end

  def validate(replacements)
    files = generated.reject { |item| item.kind == "report" }.map { |item| replace(item, replacements) }
    log = ProviderIntegrator::EventLog.new
    summary = described_class.new(context:, files:, log:).call
    [summary, log.to_a]
  end

  def replace(item, replacements)
    replacements.key?(item.kind.to_sym) ? file(item.kind, replacements[item.kind.to_sym]) : item
  end

  def failed(summary) = summary["checks"].reject { |check| check["ok"] }.map { |check| check["name"] }

  it "accepts the generated NovaPay output as is" do
    summary, events = validate({})

    aggregate_failures do
      expect(summary["ok"]).to be(true)
      expect(events).to be_empty
    end
  end

  it "reports a syntax error in the service as E201" do
    summary, events = validate(service: "class Provider\n  class NovapayService < BaseService\n    def x(\n")

    aggregate_failures do
      expect(summary["ok"]).to be(false)
      expect(failed(summary)).to eq(["novapay_service.rb: syntax"])
      expect(events.map(&:code)).to eq(["E201"])
      expect(events.first.message).to include("novapay_service.rb")
    end
  end

  it "reports leftover ERB tags and missing contract methods" do
    source = "# frozen_string_literal: true\n\nclass Provider\n  class NovapayService < BaseService\n    " \
             "def create_request(operation, request_method = 'sbp')\n      <%= payload %>\n    end\n  end\nend\n"
    summary, events = validate(service: "#{source.sub("<%= payload %>", "nil")}# <%= leftover %>\n")

    aggregate_failures do
      expect(failed(summary)).to include("novapay_service.rb: no ERB leftovers", "novapay_service.rb: contract methods")
      expect(summary["checks"].find { |check| check["name"] == "novapay_service.rb: contract methods" }["detail"])
        .to eq("missing fetch_status, process_callback, check_conditions")
      expect(events.map(&:code).uniq).to eq(["E201"])
    end
  end

  it "reports a service that does not inherit the contract" do
    source = GenerationHelpers.novapay_file(:service).sub("< BaseService", "< Object")
    summary, = validate(service: source)

    expect(failed(summary)).to eq(["novapay_service.rb: inherits BaseService"])
  end

  it "records remaining RuboCop offenses without failing the run" do
    source = GenerationHelpers.novapay_file(:service).sub("def fetch_balance", "def fetch_balance()")
    summary, events = validate(service: source)

    aggregate_failures do
      expect(failed(summary)).to eq(["novapay_service.rb: rubocop"])
      expect(events).to be_empty
    end
  end

  it "reports unparsable fixtures as E201 and a missing INTEGRATION.md section as E201" do
    summary, events = validate(fixtures: "{ not json", documentation: "# Guide\n\n## Методы\n")

    aggregate_failures do
      expect(failed(summary)).to include("fixtures.json: JSON", "INTEGRATION.md: sections")
      expect(events.map(&:code)).to eq(%w[E201 E201])
      expect(events.last.message).to include("Авторизация")
    end
  end

  it "records a fixture that violates the schema rebuilt from the IR, without failing the run" do
    fixtures = JSON.parse(GenerationHelpers.novapay_file(:fixtures))
    fixtures["create_request"]["request"]["amount"] = "not an integer"
    summary, events = validate(fixtures: JSON.generate(fixtures))

    aggregate_failures do
      expect(failed(summary)).to eq(["fixtures.json: schemas"])
      expect(summary["checks"].find { |check| check["name"] == "fixtures.json: schemas" }["detail"])
        .to include("create_request.request")
      expect(events).to be_empty
    end
  end
end
