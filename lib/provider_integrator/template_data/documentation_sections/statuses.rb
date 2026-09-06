# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Маппинг статусов", "Обработка ошибок" and "ProviderGateway config".
      class Statuses
        def initialize(doc)
          @doc = doc
          @spec = doc.spec
          @canon = doc.canon
        end

        def sections
          [doc.section("Маппинг статусов", status_lines), doc.section("Обработка ошибок", error_lines),
           doc.section("ProviderGateway config", gateway_lines)]
        end

        private

        attr_reader :doc, :spec, :canon

        def status_lines
          if spec.statuses.empty?
            return ["Спека не объявляет enum статусов: `map_status` возвращает `#{canon.default_status}` (W201)."]
          end

          doc.table(["Provider", "Space Payments", "Основание"], status_rows) +
            ["", "Неизвестный статус -> `#{canon.default_status}` до следующего уведомления (`map_status`)."]
        end

        def status_rows
          spec.statuses.map do |mapping|
            [mapping.provider, mapping.canonical,
             "#{mapping.evidence.join("; ")} (#{doc.confidence(mapping.confidence)})"]
          end
        end

        def error_lines
          if doc.error_mappings.empty?
            return ["Спека не объявляет ответов с ошибками: любой не-2xx ответ -> `provider_error` по HTTP-коду."]
          end

          doc.table(["HTTP", "Provider code", "Канон", "Действие", "Примечание"], error_rows) + ["", *error_notes]
        end

        def error_rows
          doc.error_mappings.map do |http, error|
            [http, error.provider_code || "-", error.canonical, canon.action_label(error.action), error_note(error)]
          end
        end

        def error_note(error)
          parts = []
          parts << "Retry-After из #{error.retry_after == "header" ? "заголовка" : "тела ответа"}" if error.retry_after
          parts << error.evidence.grep(/\Anote:/).first&.delete_prefix("note: ")
          text = parts.compact.join("; ")
          text.empty? ? "-" : text
        end

        def error_notes
          [duplicate_note,
           "- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).",
           "- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными " \
           "аргументами (docs/ASSUMPTIONS.md)."].compact
        end

        def duplicate_note
          create = doc.context.create_operation
          return nil if create.nil? || create.idempotent_duplicate_codes.empty?

          "- #{create.idempotent_duplicate_codes.join(", ")} на `#{create.method} #{create.path}` - идемпотентный " \
            "дубль: провайдер возвращает исходную выплату, сервис считает это успехом."
        end

        def gateway_lines
          config = spec.gateway_config
          return ["Create-операция не найдена: конфиг не выведен."] unless config

          json = "{ \"external_method\": #{JSON.generate(config.external_method)}, " \
                 "\"gateway\": #{JSON.generate(config.gateway)} }"
          ["```json", json, "```", "",
           "- Направление: #{config.direction}, валюта: #{config.currency || "не определена"}, " \
           "способ: #{config.method} (#{doc.confidence(config.confidence)})",
           "- Evidence: #{config.evidence.join("; ")}"]
        end
      end
    end
  end
end
