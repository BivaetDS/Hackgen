# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Методы", "Методы вне контракта" and "Способы выплаты": the table of the reference guide
      # (method, endpoint, purpose, idempotency), the extra operations, and how request_method works.
      class Methods
        def initialize(doc)
          @doc = doc
          @spec = doc.spec
          @context = doc.context
          @canon = doc.canon
        end

        def sections
          [doc.section("Методы", contract_lines), doc.section("Методы вне контракта", extra_lines),
           doc.section("Способы выплаты (request_method)", request_method_lines)]
        end

        private

        attr_reader :doc, :spec, :context, :canon

        def contract_lines
          doc.table(%w[Метод Endpoint Назначение Idempotency], contract_rows)
        end

        def contract_rows
          [operation_row("create_request", context.create_operation) { |op| idempotency(op) },
           operation_row("fetch_status", context.status_operation) { "-" },
           webhook_row,
           ["check_conditions", "-", conditions_purpose, "-"]]
        end

        def operation_row(name, operation)
          return [name, "-", "заглушка: операция не найдена в спеке", "-"] unless operation

          [name, "#{operation.method} #{operation.path}", operation.summary || operation.operation_id, yield(operation)]
        end

        def idempotency(operation)
          key = operation.idempotency
          key ? "#{key.name} #{key.location}" : "-"
        end

        def webhook_row
          webhook = spec.webhook
          return ["process_callback", "-", "заглушка: webhook не найден (W304)", "-"] unless webhook

          ["process_callback", "#{webhook.method} #{webhook.path}", webhook.summary || "Callback",
           webhook.signature ? webhook.signature.name : "без подписи"]
        end

        def conditions_purpose
          parts = ["предпроверки: `super`"]
          AmountLimits.for(context.create_operation, canon).each do |limit|
            parts << "#{limit.name == "MIN_AMOUNT" ? "сумма >=" : "сумма <="} #{limit.value}"
          end
          parts << "реквизиты способа выплаты (`REQUIRED_REQUISITES`)" if requisites?
          parts.join(", ")
        end

        def requisites? = !ConditionsMethod.required_requisites(context.create_operation).nil?

        def extra_lines
          return ["Все операции спеки покрыты контрактом."] if doc.extra_pairs.empty?

          doc.table(%w[Метод Endpoint Назначение Kind Уверенность], extra_rows) +
            ["", "Публичные методы сервиса вне `#{canon.base_service_class}`; платформа вызывает их по своему " \
                 "усмотрению."]
        end

        def extra_rows
          doc.extra_pairs.map do |operation, name|
            [name, "#{operation.method} #{operation.path}", operation.summary || operation.operation_id,
             operation.kind, operation.confidence]
          end
        end

        def request_method_lines
          methods = context.create_operation&.request_methods
          return ["Спека описывает один способ выплаты: `request_method` не меняет тело запроса."] unless methods

          ["- Значения: #{method_values(methods)} - из #{methods.source} поля `#{methods.discriminator_path}` " \
           "(#{doc.confidence(methods.confidence)})",
           "- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`",
           "- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет " \
           "реквизиты из `REQUIRED_REQUISITES`"]
        end

        def method_values(methods)
          methods.values.map { |v| v == methods.default ? "#{doc.code(v)} (по умолчанию)" : doc.code(v) }.join(", ")
        end
      end
    end
  end
end
