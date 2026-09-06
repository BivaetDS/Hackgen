# frozen_string_literal: true

module ProviderIntegrator
  # Thor command line (`bin/integrate`). One command, one pass through the Pipeline; the Reporter
  # prints each stage as it happens. Exit codes are the contract with CI and the web layer
  # (docs/PLAN.md 7): 0 ok, 1 internal error, 2 arguments, 3 unusable spec, 4 warnings under
  # --strict, 5 output failed validation (nothing written), 6 output could not be written.
  class CLI < Thor
    EXIT = { ok: 0, internal: 1, arguments: 2, spec: 3, ambiguous: 4, generation: 5, write: 6 }.freeze
    LANGUAGES = %w[ruby].freeze

    default_command :integrate
    map %w[--version -v] => :version

    # Thor exits with a non-zero status whenever a command raises Thor::Error.
    def self.exit_on_failure? = true

    # Argument errors, Thor's own and ours, end with EXIT[:arguments] instead of Thor's default 1.
    def self.start(given_args = ARGV, config = {})
      super(given_args, config.merge(debug: true))
    rescue Thor::Error => e
      warn e.message
      exit(EXIT[:arguments])
    end

    desc "version", "Print the provider-integrator version"
    def version
      say "provider-integrator #{VERSION}"
    end

    desc "integrate", "Generate a provider integration from an OpenAPI spec"
    option :spec, type: :string, required: true, desc: "Path to the provider OpenAPI document (YAML or JSON)"
    option :provider, type: :string, desc: "Provider slug used for class and file names (default: from info.title)"
    option :output, type: :string, default: "./output", desc: "Root directory; files go to <output>/<provider>/"
    option :overrides, type: :string, desc: "Path to an overrides.yml with fixed-key hints"
    option :analyze_only, type: :boolean, default: false, desc: "Print the analysed spec (IR) as JSON and stop"
    option :strict, type: :boolean, default: false, desc: "Treat warnings as a failure (exit 4)"
    option :verbose, type: :boolean, default: false, desc: "Show info events, spec locations and backtraces"
    option :lang, type: :string, default: "ruby", desc: "Target language (only ruby is supported)"
    def integrate
      validate_options!
      result = run_pipeline
      emit_ir(result) if options[:analyze_only]
      reporter.finish(result)
      exit(exit_code(result))
    end

    private

    def run_pipeline
      Pipeline.call(path: options[:spec], provider: options[:provider], output: options[:output],
                    overrides: options[:overrides], analyze_only: options[:analyze_only], observer: reporter)
    end

    # The IR as canonical JSON on stdout; nothing else is printed there under --analyze-only.
    def emit_ir(result)
      $stdout.write(JsonCanon.generate(result.spec.to_h)) if result.spec
    end

    # --provider becomes a class and a file name, so it must pass the slug whitelist; --lang exists
    # for the reference invocation shape and accepts only ruby.
    def validate_options!
      provider = options[:provider]
      unless provider.nil? || Inflector.slug?(provider)
        raise Thor::Error, "invalid --provider #{provider.inspect} (expected a lower-case slug such as acmepay)"
      end
      return if LANGUAGES.include?(options[:lang])

      raise Thor::Error, "unsupported --lang #{options[:lang].inspect} (supported: #{LANGUAGES.join(", ")})"
    end

    # The pipeline status maps onto the exit table by name; --strict turns a warned success into 4.
    def exit_code(result)
      return EXIT[:ambiguous] if result.success? && options[:strict] && result.warnings.any?

      EXIT.fetch(result.status)
    end

    # Under --analyze-only stdout carries the IR alone (pipe it to a file), so the human-readable
    # part moves to stderr.
    def reporter
      @reporter ||= begin
        io = options[:analyze_only] ? $stderr : $stdout
        Reporter.new(io:, err: $stderr, verbose: options[:verbose], colour: io.tty?)
      end
    end
  end
end
