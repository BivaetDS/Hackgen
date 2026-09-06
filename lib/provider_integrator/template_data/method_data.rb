# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # One generated method as a template prints it: comment lines above `def`, the signature, the
    # body already indented for the nesting `level` of the `def` (2 inside
    # `class Provider; class XService`, 1 inside an `RSpec.describe` block), and rescue clauses as
    # [exception, one-line body] pairs.
    MethodData = Data.define(:name, :comment_lines, :signature, :body, :rescues, :level)

    # Reopened so the constants and builders live outside the Data.define block.
    class MethodData
      BODY_LEVEL = 3
      DEF_LEVEL = 2

      # +lines+ are unindented body lines; +params+ the parameter list source ("operation, payload = {}").
      # rubocop:disable-next Metrics/ParameterLists -- every keyword is a distinct part of a method definition.
      def self.build(name:, lines:, params: "", comment: [], rescues: [], level: DEF_LEVEL)
        signature = params.empty? ? name : "#{name}(#{params})"
        new(name:, comment_lines: Array(comment), signature:, body: Code.indent(lines, level + 1), rescues:, level:)
      end

      # The whole method, indented for its nesting level, as one String.
      def source
        [*Code.indent(header_lines, level).split("\n"), body, *rescue_lines, Code.indent_line("end", level)]
          .join("\n")
      end

      def header_lines
        comment_lines.flat_map { |line| Code.wrap(line) }.map { |line| "# #{line}" } << "def #{signature}"
      end

      def rescue_lines
        rescues.flat_map do |exception, outcome|
          [Code.indent_line("rescue #{exception}", level), Code.indent_line(outcome, level + 1)]
        end
      end
    end
  end
end
