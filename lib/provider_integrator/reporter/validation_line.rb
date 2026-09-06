# frozen_string_literal: true

module ProviderIntegrator
  class Reporter
    # The one-line verdict of the output validator for the CLI ("Ruby syntax OK, RuboCop 0 offenses,
    # 4/4 contract methods, fixtures valid, INTEGRATION.md 12 sections"), built from the checks of
    # GenerationResult#validation by their kind, never by parsing their wording.
    class ValidationLine
      def initialize(validation)
        @ok = validation.fetch("ok")
        @checks = validation.fetch("checks")
      end

      def ok? = @ok

      # The verdict; every failed part names itself so the line reads right even on failure.
      def text = [missing, ruby, rubocop, methods, fixtures, sections].compact.join(", ")

      # Failed checks as "name: detail" lines (fatal or not).
      def failures
        @checks.reject { |check| check["ok"] }.map { |check| "#{check["name"]}: #{check["detail"]}" }
      end

      private

      def of(kind) = @checks.select { |check| Generator::OutputValidator.kind(check["name"]) == kind }
      def all_ok?(kind) = of(kind).all? { |check| check["ok"] }

      def missing
        absent = @checks.select { |check| check["name"].end_with?("_present") && !check["ok"] }
        absent.empty? ? nil : absent.map { |check| check["detail"] }.join(", ")
      end

      def ruby
        return nil if of(:syntax).empty?

        all_ok?(:syntax) && all_ok?(:leftovers) && all_ok?(:inherits) ? "Ruby syntax OK" : "Ruby syntax FAILED"
      end

      def rubocop
        return nil if of(:rubocop).empty?

        offenses = of(:rubocop).sum { |check| check["ok"] ? 0 : check["detail"].split("; ").size }
        "RuboCop #{offenses} offenses"
      end

      # "4/4 contract methods" or "missing fetch_status" straight from the check.
      def methods
        check = of(:methods).first or return nil
        check["ok"] ? check["detail"] : "contract methods: #{check["detail"]}"
      end

      def fixtures
        return nil if of(:json).empty?
        return "fixtures.json invalid" unless all_ok?(:json)

        all_ok?(:schemas) ? "fixtures valid" : "fixtures: examples differ from the schemas"
      end

      def sections
        check = of(:sections).first or return nil
        "INTEGRATION.md #{check["detail"]}"
      end
    end
  end
end
