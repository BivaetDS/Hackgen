# frozen_string_literal: true

module ProviderIntegrator
  # Turns a ProviderSpec into the output files (docs/PLAN.md 3.1, 6): the service, the contract
  # stub, INTEGRATION.md, fixtures.json, the service spec and generation_report.json, validated
  # before they are handed back. The generator reads only the IR and the dictionaries; it never
  # sees the OpenAPI document, and it writes nothing itself - the pipeline decides where the files go.
  module Generator
    module_function

    # Generates every artefact for +spec+ under the provider +slug+ (defaults to the IR slug).
    # Returns a Models::GenerationResult; #failure? when the output did not pass validation.
    def call(spec:, provider: nil, output_dir: "./output")
      context = Context.new(spec:, provider:, output_dir:)
      log = EventLog.new
      files = generate(context, log)
      validation = OutputValidator.new(context:, files:, log:).call
      files << ReportGenerator.new(context, files:, validation:, events: log.sorted).call
      Models::GenerationResult.new(value: files, events: log.sorted, validation:)
    end

    # The five content files, in output order; a template failure becomes E201 for that file.
    def generate(context, log)
      generators = [ServiceGenerator, BaseContractGenerator, DocumentationGenerator, FixturesGenerator, RspecGenerator]
      generators.filter_map do |generator|
        generator.new(context).call
      rescue GenerationError => e
        log.add("E201", file: generator.name.split("::").last, reason: e.message)
        nil
      end
    end
    private_class_method :generate
  end
end
