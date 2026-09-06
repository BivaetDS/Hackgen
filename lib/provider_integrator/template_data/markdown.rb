# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Markdown fragments for INTEGRATION.md: tables and inline code. Cell text from the spec is
    # escaped so a stray pipe or newline cannot break the table.
    module Markdown
      module_function

      # A GitHub-flavoured table: header row, separator, one row per entry (Arrays of cells).
      def table(headers, rows)
        [row(headers), separator(headers.size), *rows.map { |cells| row(cells) }]
      end

      # `text` (empty cells stay empty rather than becoming two back-ticks).
      def code(text)
        value = text.to_s
        value.empty? ? "" : "`#{value}`"
      end

      # One table cell: pipes escaped, newlines collapsed, nil rendered as a dash.
      def cell(value)
        return "-" if value.nil?

        value.to_s.gsub("|", "|").gsub(/\s*\n\s*/, " ").strip
      end

      def row(cells) = "| #{cells.map { |value| cell(value) }.join(" | ")} |"
      def separator(size) = "|#{"---|" * size}"
    end
  end
end
