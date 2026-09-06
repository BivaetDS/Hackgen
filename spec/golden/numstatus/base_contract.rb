# frozen_string_literal: true

# ДОПУЩЕНИЕ: реальный Provider::BaseService предоставляет Space Payments и в этот
# репозиторий не входит. Файл - заглушка контракта, реконструированного по эталону ТЗ и ответам экспертов
# (docs/ASSUMPTIONS.md), чтобы сгенерированный сервис можно было загрузить и прогнать тесты автономно.
# В продакшене файл не используется: сервис подключается к настоящему BaseService.
#
# Credentials this provider reads: client_id, client_secret, callback_secret.

require 'json'
require 'net/http'
require 'uri'

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

  # ДОПУЩЕНИЕ: платформа инжектирует свой HTTP-клиент (допущение 23); этот нужен только для автономного
  # прогона сгенерированного RSpec (через WebMock) и ручных проверок. JSON-ответы разбираются, остальные
  # тела возвращаются строкой; заголовки ответа - в нижнем регистре, как их отдаёт Net::HTTP.
  class HttpClient
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    def get(url, headers: {})
      perform(Net::HTTP::Get.new(URI(url), headers))
    end

    def post(url, json: nil, form: nil, headers: {})
      request = Net::HTTP::Post.new(URI(url), headers)
      if json
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(json)
      elsif form
        request.set_form_data(form)
      end
      perform(request)
    end

    private

    def perform(request)
      uri = request.uri
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      response = http.request(request)
      Response.new(status: response.code.to_i, body: parse_body(response.body), headers: response.each_header.to_h)
    end

    # JSON bodies are parsed; anything else comes back as the raw String (nil when empty).
    def parse_body(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end

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
