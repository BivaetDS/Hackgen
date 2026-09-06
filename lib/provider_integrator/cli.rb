# frozen_string_literal: true

module ProviderIntegrator
  # Thor command line (`bin/integrate`). One command, one pass: read the spec, print what was
  # recognised, then hand the IR to the generator. Exit codes are the contract with CI and the web
  # layer (docs/PLAN.md 7): 0 ok, 2 arguments, 3 unusable spec, 4 ambiguity under --strict.
  class CLI < Thor
    EXIT = { ok: 0, internal: 1, arguments: 2, spec: 3, ambiguous: 4, generation: 5, write: 6 }.freeze

    default_command :integrate
    map %w[--version -v] => :version

    # Thor exits with status 1 whenever a command raises Thor::Error.
    def self.exit_on_failure? = true

    desc "version", "Print the provider-integrator version"
    def version
      say "provider-integrator #{VERSION}"
    end

    desc "integrate", "Generate a provider integration from an OpenAPI spec"
    option :spec, type: :string, required: true, desc: "Path to the provider OpenAPI document (YAML or JSON)"
    option :provider, type: :string, desc: "Provider slug used for class and file names"
    option :output, type: :string, default: "./output", desc: "Directory for the generated files"
    option :overrides, type: :string, desc: "Path to an overrides.yml with fixed-key hints"
    option :analyze_only, type: :boolean, default: false, desc: "Print the analysed spec (IR) and stop"
    option :strict, type: :boolean, default: false, desc: "Treat warnings as a failure (exit 4)"
    option :verbose, type: :boolean, default: false, desc: "Show info events and spec locations"
    option :lang, type: :string, default: "ruby", desc: "Target language (only ruby is supported)"
    def integrate
      exit_with(run)
    end

    private

    def run
      return EXIT[:arguments] unless provider_option_valid?

      result = Parser.call(path: options[:spec], overrides: options[:overrides])
      return failed_spec(result) unless result.success?

      report(result)
      finish(result, options[:provider] || result.spec.provider.slug)
    end

    def report(result)
      reporter.analysis(result.spec)
      reporter.line
      reporter.summary(result.events)
    end

    def finish(result, slug)
      return analyze_only(result) if options[:analyze_only]

      reporter.line
      reporter.note("Generation of #{slug}_service.rb, INTEGRATION.md and fixtures.json is wave 1B; " \
                    "run with --analyze-only to see the full analysis as JSON.")
      strict_exit(result)
    end

    def analyze_only(result)
      $stdout.write(JsonCanon.generate(result.spec.to_h))
      strict_exit(result)
    end

    def strict_exit(result)
      options[:strict] && result.warnings.any? ? EXIT[:ambiguous] : EXIT[:ok]
    end

    def failed_spec(result)
      reporter.failure(result.events)
      EXIT[:spec]
    end

    # --provider is optional: the slug of info.title is the default. Given or derived, it becomes a
    # Ruby class name and a file name, so an explicit one is checked against the slug whitelist.
    def provider_option_valid?
      given = options[:provider]
      given.nil? || Inflector.slug?(given)
    end

    def reporter
      @reporter ||= Reporter.new(verbose: options[:verbose], colour: $stdout.tty?)
    end

    def exit_with(code)
      raise Thor::Error, "invalid --provider (expected a lower-case slug such as acmepay)" if code == EXIT[:arguments]

      exit(code)
    end
  end
end
