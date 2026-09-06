# frozen_string_literal: true

module ProviderIntegrator
  # Human-readable CLI output. The wording follows the reference transcript in docs/TZ.md: what was
  # read, what each operation was recognised as, how the provider authenticates, how the callback is
  # signed, and finally everything that needs a human to confirm it. Details go behind --verbose.
  class Reporter
    WRAP = 78
    LEVEL_COLOURS = { "error" => :red, "warning" => :yellow, "info" => :cyan }.freeze

    def initialize(io: $stdout, verbose: false, colour: true)
      @io = io
      @verbose = verbose
      @pastel = Pastel.new(enabled: colour)
    end

    # The whole analysis block for a parsed spec.
    def analysis(spec)
      header(spec)
      endpoints(spec)
      roles(spec)
      authentication(spec)
      webhook(spec)
    end

    # "Completed with N warnings:" plus one line per event worth showing.
    def summary(events)
      shown = events.select { |event| verbose ? !event.error? : event.warning? }
      return line(pastel.green("Completed with no warnings")) if shown.empty?

      line(pastel.yellow("Completed with #{shown.count(&:warning?)} warnings:"))
      shown.each { |event| event_line(event) }
    end

    # One error event, the only thing printed when a spec cannot be used.
    def failure(events)
      events.select(&:error?).each { |event| event_line(event) }
    end

    # A plain line (used by the CLI for progress and paths).
    def line(text = "")
      io.puts(text)
    end

    # A dimmed note that does not claim to be a result.
    def note(text)
      line(pastel.dim(text))
    end

    private

    attr_reader :io, :verbose, :pastel

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

    def authentication(spec)
      auth = spec.authentication
      return line("Auth: none declared") if auth.type == "none"

      where = auth.location ? " (#{auth.location}: #{auth.name})" : ""
      line("Auth: #{auth.scheme_name} [#{auth.type}]#{where}")
    end

    def webhook(spec)
      hook = spec.webhook
      return line(pastel.yellow("Webhook: not declared - process_callback is generated as a stub")) unless hook

      signature = hook.signature
      return line("Webhook: #{hook.method} #{hook.path} (no signature declared)") unless signature

      line("Webhook signature: #{signature.name} (#{signature.algorithm.upcase}) on #{hook.method} #{hook.path}")
    end

    def event_line(event)
      colour = LEVEL_COLOURS.fetch(event.level, :white)
      io.puts("  #{pastel.decorate(event.code, colour)} #{event.message}")
      io.puts("      at #{event.location}") if verbose && event.location
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
