# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Ruby source fragments for templates: literals, hash lines and indentation. Everything that
    # comes from the spec passes through Inflector so identifiers and strings stay valid Ruby.
    # The output of these helpers is text; templates only place it.
    module Code
      INDENT = "  "
      SYMBOL_KEY = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      WORD = /\A[A-Za-z0-9_.-]+\z/
      COMMENT_WIDTH = 100

      # One entry of a brace literal: the rendered "key value" source (possibly multi-line for a
      # nested hash) plus the comment lines printed above it (evidence, TODO markers).
      Entry = Data.define(:code, :comments) do
        # Entry["amount: 1", "Evidence: ...", nil] - nil comments are dropped.
        def self.[](code, *comments) = new(code:, comments: comments.flatten.compact)
      end

      module_function

      # Single-quoted String literal unless escaping is needed (Inflector rule).
      def str(value) = Inflector.ruby_string(value)

      # Ruby literal for any JSON-like value.
      def literal(value) = Inflector.ruby_literal(value)

      # Symbol-style key ("name:") when the name is a plain identifier, else a quoted rocket key.
      def key(name)
        text = name.to_s
        text.match?(SYMBOL_KEY) ? "#{text}:" : "#{str(text)} =>"
      end

      # Lines of a brace literal: +open+ first, entries indented one level with commas between
      # them, +close+ last. Entries are Strings ("key => value") or Entry objects.
      def hash_lines(entries, open: "{", close: "}")
        return ["#{open}#{close}"] if entries.empty?

        last = entries.size - 1
        body = entries.each_with_index.flat_map { |entry, index| entry_lines(entry, comma: index != last) }
        [open, *body, close]
      end

      # Comment lines and code lines of one entry, indented one level, with a trailing comma if asked.
      def entry_lines(entry, comma:)
        entry = Entry[entry] if entry.is_a?(String)
        comments = entry.comments.flat_map { |comment| wrap(comment) }.map { |comment| "# #{comment}" }
        lines = entry.code.split("\n")
        lines[-1] = "#{lines.last}," if comma
        (comments + lines).map { |line| indent_line(line, 1) }
      end

      # Joins +lines+ with +level+ indentation levels (two spaces each); blank lines stay empty.
      def indent(lines, level)
        Array(lines).map { |line| indent_line(line, level) }.join("\n")
      end

      def indent_line(line, level)
        line.to_s.empty? ? "" : "#{INDENT * level}#{line}"
      end

      # A %w[] literal when every value is a plain word, else an Array literal.
      def word_array(values)
        return "[]" if values.empty?
        return "%w[#{values.join(" ")}]" if values.all? { |value| value.to_s.match?(WORD) }

        literal(values)
      end

      # Hash access expression for a dotted provider path: one segment indexes, more segments dig.
      # Array markers ("items[]") are dropped: the array itself is returned.
      def access(receiver, path)
        segments = path.to_s.split(".").map { |segment| segment.delete_suffix("[]") }
        return "#{receiver}[#{str(segments.first)}]" if segments.size == 1

        "#{receiver}.dig(#{segments.map { |segment| str(segment) }.join(", ")})"
      end

      # Wraps +text+ into lines no longer than +width+ characters (for comments).
      def wrap(text, width: COMMENT_WIDTH)
        text.to_s.split("\n").flat_map { |paragraph| wrap_paragraph(paragraph, width) }
      end

      def wrap_paragraph(paragraph, width)
        paragraph.split.each_with_object([+""]) do |word, lines|
          fits = lines.last.empty? || lines.last.length + word.length < width
          fits ? append_word(lines.last, word) : lines << word.dup
        end.map(&:freeze)
      end

      def append_word(line, word)
        line << (line.empty? ? word : " #{word}")
      end
    end
  end
end
