# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Webhook signature": the signature formula of the reference guide, the payload convention
      # process_callback expects, the events and the answer the provider wants back.
      class Webhook
        NO_WEBHOOK = "Спека не описывает webhook (W304): `process_callback` - заглушка, статус получать через " \
                     "`fetch_status`."
        NO_SIGNATURE = "Спека не описывает подпись уведомлений: `process_callback` не аутентифицирует webhook - " \
                       "**подтвердить у провайдера**."

        def initialize(doc)
          @doc = doc
          @webhook = doc.spec.webhook
          @canon = doc.canon
          @verifier = SignatureVerifier.new(doc.service, @webhook.signature) if @webhook&.signature
        end

        def sections
          [doc.section("Webhook signature", lines)]
        end

        private

        attr_reader :doc, :webhook, :canon, :verifier

        def lines
          return [NO_WEBHOOK] unless webhook

          [formula, "", *endpoint_lines, "", *payload_lines, "", *event_lines, "", *response_lines]
        end

        def formula
          return NO_SIGNATURE unless verifier

          message = verifier.message == "raw_body" ? "body" : "sorted_values(payload)"
          "#{verifier.algorithm.upcase}(#{message}, #{canon.callback_secret_key}) -> #{verifier.encoding} -> " \
            "#{webhook.signature.name} (#{webhook.signature.location})"
        end

        def endpoint_lines
          [endpoint_line, *signature_lines]
        end

        def endpoint_line
          "- Endpoint провайдера: `#{webhook.method} #{webhook.path}` (#{webhook.operation_id}); найден: " \
            "#{webhook.source} (#{doc.confidence(webhook.confidence)})"
        end

        def signature_lines
          signature = webhook.signature
          return [] unless signature

          defaulted = signature.encoding == "unknown" || signature.message == "unknown"
          origin = defaulted ? "**не указаны в спеке (W301)**: приняты дефолты канона" : "из спеки"
          ["- Evidence подписи: #{signature.evidence.join("; ")}",
           "- Кодировка и канонизация #{origin}",
           "- Сравнение подписи в постоянное время (`secure_compare`); секрет - " \
           "`#{canon.credential(canon.callback_secret_key)}`"]
        end

        def payload_lines
          body = canon.callback_key("body")
          raw = canon.callback_key("raw_body")
          ["- Payload для `process_callback`: разобранный JSON уведомления либо конверт `{ '#{body}' => <JSON>, " \
           "'#{canon.callback_key("headers")}' => { '<Signature-Header>' => ... }, '#{raw}' => '<сырое тело>' }`",
           "- Без `#{raw}` подпись проверяется по `JSON.generate(#{body})` - ненадёжно при иной сериализации " \
           "у провайдера",
           "- Поля payload: событие `#{webhook.event_field || "-"}`, статус `#{webhook.status_field || "-"}`, " \
           "id операции `#{webhook.id_field || "-"}`, код ошибки `#{webhook.error_code_path || "-"}`"]
        end

        def event_lines
          if webhook.events.empty?
            return ["- События не объявлены: статус берётся из поля `#{webhook.status_field}` через STATUS_MAP"]
          end

          rows = webhook.events.map { |event| [event.value, event.canonical_status || "-", outcome(event)] }
          doc.table(["Событие", "Статус Space Payments", "Действие сервиса"], rows)
        end

        def outcome(event)
          case event.canonical_status
          when "approved" then "`#{canon.approve}`"
          when "rejected" then "`#{canon.reject}` с кодом ошибки"
          when nil then "`unknown_event` (W203)"
          else "`#{canon.success}(status: '#{event.canonical_status}')`"
          end
        end

        def response_lines
          response = webhook.response
          return ["- Ответ провайдеру не объявлен: платформа отвечает по умолчанию"] unless response

          example = response.example ? " `#{JSON.generate(response.example)}`" : ""
          ["- Ответ провайдеру: HTTP #{response.http}#{example} (формирует платформа после `process_callback`)"]
        end
      end
    end
  end
end
