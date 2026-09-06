# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Маппинг полей": request payloads (per payout method) with their platform sources, units
      # and requirements, then the response fields with their canonical names.
      class Fields
        REQUEST_HEADERS = ["Поле провайдера", "Источник на платформе", "Обязательно", "Примечание"].freeze
        RESPONSE_HEADERS = ["Поле провайдера", "Канон Space Payments", "Тип", "Примечание"].freeze

        def initialize(doc)
          @doc = doc
          @context = doc.context
          @service = doc.service
        end

        def sections
          [doc.section("Маппинг полей", request_blocks + response_blocks + extra_blocks)]
        end

        private

        attr_reader :doc, :context, :service

        def request_blocks
          operation = context.create_operation
          return ["Create-операция не найдена: тело запроса не сформировано."] unless operation

          branches = operation.request_methods ? operation.request_methods.values : [nil]
          branches.flat_map { |branch| request_block(operation, branch) }
        end

        def request_block(operation, branch)
          suffix = branch && " (request_method #{doc.code(branch)})"
          rows = service.payload_docs.fetch(["create", branch], [])
          ["### Запрос create_request#{suffix}", "", "`#{media(operation)}`", "", *doc.table(REQUEST_HEADERS, rows), ""]
        end

        def media(operation)
          body = operation.request_body
          [operation.method, operation.path, body&.content_type, body&.schema_name].compact.join(" ")
        end

        def response_blocks
          [["create_request", context.create_operation],
           ["fetch_status", context.status_operation]].flat_map do |name, op|
            next [] unless op && !op.response_fields.empty?

            ["### Ответ #{name} (#{op.success_codes.join("/")}) -> платформа", "", *response_table(op), ""]
          end
        end

        def response_table(operation)
          rows = operation.response_fields.map do |field|
            [field.provider_path, field.canonical || "-", field.type || "-", response_note(field)]
          end
          doc.table(RESPONSE_HEADERS, rows)
        end

        def response_note(field)
          return "см. «Маппинг статусов»" if field.canonical == "status"
          return "сохраняется как provider_operation_id" if field.canonical == "provider_operation_id"
          return "enum: #{field.enum.join(", ")}" if field.enum

          field.description || "-"
        end

        def extra_blocks
          doc.extra_pairs.flat_map do |operation, name|
            rows = service.payload_docs[["extra", name]]
            next [] unless rows

            ["### Запрос #{name}", "", "`#{operation.method} #{operation.path}`", "",
             *doc.table(REQUEST_HEADERS, rows), ""]
          end
        end
      end
    end
  end
end
