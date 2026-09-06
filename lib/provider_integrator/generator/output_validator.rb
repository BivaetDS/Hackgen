# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Proves the generated files before they are written (docs/PLAN.md 8): the Ruby parses with
    # Prism and carries no ERB leftovers, the service inherits the contract and defines its four
    # methods, RuboCop finds nothing left to fix, fixtures.json parses and its examples satisfy
    # the schemas rebuilt from the IR, INTEGRATION.md has every required section. Fatal findings
    # become E201 events; schema mismatches of provider examples are recorded, not fatal.
    class OutputValidator
      Check = Data.define(:name, :ok, :detail)

      # Kinds of check; every check is named "<file>: <kind>" so the CLI's validation line can read
      # the kind back through .kind without guessing at the wording.
      CHECKS = { syntax: "syntax", leftovers: "no ERB leftovers", rubocop: "rubocop", inherits: "inherits",
                 methods: "contract methods", json: "JSON", schemas: "schemas", sections: "sections" }.freeze

      # The kind (a CHECKS key) of a recorded check name, or nil for a "<what>_present" check.
      def self.kind(name)
        suffix = name.split(": ", 2)[1] or return nil
        CHECKS.key(suffix) || (suffix.start_with?(CHECKS[:inherits]) ? :inherits : nil)
      end

      def initialize(context:, files:, log:)
        @context = context
        @files = files
        @log = log
        @checks = []
      end

      # { "ok" => Boolean, "checks" => [{ "name", "ok", "detail" }] }, the report/CLI summary.
      def call
        ruby_checks(:service, contract: true)
        ruby_checks(:base_contract)
        ruby_checks(:service_spec)
        fixtures_checks(file(:fixtures))
        documentation_checks(file(:documentation))
        { "ok" => @checks.all?(&:ok), "checks" => @checks.map { |check| check.to_h.transform_keys(&:to_s) } }
      end

      private

      attr_reader :context, :files, :log

      def file(kind) = files.find { |item| item.kind == kind.to_s }

      # Records a check; +detail+ is [text when ok, text when failed] or one text for both.
      def record(name, passed, detail, fatal: true, file: nil)
        text = if detail.is_a?(Array)
                 detail.fetch(passed ? 0 : 1)
               else
                 detail
               end
        @checks << Check.new(name:, ok: passed, detail: text)
        log.add("E201", file: file || name, reason: text) if fatal && !passed
        passed
      end

      def missing(name, what)
        record("#{name}_present", false, "#{what} was not generated")
      end

      # ---- Ruby ----------------------------------------------------------------------------------

      # Syntax, leftovers and RuboCop for the Ruby file of +kind+; the contract checks for the service.
      def ruby_checks(kind, contract: false)
        file = file(kind)
        return missing(kind.to_s, "the Ruby file") unless file

        source = file.content
        return unless record("#{file.name}: #{CHECKS[:syntax]}", *syntax(source), file: file.name)

        leftovers_check(file)
        record("#{file.name}: #{CHECKS[:rubocop]}", *rubocop(source, file.name), fatal: false)
        contract_checks(file) if contract
      end

      def leftovers_check(file)
        record("#{file.name}: #{CHECKS[:leftovers]}", !file.content.match?(Template::LEFTOVER),
               ["no ERB tags in the output", "ERB tags remain in the output"], file: file.name)
      end

      def syntax(source)
        errors = Prism.parse(source).errors.map { |error| "#{error.message} (line #{error.location.start_line})" }
        [errors.empty?, errors.empty? ? "Prism: no syntax errors" : errors.join("; ")]
      end

      def rubocop(source, name)
        offenses = RubyFormatter.offenses(source, name:)
        [offenses.empty?, offenses.empty? ? "0 offenses" : offenses.join("; ")]
      end

      def contract_checks(file)
        canon = TemplateData::Canon.new
        record("#{file.name}: #{CHECKS[:inherits]} #{canon.base_service}",
               file.content.include?("< #{canon.base_service}"),
               ["class inherits #{canon.base_service_class}", "class does not inherit #{canon.base_service_class}"],
               file: file.name)
        contract_methods_check(file, canon.contract_methods)
      end

      def contract_methods_check(file, expected)
        absent = expected - method_names(file.content)
        record("#{file.name}: #{CHECKS[:methods]}", absent.empty?,
               ["#{expected.size}/#{expected.size} contract methods", "missing #{absent.join(", ")}"], file: file.name)
      end

      # Names of every `def` in the source, through the Prism AST.
      def method_names(source)
        names = []
        visitor = Class.new(Prism::Visitor) do
          define_method(:visit_def_node) do |node|
            names << node.name.to_s
            super(node)
          end
        end
        Prism.parse(source).value.accept(visitor.new)
        names
      end

      # ---- fixtures ------------------------------------------------------------------------------

      def fixtures_checks(file)
        return missing("fixtures", "fixtures.json") unless file

        data = JSON.parse(file.content)
        record("#{file.name}: #{CHECKS[:json]}", true, "parses, #{data.size} top-level entries")
        schema_check(file, data)
      rescue JSON::ParserError => e
        record("#{file.name}: #{CHECKS[:json]}", false, e.message, file: file.name)
      end

      def schema_check(file, data)
        problems = FixtureSchemaCheck.new(context, data).problems
        record("#{file.name}: #{CHECKS[:schemas]}", problems.empty?,
               ["examples satisfy the schemas rebuilt from the IR", problems.join("; ")], fatal: false)
      end

      # ---- documentation -------------------------------------------------------------------------

      def documentation_checks(file)
        return missing("documentation", "INTEGRATION.md") unless file

        headings = file.content.scan(/^## (.+)$/).flatten.map(&:strip)
        absent = TemplateData::Documentation::REQUIRED_SECTIONS.reject { |title| headings.include?(title) }
        record("#{file.name}: #{CHECKS[:sections]}", absent.empty?,
               ["#{headings.size} sections", "missing sections: #{absent.join(", ")}"], file: file.name)
        leftovers_check(file)
      end
    end
  end
end
