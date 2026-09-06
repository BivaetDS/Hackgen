# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Normalizes generated Ruby with RuboCop's autocorrect, entirely in memory: the source goes in
    # through the `stdin` option and the corrected text comes back from the same option, so nothing
    # is written to disk and the Windows text-mode CRLF problem never arises. The configuration is
    # templates/rubocop_generated.yml (single quotes, table-aligned rockets, no Metrics).
    # RuboCop is deterministic, so formatting keeps byte-identical output across runs.
    class RubyFormatter
      CONFIG = File.join(Template::DIR, "rubocop_generated.yml")

      class << self
        # Formats +source+ (a String) for the file +name+; returns the corrected source.
        def format(source, name: "generated.rb")
          cache[[:format, source, name]] ||= new.format(source, name:)
        end

        # Offenses RuboCop still reports for +source+ ("Cop/Name:line message"), empty when clean.
        def offenses(source, name: "generated.rb")
          cache[[:offenses, source, name]] ||= new.offenses(source, name:)
        end

        # Formatting is pure, so identical input is processed once per process.
        def cache = @cache ||= {}
      end

      def format(source, name:)
        options = { stdin: source.dup, autocorrect: true, autocorrect_all: true }
        run(options, name)
        normalize(options[:stdin])
      end

      def offenses(source, name:)
        collected = []
        formatter = Class.new(RuboCop::Formatter::BaseFormatter) do
          define_method(:file_finished) do |_file, offenses|
            collected.concat(offenses.map { |offense| "#{offense.cop_name}:#{offense.line} #{offense.message}" })
          end
        end
        run({ stdin: source.dup }, name, formatter)
        collected.sort
      end

      private

      def run(options, name, formatter = nil)
        require "rubocop"
        options[:formatters] = formatter ? [[formatter, File::NULL]] : [["quiet", File::NULL]]
        options[:force_exclusion] = false
        store = RuboCop::ConfigStore.new
        store.options_config = CONFIG
        RuboCop::Runner.new(options, store).run([name])
      end

      # RuboCop returns the text as it was given; generated files are LF-only by contract.
      def normalize(text)
        "#{text.gsub("\r\n", "\n").rstrip}\n"
      end
    end
  end
end
