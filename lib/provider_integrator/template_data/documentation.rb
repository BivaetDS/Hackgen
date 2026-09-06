# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Everything integration.md.erb prints: a title, an intro line and the sections of the guide
    # (docs/PLAN.md 6) as ready Markdown lines. The wording of the headings follows the reference
    # INTEGRATION.md in docs/TZ.md; the required ones are checked by the output validator.
    class Documentation
      Section = Data.define(:title, :lines)

      REQUIRED_SECTIONS = ["Авторизация", "Методы", "Маппинг статусов", "Обработка ошибок", "Webhook signature",
                           "ProviderGateway config", "Требует подтверждения"].freeze

      def initialize(context)
        @context = context
        @spec = context.spec
        @canon = Canon.new
        @service = context.service_data
      end

      def title = "#{spec.provider.title.split(/\s+/).first} Integration Guide"

      def intro
        "Сгенерировано provider-integrator #{VERSION} из «#{spec.provider.title}» #{spec.provider.version} " \
          "(OpenAPI #{spec.spec_format.openapi}). Сервис: `#{canon.namespace}::#{context.class_name}` " \
          "(`#{context.service_file_name}`), контракт `#{canon.base_service_class}`."
      end

      # Sections in document order; empty ones are dropped.
      def sections
        [DocumentationSections::Setup, DocumentationSections::Methods, DocumentationSections::Fields,
         DocumentationSections::Statuses, DocumentationSections::Webhook, DocumentationSections::Tests,
         DocumentationSections::Review]
          .flat_map { |builder| builder.new(self).sections }
          .reject { |section| section.lines.empty? }
      end

      # ---- shared by the section builders --------------------------------------------------------

      attr_reader :context, :spec, :canon, :service

      # A section without trailing blank lines (the template separates sections itself).
      def section(title, lines)
        trimmed = lines.dup
        trimmed.pop while trimmed.last == ""
        Section.new(title:, lines: trimmed)
      end

      def code(text) = Markdown.code(text)
      def table(headers, rows) = Markdown.table(headers, rows)

      # Extra operations paired with the method names the service gave them.
      def extra_pairs = context.extra_operations.zip(service.extra_methods.map(&:name))

      # { http => ErrorMapping } as ERROR_MAP sees it.
      def error_mappings = ServiceConstants.error_mappings(spec, context)

      def confirmations = @confirmations ||= Confirmations.new(spec)

      def confidence(value) = "уверенность #{value}"
    end
  end
end
