# frozen_string_literal: true

require "tmpdir"

RSpec.describe ProviderIntegrator::Parser::Loader do
  let(:dir) { Dir.mktmpdir("provider-integrator-loader") }
  let(:log) { ProviderIntegrator::EventLog.new }
  let(:loaded) { described_class.call(path: spec_path, log:) }
  let(:event) { log.to_a.first }

  after { FileUtils.rm_rf(dir) }

  # Writes +content+ with LF endings and returns its path (Files.write never translates newlines).
  def write_spec(name, content)
    ProviderIntegrator::Files.write(File.join(dir, name), content)
  end

  # A document whose deepest branch nests exactly +levels+ levels, the root counted as the first.
  def nested_document(levels)
    branch = (3..levels).inject("leaf") { |node, _| { "nested" => node } }
    { "openapi" => "3.0.3", "info" => { "title" => "DeepPay", "version" => "1.0.0" }, "deep" => branch }
  end

  describe ".call" do
    context "with a supported document" do
      let(:spec_path) do
        write_spec("minipay.yaml", <<~YAML)
          openapi: 3.0.3
          info:
            title: MiniPay Payout API
            version: "1.0.0"
          paths:
            /payouts:
              post:
                operationId: createPayout
                responses:
                  "201":
                    description: Created
        YAML
      end

      it "returns the parsed document and the declared OpenAPI 3.0 version" do
        aggregate_failures do
          expect(loaded.openapi).to eq("3.0.3")
          expect(loaded.swagger).to be_nil
          expect(loaded).not_to be_swagger2
          expect(loaded.document["info"]).to eq({ "title" => "MiniPay Payout API", "version" => "1.0.0" })
          expect(loaded.document["paths"].keys).to eq(["/payouts"])
          expect(log).to be_empty
        end
      end
    end

    context "with an OpenAPI 3.1 document" do
      let(:spec_path) do
        write_spec("minipay31.yaml", <<~YAML)
          openapi: 3.1.0
          info:
            title: MiniPay Payout API
            version: "2.0.0"
          paths: {}
        YAML
      end

      it "accepts the 3.1 major and reports no conversion" do
        aggregate_failures do
          expect(loaded.openapi).to eq("3.1.0")
          expect(loaded).not_to be_swagger2
          expect(log).to be_empty
        end
      end
    end

    context "with a Swagger 2.0 document" do
      let(:spec_path) do
        write_spec("legacy.yaml", <<~YAML)
          swagger: "2.0"
          info:
            title: Kassira Merchant API
            version: "2.4"
          paths: {}
        YAML
      end

      it "keeps swagger separate from openapi and flags the document for conversion" do
        aggregate_failures do
          expect(loaded.swagger).to eq("2.0")
          expect(loaded.openapi).to be_nil
          expect(loaded).to be_swagger2
          expect(log).to be_empty
        end
      end
    end

    context "when the file cannot be read" do
      let(:spec_path) { File.join(dir, "absent.yaml") }

      it "reports E001 and returns nil" do
        aggregate_failures do
          expect(loaded).to be_nil
          expect(event.code).to eq("E001")
          expect(event.message).to eq("Spec cannot be parsed: #{spec_path} is not a readable file")
          expect(event.details).to eq({ "reason" => "#{spec_path} is not a readable file" })
          expect(event.location).to be_nil
        end
      end

      it "reports E001 for a directory as well" do
        expect(described_class.call(path: dir, log:)).to be_nil
        expect(log.with_code("E001").size).to eq(1)
      end
    end

    context "when the YAML is broken" do
      let(:spec_path) { fixture_path("specs", "invalid_broken_yaml.yaml") }

      it "reports E001 once with the parser message on a single line" do
        aggregate_failures do
          expect(loaded).to be_nil
          expect(log.to_a.map(&:code)).to eq(["E001"])
          expect(event.message).to start_with("Spec cannot be parsed: ")
          expect(event.details["reason"]).not_to include("\n")
          expect(event.details["reason"]).to include("quoted scalar")
        end
      end
    end

    context "when the document uses a YAML alias" do
      let(:spec_path) do
        write_spec("aliased.yaml", <<~YAML)
          openapi: 3.0.3
          info: &info
            title: AliasPay
            version: "1.0.0"
          paths: {}
          x-copy: *info
        YAML
      end

      it "refuses the alias with E007 instead of expanding it" do
        aggregate_failures do
          expect(loaded).to be_nil
          expect(event.code).to eq("E007")
          expect(event.message)
            .to eq("Input exceeds limits: YAML aliases are not supported (a spec may not reference itself)")
        end
      end
    end

    context "when the root is not a mapping" do
      let(:spec_path) { write_spec("sequence.yaml", "- openapi: 3.0.3\n- info: {}\n") }

      it "reports E001 with the actual root type" do
        aggregate_failures do
          expect(loaded).to be_nil
          expect(event.code).to eq("E001")
          expect(event.message).to eq("Spec cannot be parsed: document root is Array, expected a mapping")
        end
      end

      it "reports E001 for a scalar root too" do
        scalar = described_class.call(path: write_spec("scalar.yaml", "just a string\n"), log:)

        expect(scalar).to be_nil
        expect(log.to_a.last.message).to eq("Spec cannot be parsed: document root is String, expected a mapping")
      end
    end

    context "when the version is missing or unsupported" do
      let(:spec_path) do
        write_spec("versionless.yaml", "info:\n  title: NoVersionPay\n  version: \"1.0.0\"\npaths: {}\n")
      end

      it "reports E002 with the supported majors when no version is declared" do
        aggregate_failures do
          expect(loaded).to be_nil
          expect(event.code).to eq("E002")
          expect(event.message).to eq("Unsupported OpenAPI version (absent); supported: 2.0, 3.0, 3.1")
          expect(event.details).to eq({ "version" => "(absent)", "supported" => ["2.0", "3.0", "3.1"] })
        end
      end

      it "reports E002 for a future major" do
        future = described_class.call(path: write_spec("future.yaml", "openapi: \"4.0\"\npaths: {}\n"), log:)

        expect(future).to be_nil
        expect(log.to_a.last.message).to eq("Unsupported OpenAPI version 4.0; supported: 2.0, 3.0, 3.1")
      end

      it "reports E002 when the version is not a String (an unquoted 3.0 is a YAML float)" do
        float = described_class.call(path: write_spec("float.yaml", "openapi: 3.0\npaths: {}\n"), log:)

        expect(float).to be_nil
        expect(log.to_a.last.message).to eq("Unsupported OpenAPI version 3.0; supported: 2.0, 3.0, 3.1")
      end
    end

    context "when the file is larger than the size limit" do
      let(:spec_path) { write_spec("huge.yaml", "y" * (described_class::MAX_BYTES + 1)) }

      it "reports E007 with the measured size and the limit, without parsing the content" do
        aggregate_failures do
          expect(described_class::MAX_BYTES).to eq(5 * 1024 * 1024)
          expect(loaded).to be_nil
          expect(log.to_a.map(&:code)).to eq(["E007"])
          expect(event.message).to eq("Input exceeds limits: file is 5242881 bytes, limit is 5242880")
          expect(event.details).to eq({ "reason" => "file is 5242881 bytes, limit is 5242880" })
        end
      end

      it "accepts a file sized exactly to the limit" do
        header = "openapi: 3.0.3\npaths: {}\n#"
        path = write_spec("at_byte_limit.yaml", header + ("y" * (described_class::MAX_BYTES - header.bytesize)))
        at_limit = described_class.call(path:, log:)

        aggregate_failures do
          expect(File.size(path)).to eq(described_class::MAX_BYTES)
          expect(at_limit.openapi).to eq("3.0.3")
          expect(log).to be_empty
        end
      end
    end

    context "when the document nests too deeply" do
      let(:spec_path) { write_spec("deep.yaml", Psych.dump(nested_document(described_class::MAX_DEPTH + 1))) }

      it "reports E007 with the measured depth and the limit" do
        aggregate_failures do
          expect(described_class::MAX_DEPTH).to eq(100)
          expect(loaded).to be_nil
          expect(event.code).to eq("E007")
          expect(event.message).to eq("Input exceeds limits: document nests 101 levels, limit is 100")
        end
      end

      it "accepts a document nested exactly to the limit" do
        path = write_spec("at_limit.yaml", Psych.dump(nested_document(described_class::MAX_DEPTH)))
        at_limit = described_class.call(path:, log:)

        expect(at_limit.openapi).to eq("3.0.3")
        expect(log).to be_empty
      end

      it "counts sequence nesting toward the depth as well" do
        branch = (3..(described_class::MAX_DEPTH + 1)).inject("leaf") { |node, _| [node] }
        deep = { "openapi" => "3.0.3", "info" => { "title" => "DeepPay", "version" => "1.0.0" }, "deep" => branch }
        nested = described_class.call(path: write_spec("deep_seq.yaml", Psych.dump(deep)), log:)

        expect(nested).to be_nil
        expect(event.message).to eq("Input exceeds limits: document nests 101 levels, limit is 100")
      end
    end
  end
end
