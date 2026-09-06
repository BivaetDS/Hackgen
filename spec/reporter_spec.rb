# frozen_string_literal: true

# The Reporter is what the jury reads: the analysis block and the run outcome follow the reference
# transcript in docs/TZ.md, failures go to stderr, backtraces only appear under --verbose.
RSpec.describe ProviderIntegrator::Reporter do
  let(:io) { StringIO.new }
  let(:err) { StringIO.new }
  let(:verbose) { false }
  let(:reporter) { described_class.new(io:, err:, verbose:, colour: false) }
  let(:parsed) { ProviderIntegrator::Parser.call(path: fixture_path("specs", "novapay.yaml")) }
  let(:generation) { GenerationHelpers.novapay_generation }

  def pipeline_result(status, **attrs)
    defaults = { spec: parsed.spec, events: parsed.events, files: [], output_dir: nil, error: nil }
    ProviderIntegrator::Models::PipelineResult.new(status:, **defaults.merge(attrs))
  end

  def written_files
    generation.files.map { |file| file.with(path: File.join("./output/novapay", file.name)) }
  end

  describe "#parsed (the analysis block)" do
    it "prints the reference lines for NovaPay" do
      reporter.parsed(parsed)

      aggregate_failures do
        expect(io.string.lines.first).to eq("Parsing spec... OpenAPI 3.0.3, NovaPay Payout API 1.0.0\n")
        expect(io.string).to include(<<~TEXT)
          Found 5 endpoints: POST /payouts, GET /payouts/{payout_id},
                             POST /payouts/{payout_id}/cancel, POST /webhooks/payout,
                             GET /balance
            create_request   -> POST /payouts (confidence 0.9)
            fetch_status     -> GET /payouts/{payout_id} (confidence 0.9)
            process_callback -> POST /webhooks/payout (confidence 0.92)
            extra            -> cancel, balance (outside the BaseService contract)
          Auth: ApiKeyAuth (header: X-API-Key)
          Webhook signature: X-NovaPay-Signature (HMAC-SHA256) on POST /webhooks/payout
        TEXT
        expect(err.string).to be_empty
      end
    end

    context "with --verbose" do
      let(:verbose) { true }

      it "adds the scheme type and confidence to the Auth line" do
        reporter.parsed(parsed)
        expect(io.string).to include("Auth: ApiKeyAuth (header: X-API-Key) [api_key, confidence 1.0]\n")
      end
    end

    it "prints nothing for a failed parse (finish reports the errors)" do
      reporter.parsed(ProviderIntegrator::Parser.call(path: fixture_path("specs", "invalid_bad_ref.yaml")))
      expect(io.string).to be_empty
    end

    it "degrades the webhook line when the spec has none" do
      reporter.parsed(ProviderIntegrator::Parser.call(path: fixture_path("specs", "bearerpay.yaml")))
      expect(io.string).to include("Webhook: not declared - process_callback is generated as a stub\n")
    end
  end

  describe "#generating and #generated" do
    it "announces the generation and summarises the validation on one line" do
      reporter.generating("novapay", "./output/novapay")
      reporter.generated(generation)

      expect(io.string).to eq(<<~TEXT)
        Generating service...
        Generating integration guide...
        Generating test fixtures...
        Generating contract stub and report...
        Validating output... Ruby syntax OK, RuboCop 0 offenses, 4/4 contract methods, fixtures valid, INTEGRATION.md 12 sections
      TEXT
    end

    it "names the failed checks under the verdict" do
      checks = generation.validation["checks"].map do |check|
        check["name"].end_with?(": syntax") ? check.merge("ok" => false, "detail" => "unexpected end (line 3)") : check
      end
      reporter.generated(generation.with(validation: { "ok" => false, "checks" => checks }))

      aggregate_failures do
        expect(io.string).to include("Validating output... Ruby syntax FAILED, RuboCop 0 offenses")
        expect(io.string).to include("  FAILED novapay_service.rb: syntax: unexpected end (line 3)\n",
                                     "  FAILED base_contract.rb: syntax: unexpected end (line 3)\n")
      end
    end
  end

  describe ProviderIntegrator::Reporter::ValidationLine do
    def verdict_for(checks, passed: checks.all? { |check| check["ok"] })
      described_class.new("ok" => passed, "checks" => checks)
    end

    def check(name, passed, detail) = { "name" => name, "ok" => passed, "detail" => detail }

    it "reads each part by check kind" do
      verdict = verdict_for([check("x_service.rb: syntax", true, "-"),
                             check("x_service.rb: rubocop", false, "A:1 m; B:2 n"),
                             check("x_service.rb: contract methods", false, "missing fetch_status"),
                             check("fixtures.json: JSON", true, "-"), check("fixtures.json: schemas", false, "bad"),
                             check("INTEGRATION.md: sections", false, "missing sections: Методы")])

      expect(verdict.text).to eq("Ruby syntax OK, RuboCop 2 offenses, contract methods: missing fetch_status, " \
                                 "fixtures: examples differ from the schemas, INTEGRATION.md missing sections: Методы")
    end

    it "reports missing files and an unparsable fixtures.json" do
      verdict = verdict_for([check("service_present", false, "the Ruby file was not generated"),
                             check("fixtures.json: JSON", false, "unexpected token")], passed: false)

      aggregate_failures do
        expect(verdict.text).to eq("the Ruby file was not generated, fixtures.json invalid")
        expect(verdict.failures).to eq(["service_present: the Ruby file was not generated",
                                        "fixtures.json: JSON: unexpected token"])
      end
    end
  end

  describe "#finish" do
    it "prints the warnings, the confirmation tally and the output paths in reference order" do
      reporter.finish(pipeline_result(:ok, files: written_files, output_dir: "./output/novapay"))

      aggregate_failures do
        expect(io.string).to start_with("Completed with 3 warnings:\n  W301 HMAC canonicalization")
        expect(io.string.scan(/^  W402 /).size).to eq(2)
        expect(io.string).to include("Requires confirmation: 7 items (W301, W402 x2, I201, I301, I401, I403) - " \
                                     "see INTEGRATION.md «Требует подтверждения» and generation_report.json\n")
        expect(io.string).to end_with(<<~TEXT)
          Output:
            ./output/novapay/novapay_service.rb
            ./output/novapay/INTEGRATION.md
            ./output/novapay/fixtures.json
            ./output/novapay/base_contract.rb
            ./output/novapay/generation_report.json
        TEXT
        expect(io.string).not_to include("  I201 ", "  I401 ")
        expect(err.string).to be_empty
      end
    end

    it "omits the output block and the file pointer after an analyze-only run" do
      reporter.finish(pipeline_result(:ok))

      aggregate_failures do
        expect(io.string).to include("Requires confirmation: 7 items (W301, W402 x2, I201, I301, I401, I403)\n")
        expect(io.string).not_to include("Output:", "INTEGRATION.md")
      end
    end

    it "sends spec errors to stderr" do
      failed = ProviderIntegrator::Parser.call(path: fixture_path("specs", "invalid_bad_ref.yaml"))
      reporter.finish(pipeline_result(:spec, spec: nil, events: failed.events))

      aggregate_failures do
        expect(err.string)
          .to eq("The spec cannot be used:\n  E005 Unresolvable $ref #/components/schemas/PayeeAccount\n")
        expect(io.string).to be_empty
      end
    end

    it "explains a generation failure and that nothing was written" do
      event = ProviderIntegrator::Events.build("E201", file: "novapay_service.rb", reason: "ERB tags remain")
      reporter.finish(pipeline_result(:generation, events: parsed.events + [event]))

      expect(err.string).to eq("Generation failed; nothing was written:\n  " \
                               "E201 Generated novapay_service.rb is invalid: ERB tags remain\n")
    end

    it "reports a write failure with the OS reason" do
      error = ProviderIntegrator::WriteError.new("cannot write ./out/novapay: Permission denied")
      reporter.finish(pipeline_result(:write, error:))

      expect(err.string).to eq("Cannot write output: cannot write ./out/novapay: Permission denied\n")
    end

    it "hides the backtrace of an internal error unless verbose" do
      error = RuntimeError.new("boom").tap { |e| e.set_backtrace(["lib/x.rb:1:in 'y'"]) }
      reporter.finish(pipeline_result(:internal, error:))

      expect(err.string).to eq("Internal error: RuntimeError: boom\nRun again with --verbose to see the backtrace.\n")
    end

    context "with --verbose" do
      let(:verbose) { true }

      it "lists the info events with their locations" do
        reporter.finish(pipeline_result(:ok))

        aggregate_failures do
          expect(io.string).to include("  I401 Amount field amount", "      at #/paths/~1payouts/post")
          expect(io.string).to include("  I201 Status mapping recorded")
        end
      end

      it "prints the backtrace of an internal error" do
        error = RuntimeError.new("boom").tap { |e| e.set_backtrace(["lib/x.rb:1:in 'y'"]) }
        reporter.finish(pipeline_result(:internal, error:))

        expect(err.string).to eq("Internal error: RuntimeError: boom\n    lib/x.rb:1:in 'y'\n")
      end
    end
  end
end
