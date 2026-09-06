# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The one line that talks to the provider: "response = client.post(url, json: payload, headers: ...)".
    # The HTTP verb comes from the operation, the body keyword from the media type through the canon
    # (json / form), so the same builder serves JSON and form-urlencoded providers.
    module Requests
      module_function

      def call_line(operation, url:, headers:, canon:, payload: nil)
        arguments = [url]
        arguments << "#{body_keyword(operation, canon)}: #{payload}" if payload
        arguments << "headers: #{headers}"
        "response = client.#{operation.method.downcase}(#{arguments.join(", ")})"
      end

      # "json" or "form" for the operation's request media type (json when unknown).
      def body_keyword(operation, canon)
        canon.client_argument(operation.request_body&.content_type) || canon.client_argument("application/json")
      end

      # "[200, 202].include?(response.status)" or "response.status == 200".
      def success_check(codes)
        return "response.status == #{codes.first}" if codes.size == 1

        "#{Code.literal(codes)}.include?(response.status)"
      end
    end
  end
end
