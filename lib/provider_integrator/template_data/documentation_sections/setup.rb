# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Авторизация" and "Настройка": how the service authenticates and what has to be configured
      # (ENV constants, credentials keys) before it can talk to the provider.
      class Setup
        def initialize(doc)
          @doc = doc
          @auth = doc.spec.authentication
          @canon = doc.canon
          @context = doc.context
        end

        def sections
          [doc.section("Авторизация", authorization_lines), doc.section("Настройка", setup_lines)]
        end

        private

        attr_reader :doc, :auth, :canon, :context

        def authorization_lines
          [type_line, transport_line, storage_line,
           "- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется " \
           "подписью (см. «Webhook signature»)",
           evidence_line, alternatives_line].compact
        end

        def type_line
          scheme = auth.scheme_name && " (#{doc.code(auth.scheme_name)})"
          "- Тип: #{auth.type}#{scheme}"
        end

        def storage_line
          keys = credential_keys.map { |key| doc.code(key) }.join(", ")
          "- Хранение: `providers.credentials` (encrypted), ключи: #{keys}"
        end

        def evidence_line
          auth.evidence.empty? ? nil : "- Evidence: #{auth.evidence.join("; ")}"
        end

        def alternatives_line
          return nil if auth.alternatives.empty?

          "- Альтернативные схемы в спеке: #{auth.alternatives.map(&:scheme_name).join(", ")}"
        end

        def transport_line
          case auth.type
          when "api_key" then api_key_line
          when "http_bearer" then "- Header: `#{auth.name}: Bearer <credentials.token>`"
          when "http_basic" then "- Header: `#{auth.name}: Basic base64(<credentials.login>:<credentials.password>)`"
          when "oauth2_client_credentials", "oauth2" then oauth_line
          when "none" then "- Спека не объявляет securitySchemes: запросы без авторизации"
          else "- Схема `#{auth.scheme_name}` (#{auth.type}) не поддерживается (W501): настроить вручную"
          end
        end

        def api_key_line
          key = "<credentials.#{auth.credentials_key}>"
          case auth.location
          when "query" then "- Query-параметр: `#{auth.name}=#{key}` (добавляется `with_api_key`)"
          when "cookie" then "- Cookie: `#{auth.name}=#{key}`"
          else "- Header: `#{auth.name}: #{key}`"
          end
        end

        def oauth_line
          scopes = auth.scopes.empty? ? "" : ", scopes: #{auth.scopes.join(" ")}"
          "- Header: `#{auth.name}: Bearer <access_token>`; токен по client credentials с `TOKEN_URL` " \
            "(#{auth.token_url || "не указан в спеке"}#{scopes})"
        end

        def credential_keys
          keys = canon.credential_keys(auth.type)
          keys += [canon.callback_secret_key] if doc.spec.webhook&.signature
          keys += [canon.merchant_account_key] if merchant_account?
          keys.uniq
        end

        def merchant_account?
          doc.spec.operations.any? { |op| op.request_fields.any? { |f| f.canonical == "merchant_account" } }
        end

        def setup_lines
          doc.table(["Параметр", "Откуда", "Значение по умолчанию / назначение"], env_rows + credential_rows)
        end

        def env_rows
          [base_url_row, *other_server_rows, token_url_row, *env_constant_rows].compact
        end

        def base_url_row
          server = context.default_server
          value = server ? "#{doc.code(server.url)} (#{server.environment})" : "нет servers в спеке (W104): обязательно"
          [doc.code(context.env_name("base_url")), "ENV", value]
        end

        def other_server_rows
          default = context.default_server
          doc.spec.servers.reject { |server| server.equal?(default) }
             .map { |server| ["servers (#{server.environment})", "спека", doc.code(server.url)] }
        end

        def token_url_row
          return nil unless auth.token_url

          [doc.code(context.env_name("token_url")), "ENV", doc.code(auth.token_url)]
        end

        def env_constant_rows
          doc.service.env_constants.map do |canonical|
            [doc.code(context.env_name(canonical)), "ENV", "отправляется в теле запроса как #{canonical}"]
          end
        end

        def credential_rows
          credential_keys.map do |key|
            [doc.code(canon.credential(key)), "providers.credentials", credential_purpose(key)]
          end
        end

        def credential_purpose(key)
          return "секрет подписи webhook" if key == canon.callback_secret_key
          return "идентификатор мерчанта в теле запроса" if key == canon.merchant_account_key

          "авторизация запросов (#{auth.scheme_name})"
        end
      end
    end
  end
end
