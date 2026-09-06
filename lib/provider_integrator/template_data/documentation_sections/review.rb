# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Требует подтверждения" and "Допущения": every warning and critical inference with its
      # evidence and the place in the code, then the assumptions about the platform contract.
      class Review
        OVERRIDE_KEYS = %w[operations amount_unit required_if signature status_map error_actions].freeze
        HEADERS = ["Код", "Уровень", "Вывод", "Основание", "Где в коде"].freeze

        def initialize(doc)
          @doc = doc
          @canon = doc.canon
        end

        def sections
          [doc.section("Требует подтверждения", confirmation_lines), doc.section("Допущения", assumption_lines)]
        end

        private

        attr_reader :doc, :canon

        def confirmation_lines
          items = doc.confirmations.items
          return intro + ["Предупреждений нет."] if items.empty?

          rows = items.map { |item| [item.code, item.level, item.message, evidence(item), item.where] }
          intro + doc.table(HEADERS, rows)
        end

        def intro
          ["Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) " \
           "попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: " \
           "`overrides.yml` (ключи #{OVERRIDE_KEYS.join(", ")}).", ""]
        end

        def evidence(item)
          item.evidence.empty? ? "см. вывод" : item.evidence.join("; ")
        end

        def assumption_lines
          ["Реальный `#{canon.base_service_class}` не предоставлен; сервис написан под контракт, реконструированный " \
           "по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):",
           "", *assumptions]
        end

        def assumptions
          [operation_assumption, result_assumption, client_assumption,
           "- `#{canon.approve}(id)` / `#{canon.reject}(id, error_code)` завершают операцию на платформе",
           "- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех"]
        end

        def operation_assumption
          "- `#{canon.accessor("amount")}` в основных единицах валюты; реквизиты - " \
            "`#{canon.accessor("requisite")}` одним хешем с ключом по способу выплаты"
        end

        def result_assumption
          "- `#{canon.success}(**details)` / `#{canon.failure}(<символ>, <i18n-код>, **details)`; символы: " \
            "#{failure_symbols.join(", ")}"
        end

        def client_assumption
          "- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не " \
            "бросает исключений сам; #{canon.exceptions.values.join(" и ")} перехватываются на случай, если бросает"
        end

        def failure_symbols
          canon.error_codes.map { |code| canon.failure_for_error(code)[/:\w+/] }.uniq
        end
      end
    end
  end
end
