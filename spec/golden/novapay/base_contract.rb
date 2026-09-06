# frozen_string_literal: true

# ДОПУЩЕНИЕ: реальный Provider::BaseService предоставляет Space Payments и в этот
# репозиторий не входит. Файл - заглушка контракта, реконструированного по эталону ТЗ и ответам экспертов
# (docs/ASSUMPTIONS.md), чтобы сгенерированный сервис можно было загрузить и прогнать тесты автономно.
# В продакшене файл не используется: сервис подключается к настоящему BaseService.
#
# Credentials this provider reads: api_key, callback_secret.

class Provider
  class RateLimitError < StandardError; end
  class UnauthorizedError < StandardError; end

  # Outcome of a service call: success(**details) or failure(error, code, **details).
  # details carry what the platform stores: status, provider_operation_id, response, error_code, retry_after.
  Result = Struct.new(:success, :error, :code, :details, keyword_init: true) do
    def success? = success
    def failed? = !success
    def status = details[:status]
    def provider_operation_id = details[:provider_operation_id]
    def response = details[:response]
  end

  # The platform operation as the generated service reads it (docs/ASSUMPTIONS.md, допущение 1).
  # amount is in major units; the requisites are one hash keyed by the payout method.
  Operation = Struct.new(:id, :amount, :currency, :provider_operation_id, :payout_requisite, keyword_init: true)

  # What the HTTP client returns.
  Response = Struct.new(:status, :body, :headers, keyword_init: true)

  class BaseService
    STATUSES = %w[in_progress approved rejected].freeze

    attr_reader :client, :credentials

    # client returns a Response and responds to:
    #   client.get(url, headers:)
    #   client.post(url, json:, headers:)
    #   client.post(url, form:, headers:)
    # credentials is the provider's secret hash from providers.credentials.
    def initialize(client:, credentials:)
      @client = client
      @credentials = credentials
    end

    def create_request(_operation, _request_method = nil)
      raise NotImplementedError, 'implemented by the generated service'
    end

    def fetch_status(_operation)
      raise NotImplementedError, 'implemented by the generated service'
    end

    def process_callback(_payload)
      raise NotImplementedError, 'implemented by the generated service'
    end

    def check_conditions(_operation, _request_method)
      success
    end

    private

    def success(**details)
      Result.new(success: true, error: nil, code: nil, details: details)
    end

    def failure(error, code, **details)
      Result.new(success: false, error: error, code: code, details: details)
    end

    def approve_operation(provider_operation_id)
      success(status: 'approved', provider_operation_id: provider_operation_id)
    end

    def reject_operation(provider_operation_id, error_code = nil)
      success(status: 'rejected', provider_operation_id: provider_operation_id, error_code: error_code)
    end
  end
end
