# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # One generated method as the service template prints it: comment lines above `def`, the
    # signature, the body already indented for a method inside `class Provider; class XService`,
    # and rescue clauses as [exception, one-line body] pairs.
    MethodData = Data.define(:name, :comment_lines, :signature, :body, :rescues)

    # Reopened so the constants and builders live outside the Data.define block.
    class MethodData
      BODY_LEVEL = 3
      DEF_LEVEL = 2

      # +lines+ are unindented body lines; +params+ the parameter list source ("operation, payload = {}").
      def self.build(name:, lines:, params: "", comment: [], rescues: [])
        signature = params.empty? ? name : "#{name}(#{params})"
        new(name:, comment_lines: Array(comment), signature:, body: Code.indent(lines, BODY_LEVEL), rescues:)
      end

      # The whole method, indented for the class body, as one String.
      def source
        [*Code.indent(header_lines, DEF_LEVEL).split("\n"), body, *rescue_lines, Code.indent_line("end", DEF_LEVEL)]
          .join("\n")
      end

      def header_lines
        comment_lines.flat_map { |line| Code.wrap(line) }.map { |line| "# #{line}" } << "def #{signature}"
      end

      def rescue_lines
        rescues.flat_map do |exception, outcome|
          [Code.indent_line("rescue #{exception}", DEF_LEVEL), Code.indent_line(outcome, BODY_LEVEL)]
        end
      end
    end
  end
end
