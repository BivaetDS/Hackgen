# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Building blocks of the generated RSpec file, each rendering itself indented for its nesting
    # level (1 inside `RSpec.describe`, 2 inside a `describe`): `let` definitions, `do ... end`
    # blocks (before, it) and `describe` groups. The template only prints `source`.
    module SpecBlock
      ONE_LINE_WIDTH = 100

      # `header do ... end` with optional comment lines above it.
      Block = Data.define(:header, :lines, :level, :comment)

      # `let(:name) { expression }` on one line when it fits, else a do-block.
      Let = Data.define(:name, :lines, :level, :comment)

      # `describe '#method' do` holding lets, blocks and methods (anything with #source).
      Group = Data.define(:header, :children, :level)

      # Reopened for the builder and the rendering (outside the Data.define block).
      class Block
        def self.build(header, lines, level:, comment: [])
          new(header:, lines: Array(lines), level:, comment: Array(comment))
        end

        def source
          opening = Code.indent(comment_lines + ["#{header} do"], level)
          "#{opening}\n#{Code.indent(lines, level + 1)}\n#{Code.indent_line("end", level)}"
        end

        def comment_lines = comment.flat_map { |line| Code.wrap(line) }.map { |line| "# #{line}" }
      end

      # Reopened for the builder and the rendering (outside the Data.define block).
      class Let
        def self.build(name, lines, level: 1, comment: [])
          new(name:, lines: Array(lines), level:, comment: Array(comment))
        end

        def source
          block = Block.build("let(:#{name})", lines, level:, comment:)
          return block.source unless one_line?

          Code.indent(block.comment_lines + ["let(:#{name}) { #{lines.first} }"], level)
        end

        private

        def one_line?
          lines.size == 1 && lines.first.length + "let(:#{name}) {  }".length + (level * 2) <= ONE_LINE_WIDTH
        end
      end

      # Reopened for the builder and the rendering (outside the Data.define block).
      class Group
        def self.build(header, children, level: 1)
          new(header:, children:, level:)
        end

        # The group with its children separated by blank lines (consecutive lets stay together).
        def source
          inner = children.each_with_index.map { |child, index| "#{separator(index)}#{child.source}" }.join
          "#{Code.indent_line("#{header} do", level)}\n#{inner}\n#{Code.indent_line("end", level)}"
        end

        private

        def separator(index)
          return "" if index.zero?

          children[index - 1].is_a?(Let) && children[index].is_a?(Let) ? "\n" : "\n\n"
        end
      end
    end
  end
end
