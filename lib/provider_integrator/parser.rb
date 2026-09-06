# frozen_string_literal: true

module ProviderIntegrator
  # Reads an OpenAPI document and returns the ProviderSpec IR plus the events raised on the way
  # (docs/PLAN.md 3.1). The parser never produces Ruby and never reads a template: it hands the
  # generator semantics ({conversion: {type: multiply, value: 100}}), not code.
  module Parser
    module_function

    # Parses +path+, optionally applying the fixed-key hints in +overrides+ (a path to overrides.yml).
    # Returns a Models::ParseResult whose #spec is nil when the document could not be used.
    def call(path:, overrides: nil)
      log = EventLog.new
      spec = analyse(path:, overrides:, log:)
      Models::ParseResult.new(value: spec, events: spec ? spec.events : log.sorted)
    end

    # Parses and returns just the IR, raising SpecError when the document is unusable.
    def call!(path:, overrides: nil)
      result = call(path:, overrides:)
      raise SpecError, result.errors.map(&:message).join("; ") unless result.success?

      result.spec
    end

    def analyse(path:, overrides:, log:)
      loaded = Loader.call(path:, log:)
      return nil unless loaded

      loaded = Swagger2Converter.call(loaded:, log:) if loaded.swagger2?
      return nil unless loaded && Validator.call(loaded:, log:)

      build(loaded:, overrides:, log:)
    end
    private_class_method :analyse

    def build(loaded:, overrides:, log:)
      document = Document.new(root: loaded.document, log:, spec_format: loaded.openapi)
      hints = Normalizer::Overrides.load(path: overrides, log:)
      return nil if log.error?

      Normalizer::SpecBuilder.new(document:, log:, overrides: hints, loaded:).call
    end
    private_class_method :build
  end
end
