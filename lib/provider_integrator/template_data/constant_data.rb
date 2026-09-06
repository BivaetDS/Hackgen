# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # One generated constant: comment lines above and the source lines (unindented) of the assignment.
    ConstantData = Data.define(:name, :comment_lines, :lines)

    # Reopened so the builders live outside the Data.define block.
    class ConstantData
      CLASS_BODY_LEVEL = 2

      # A one-line constant.
      def self.single(name, expression, comment: [])
        new(name:, comment_lines: Array(comment), lines: ["#{name} = #{expression}"])
      end

      # A frozen multi-line Hash constant from rendered "key => value" entries.
      def self.hash(name, entries, comment: [])
        lines = Code.hash_lines(entries, open: "#{name} = {", close: "}.freeze")
        new(name:, comment_lines: Array(comment), lines:)
      end

      # Comment and assignment, indented for the class body, as one String.
      def source
        comments = comment_lines.flat_map { |line| Code.wrap(line) }.map { |line| "# #{line}" }
        Code.indent(comments + lines, CLASS_BODY_LEVEL)
      end
    end
  end
end
