# frozen_string_literal: true

module ProviderIntegrator
  # The one pass of the product (docs/PLAN.md 1): Parser -> Generator (which validates its own
  # output) -> files on disk under <output>/<slug>/. It is also the only place where exceptions
  # become a status: nothing escapes to the CLI or the web layer. Progress is reported to an
  # observer (`parsed`, `generating`, `generated`) so the CLI can print each stage as it happens.
  class Pipeline
    # Observer that ignores every stage (library callers, the web layer).
    class NullObserver
      def parsed(_result) = nil
      def generating(_slug, _output_dir) = nil
      def generated(_result) = nil
    end

    # Runs one pipeline pass: what to run on goes to .new, how to run it to #call.
    def self.call(analyze_only: false, observer: NullObserver.new, **) = new(**).call(analyze_only:, observer:)

    # +path+ is the OpenAPI document, +provider+ an optional slug for the class and file names
    # (must pass Inflector.slug?), +output+ the root directory, +overrides+ an optional overrides.yml.
    def initialize(path:, provider: nil, output: "./output", overrides: nil)
      raise ArgumentError, "provider slug #{provider.inspect} is not a safe identifier" unless slug_ok?(provider)

      @path = path
      @provider = provider
      @output = output
      @overrides = overrides
    end

    # Returns a Models::PipelineResult; never raises. +analyze_only+ stops after the parse.
    def call(analyze_only: false, observer: NullObserver.new)
      @analyze_only = analyze_only
      @observer = observer
      @parsed = Parser.call(path: @path, overrides: @overrides)
      @observer.parsed(@parsed)
      return result(:spec) unless @parsed.success?
      return result(:ok) if @analyze_only

      generate
      return result(:generation) unless @generation.success?

      write
      result(:ok, files: @generation.files)
    rescue WriteError => e
      result(:write, error: e)
    rescue StandardError => e
      result(:internal, error: e)
    end

    private

    def slug_ok?(provider) = provider.nil? || provider.empty? || Inflector.slug?(provider)

    def generate
      slug = @provider.nil? || @provider.empty? ? @parsed.spec.provider.slug : @provider
      @output_dir = File.join(@output, slug)
      @observer.generating(slug, @output_dir)
      @generation = Generator.call(spec: @parsed.spec, provider: slug, output_dir: @output_dir)
      @observer.generated(@generation)
    end

    # Files are written only after every check passed, so output/ never holds a broken service.
    def write
      @generation.files.each { |file| Files.write(file.path, file.content) }
    rescue SystemCallError, IOError => e
      raise WriteError, "cannot write #{@output_dir}: #{e.message.sub(/ @ \w+ - .*\z/m, "")}"
    end

    def result(status, files: [], error: nil)
      Models::PipelineResult.new(status:, spec: @parsed&.spec, events:, files:, output_dir: @output_dir, error:)
    end

    # Analysis events first, then the generator's, in canonical IR order.
    def events
      log = EventLog.new(@parsed ? @parsed.events : [])
      log.concat(@generation.events) if @generation
      log.sorted
    end
  end
end
