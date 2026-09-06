# frozen_string_literal: true

module ProviderIntegrator
  # Human-readable CLI output. The wording follows the reference transcript in docs/TZ.md and
  # docs/PLAN.md 7: what was read, what each operation was recognised as, how the provider
  # authenticates, how the callback is signed, the generation and validation lines, then everything
  # a human must confirm and where the files went. Details go behind --verbose, failures to stderr.
  # The Reporter is also the Pipeline observer (#parsed, #generating, #generated, #spec_ran).
  class Reporter
    WRAP = 78
    LEVEL_COLOURS = { "error" => :red, "warning" => :yellow, "info" => :cyan }.freeze
    GENERATING = ["service", "integration guide", "test fixtures", "service spec", "contract stub and report"].freeze
    # The three deliverables of the case study first, then the extras (presentation order only).
    OUTPUT_ORDER = %w[service documentation fixtures service_spec base_contract report].freeze
    FAILURE_TITLES = { spec: "The spec cannot be used:", generation: "Generation failed; nothing was written:" }.freeze

    def initialize(io: $stdout, err: $stderr, verbose: false, colour: true)
      @io = io
      @err = err
      @verbose = verbose
      @pastel = Pastel.new(enabled: colour)
    end

    # ---- Pipeline observer -----------------------------------------------------------------------

    # After the parse: the analysis block (errors are reported by #finish).
    def parsed(result)
      analysis(result.spec) if result.success?
    end

    # Before the generator runs: the "Generating ..." lines of the reference transcript.
    def generating(_slug, _output_dir)
      GENERATING.each { |what| line("Generating #{what}...") }
    end

    # After the generator ran: the validator's verdict, plus every failed check.
    def generated(result)
      verdict = ValidationLine.new(result.validation)
      line("Validating output... #{verdict.ok? ? verdict.text : pastel.red(verdict.text)}")
      verdict.failures.each { |failure| line("  #{pastel.red("FAILED")} #{failure}") }
    end

    # After --run-spec: one stable success line, or the captured RSpec output on stderr.
    def spec_ran(run)
      return line("Running generated spec... RSpec #{run.examples} examples, #{run.failures} failures") if run.ok?

      failed_spec_run(run)
    end

    # ---- Blocks ----------------------------------------------------------------------------------

    # The whole analysis block for a parsed spec.
    def analysis(spec)
      header(spec)
      endpoints(spec)
      roles(spec)
      authentication(spec)
      webhook(spec)
    end

    # The end of a run: warnings, what needs confirmation and the output paths, or the failure.
    def finish(result)
      case result.status
      when :ok then completed(result)
      when :spec, :generation then failure(FAILURE_TITLES.fetch(result.status), result.errors)
      when :spec_failed then failed_spec(result)
      when :write then fatal("Cannot write output: #{result.error.message}")
      when :internal then internal(result.error)
      end
    end

    # "Completed with N warnings:" plus one line per event worth showing.
    def summary(events)
      shown = events.select { |event| verbose ? !event.error? : event.warning? }
      return line(pastel.green("Completed with no warnings")) if shown.empty?

      line(pastel.yellow("Completed with #{shown.count(&:warning?)} warnings:"))
      shown.each { |event| event_line(event) }
    end

    private

    attr_reader :io, :err, :verbose, :pastel

    def line(text = "")
      io.puts(text)
    end

    def failed_spec_run(run)
      err.puts(pastel.red("Running generated spec... FAILED"))
      err.puts(run.error) if run.error
      write_spec_output(run.output)
    end

    def write_spec_output(text)
      err.write(text)
      err.puts unless text.empty? || text.end_with?("\n")
    end

    # ---- analysis --------------------------------------------------------------------------------

    def header(spec)
      format = spec.spec_format
      converted = format.converted_from ? " (converted from Swagger #{format.converted_from})" : ""
      line("Parsing spec... OpenAPI #{format.openapi}#{converted}, #{spec.provider.title} #{spec.provider.version}")
    end

    def endpoints(spec)
      names = spec.operations.map { |operation| "#{operation.method} #{operation.path}" }
      line(wrap("Found #{names.size} endpoints: ", names.join(", ")))
    end

    # The four contract slots first, then everything the spec offers beyond the contract.
    def roles(spec)
      spec.contract_operations.each do |operation|
        line("  #{operation.canonical_method.ljust(16)} -> #{operation.method} #{operation.path} " \
             "(confidence #{operation.confidence})")
      end
      extras = spec.operations.reject(&:in_contract)
      return if extras.empty?

      line("  #{"extra".ljust(16)} -> #{extras.map(&:kind).uniq.join(", ")} (outside the BaseService contract)")
    end

    # "Auth: ApiKeyAuth (header: X-API-Key)" as in the reference; the scheme type under --verbose.
    def authentication(spec)
      auth = spec.authentication
      return line("Auth: none declared") if auth.type == "none"

      where = auth.location ? " (#{auth.location}: #{auth.name})" : ""
      detail = verbose ? " [#{auth.type}, confidence #{auth.confidence}]" : ""
      line("Auth: #{auth.scheme_name}#{where}#{detail}")
    end

    def webhook(spec)
      hook = spec.webhook
      return line(pastel.yellow("Webhook: not declared - process_callback is generated as a stub")) unless hook

      signature = hook.signature
      return line("Webhook: #{hook.method} #{hook.path} (no signature declared)") unless signature

      line("Webhook signature: #{signature.name} (#{signature.algorithm.upcase}) on #{hook.method} #{hook.path}")
    end

    # ---- outcome ---------------------------------------------------------------------------------

    def completed(result)
      summary(result.events)
      confirmations(result)
      output(result)
    end

    def failed_spec(result)
      err.puts(pastel.red("Generated spec failed; files were kept in #{result.output_dir}."))
      output(result)
    end

    # Critical inferences never stay silent (docs/PLAN.md 5): one line with the tally of codes.
    def confirmations(result)
      items = TemplateData::Confirmations.new(result.spec).items
      return if items.empty?

      tally = items.map(&:code).tally.map { |code, count| count > 1 ? "#{code} x#{count}" : code }
      pointer = result.files.empty? ? "" : " - see INTEGRATION.md «Требует подтверждения» and generation_report.json"
      line("Requires confirmation: #{items.size} items (#{tally.join(", ")})#{pointer}")
    end

    def output(result)
      return if result.files.empty?

      line("Output:")
      ordered = result.files.sort_by { |file| OUTPUT_ORDER.index(file.kind) || OUTPUT_ORDER.size }
      ordered.each { |file| line("  #{file.path}") }
    end

    def failure(title, events)
      err.puts(pastel.red(title))
      events.each { |event| event_line(event, err) }
    end

    def fatal(text)
      err.puts(pastel.red(text))
    end

    # A bug, not a user error: the message always, the backtrace only when asked for.
    def internal(error)
      fatal("Internal error: #{error.class}: #{error.message}")
      return err.puts(pastel.dim("Run again with --verbose to see the backtrace.")) unless verbose

      Array(error.backtrace).each { |frame| err.puts("    #{frame}") }
    end

    def event_line(event, target = io)
      colour = LEVEL_COLOURS.fetch(event.level, :white)
      target.puts("  #{pastel.decorate(event.code, colour)} #{event.message}")
      target.puts("      at #{event.location}") if verbose && event.location
    end

    # "Found 5 endpoints: a, b, c" wrapped at WRAP columns, continuation lines aligned under the list.
    def wrap(prefix, text)
      indent = " " * prefix.length
      text.split(", ").each_with_object([prefix.dup]) do |word, lines|
        append(lines, word, indent, lines.last == prefix)
      end.join("\n")
    end

    def append(lines, word, indent, first)
      if !first && lines.last.length + word.length + 2 > WRAP
        lines[-1] = "#{lines.last},"
        lines << "#{indent}#{word}"
      else
        lines[-1] += first ? word : ", #{word}"
      end
    end
  end
end
