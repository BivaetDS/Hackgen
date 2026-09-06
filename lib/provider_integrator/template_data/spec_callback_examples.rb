# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # `describe '#process_callback'`: one example per callback entry of fixtures.json, signed the
    # way verify_signature! checks (header envelope or in-body field), the outcome computed by
    # CallbackOutcome, a forged signature refused, and NotImplementedError expectations for a
    # missing webhook (W304) or an asymmetric signature.
    class SpecCallbackExamples < SpecExamples
      def method_name = "process_callback"

      def examples
        @examples ||= if webhook.nil?
                        [stub_example("the spec declares no webhook (W304)")]
                      elsif verifier&.asymmetric?
                        [stub_example("#{verifier.algorithm} needs the provider public key")]
                      else
                        entries.map { |key, payload| entry_example(key, payload) } + forged_examples
                      end
      end

      def summary
        return "заглушка (`NotImplementedError`, W304)" unless webhook
        return "заглушка (`NotImplementedError`, асимметричная подпись)" if verifier&.asymmetric?

        parts = entries.map { |key, payload| "#{key} -> #{CallbackOutcome.status(spec, payload) || "unknown_event"}" }
        parts << "подделанная подпись" if verifier
        parts.join(", ")
      end

      # The SignatureVerifier of the webhook (nil without a signature), shared with the helpers.
      def verifier
        return @verifier if defined?(@verifier)

        @verifier = webhook&.signature && SignatureVerifier.new(service, webhook.signature)
      end

      private

      def webhook = spec.webhook

      # [[fixture key, payload without generator markers], ...] in fixtures.json order.
      def entries
        @entries ||= data.fixtures.filter_map do |key, value|
          next unless value.is_a?(Hash) && value["payload"].is_a?(Hash)

          [key, data.fixture(key, "payload")]
        end
      end

      def stub_example(reason)
        example("raises NotImplementedError: #{reason}",
                ["expect { service.process_callback({}) }.to raise_error(NotImplementedError)"])
      end

      def payload_expression(key)
        call = fixture_call(key, "payload")
        verifier ? "signed_payload(#{call})" : call
      end

      def entry_example(key, payload)
        status = CallbackOutcome.status(spec, payload)
        lines = ["result = service.process_callback(#{payload_expression(key)})", "", *outcome_lines(status, payload)]
        example("#{outcome_verb(status)} for the #{key} fixture#{event_note(payload)}", lines)
      end

      def event_note(payload)
        field = webhook.event_field or return ""
        value = CallbackOutcome.dig(payload, field) or return ""
        " (#{field} #{value})"
      end

      def outcome_verb(status)
        case status
        when "approved" then "approves the operation"
        when "rejected" then "rejects the operation"
        when nil then CallbackOutcome.acknowledged?(spec) ? "acknowledges the notification" : "answers unknown_event"
        else "reports #{status}"
        end
      end

      def outcome_lines(status, payload)
        return [failure_expectation(canon.service_failure_parts("unknown_event"))] if status.nil? && !acknowledged?
        return ["expect(result).to be_success"] if status.nil?

        ["expect(result).to be_success", "expect(result.status).to eq(#{Code.str(status)})",
         *detail_lines(status, payload)]
      end

      # The provider id (final statuses) and the error code (rejected) the payload carries.
      def detail_lines(status, payload)
        id = final?(status) ? id_of(payload) : nil
        code = status == canon.statuses.fetch(2) ? error_code_of(payload) : nil
        lines = []
        lines << "expect(result.provider_operation_id).to eq(#{Code.literal(id)})" unless id.nil?
        lines << "expect(result.details[:error_code]).to eq(#{Code.literal(code)})" unless code.nil?
        lines
      end

      # Only approve_operation/reject_operation carry the provider id; an intermediate status is
      # answered with success(status:, response:) alone.
      def final?(status) = [canon.statuses.fetch(1), canon.statuses.fetch(2)].include?(status)

      def acknowledged? = CallbackOutcome.acknowledged?(spec)
      def id_of(payload) = webhook.id_field && CallbackOutcome.dig(payload, webhook.id_field)
      def error_code_of(payload) = webhook.error_code_path && CallbackOutcome.dig(payload, webhook.error_code_path)

      def forged_examples
        return [] unless verifier && entries.any?

        key = entries.first.first
        lines = ["payload = #{payload_expression(key)}", forged_line, "", "result = service.process_callback(payload)",
                 "", failure_expectation(canon.service_failure_parts("invalid_signature"))]
        [example("refuses a payload whose signature does not verify", lines)]
      end

      # Overwrites the signature where verify_signature! reads it.
      def forged_line
        if verifier.location == "body"
          "payload[#{Code.str(verifier.name)}] = #{Code.str("invalid")}"
        else
          "payload[#{Code.str(canon.callback_key("headers"))}][#{Code.str(verifier.name)}] = #{Code.str("invalid")}"
        end
      end
    end
  end
end
