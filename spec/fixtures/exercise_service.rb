# frozen_string_literal: true

# Runs the generated NovaPay service against base_contract.rb with a fake client (no HTTP at all)
# and prints what happened as JSON. Executed in a child process by spec/generator/generator_spec.rb
# so the generated constants never leak into the test process.
require "json"
require "openssl"
require_relative "base_contract"
require_relative "novapay_service"

# Records the request and answers with the canned response.
class FakeClient
  attr_reader :requests

  def initialize(response)
    @response = response
    @requests = []
  end

  def post(url, json: nil, form: nil, headers: {})
    @requests << { "url" => url, "json" => json, "form" => form, "headers" => headers }
    @response
  end

  def get(url, headers: {})
    @requests << { "url" => url, "headers" => headers }
    @response
  end
end

def response(status, body, headers = {})
  Provider::Response.new(status: status, body: body, headers: headers)
end

def service_for(response)
  Provider::NovapayService.new(client: FakeClient.new(response), credentials: { api_key: "key", callback_secret: "s3cret" })
end

def outcome(result)
  { "success" => result.success?, "error" => result.error&.to_s, "code" => result.code,
    "status" => result.details[:status], "provider_operation_id" => result.details[:provider_operation_id],
    "error_code" => result.details[:error_code], "retry_after" => result.details[:retry_after] }.compact
end

operation = Provider::Operation.new(id: "op_1", amount: 1500, currency: "RUB", provider_operation_id: "np_7f3a9b2c",
                                    payout_requisite: { "sbp" => { "phone" => "79001234567", "bank_code" => "044525225" },
                                                        "card" => { "phone" => "79001234567" } })
created = { "id" => "np_7f3a9b2c", "status" => "pending" }
report = {}

service = service_for(response(201, created))
report["create"] = outcome(service.create_request(operation, "sbp"))
report["request"] = service.client.requests.first
report["duplicate"] = outcome(service_for(response(409, created)).create_request(operation))
error = { "error" => { "code" => "rate_limit_exceeded", "message" => "slow down" } }
report["rate_limited"] = outcome(service_for(response(429, error, { "Retry-After" => "60" })).create_request(operation))

checker = service_for(response(201, created))
report["too_low"] = outcome(checker.check_conditions(Provider::Operation.new(id: "op_2", amount: 5, currency: "RUB",
                                                                             payout_requisite: {}), "sbp"))
report["missing_requisite"] = outcome(checker.check_conditions(operation, "card"))
report["unsupported"] = outcome(checker.check_conditions(operation, "crypto"))
report["ok"] = outcome(checker.check_conditions(operation, "sbp"))

report["status"] = outcome(service_for(response(200, { "id" => "np_7f3a9b2c", "status" => "completed" }))
                             .fetch_status(operation))

def signed(body)
  raw = JSON.generate(body)
  { "body" => body, "raw_body" => raw,
    "headers" => { "X-NovaPay-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "s3cret", raw) } }
end

callback_service = service_for(response(200, {}))
report["callback"] = outcome(callback_service.process_callback(signed({ "event" => "payout.completed",
                                                                        "payout_id" => "np_7f3a9b2c" })))
failed = { "event" => "payout.failed", "payout_id" => "np_7f3a9b2c", "error" => { "code" => "recipient_not_found" } }
report["callback_failed"] = outcome(callback_service.process_callback(signed(failed)))
tampered = signed({ "event" => "payout.completed", "payout_id" => "np_7f3a9b2c" })
tampered["headers"]["X-NovaPay-Signature"] = "0" * 64
report["bad_signature"] = outcome(callback_service.process_callback(tampered))
report["unknown_event"] = outcome(callback_service.process_callback(signed({ "event" => "payout.unknown" })))

puts JSON.generate(report)
