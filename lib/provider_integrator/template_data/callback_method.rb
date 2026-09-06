# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # process_callback and its helpers: verify the signature (SignatureVerifier), read the parsed
    # body out of the platform payload, then dispatch on the event value (or the status field) to
    # approve/reject the operation.
    class CallbackMethod
      def initialize(service)
        @service = service
        @webhook = service.spec.webhook
        @canon = service.canon
        @verifier = SignatureVerifier.new(service, @webhook.signature) if @webhook&.signature
      end

      def public_methods_data
        return [stub] unless webhook

        rescues = verifier ? [[canon.exception("invalid_credentials"), invalid_signature]] : []
        [MethodData.build(name: "process_callback", params: "payload", comment: comment, lines: body_lines, rescues:)]
      end

      def private_methods_data
        return [] unless webhook

        methods = [callback_body_method]
        methods += [verifier.method_data, secure_compare_method] if verifier
        methods
      end

      private

      attr_reader :service, :webhook, :canon, :verifier

      def invalid_signature = canon.failure_for_service_code("invalid_signature")
      def body_key = canon.callback_key("body")

      def comment
        [
          "#{webhook.method} #{webhook.path} (#{webhook.operation_id}); source: #{webhook.source}.",
          "payload is the parsed JSON body, or #{envelope} (INTEGRATION.md, Webhook).",
          Generator::Confidence.todo_if_needed(webhook.confidence, "webhook identified with confidence " \
                                                                   "#{webhook.confidence}; confirm the endpoint")
        ].compact
      end

      def envelope
        keys = %w[body headers raw_body].map { |name| Code.str(canon.callback_key(name)) }
        "{ #{keys[0]} => body, #{keys[1]} => headers, #{keys[2]} => raw body }"
      end

      def body_lines
        lines = []
        lines << "verify_signature!(payload) # #{verifier.algorithm.upcase} from #{webhook.signature.name}" if verifier
        lines << "body = callback_body(payload)"
        lines.concat(dispatch_lines)
      end

      def dispatch_lines
        return event_dispatch if webhook.events.any?(&:canonical_status)
        return status_dispatch if webhook.status_field

        [Generator::Confidence.todo(0.0, "the payload declares neither an event nor a status field; " \
                                         "the notification is acknowledged without changing the operation"),
         "#{canon.success}(response: body)"]
      end

      # case body[event] grouped by canonical status in order of first appearance.
      def event_dispatch
        groups = webhook.events.select(&:canonical_status).group_by(&:canonical_status)
        branches = groups.map { |status, events| branch_line(status, events) }
        [*unmapped_events_comment, "case #{Code.access("body", webhook.event_field)}", *branches,
         "else #{canon.failure_for_service_code("unknown_event")}", "end"]
      end

      def branch_line(status, events)
        "when #{events.map { |event| Code.str(event.value) }.join(", ")} then #{outcome(status)}"
      end

      def unmapped_events_comment
        unmapped = webhook.events.reject(&:canonical_status).map(&:value)
        return [] if unmapped.empty?

        ["# Events without a canonical status (W203), answered as unknown_event: #{unmapped.join(", ")}"]
      end

      def status_dispatch
        ["case map_status(#{Code.access("body", webhook.status_field)})",
         *canon.statuses.map { |status| "when #{Code.str(status)} then #{outcome(status)}" },
         "else #{canon.failure_for_service_code("unknown_event")}",
         "end"]
      end

      def outcome(status)
        case status
        when "approved" then "#{canon.approve}(#{id_expression})"
        when "rejected" then "#{canon.reject}(#{id_expression}, #{error_code_expression})"
        else "#{canon.success}(status: #{Code.str(status)}, response: body)"
        end
      end

      def id_expression
        webhook.id_field ? Code.access("body", webhook.id_field) : "nil"
      end

      def error_code_expression
        webhook.error_code_path ? Code.access("body", webhook.error_code_path) : "nil"
      end

      def callback_body_method
        MethodData.build(name: "callback_body", params: "payload",
                         comment: ["The parsed notification: payload[#{Code.str(body_key)}] under the platform " \
                                   "envelope, else the payload itself."],
                         lines: ["payload[#{Code.str(body_key)}] || payload"])
      end

      def secure_compare_method
        MethodData.build(name: "secure_compare", params: "left, right",
                         lines: ["left.bytesize == right.bytesize && OpenSSL.fixed_length_secure_compare(left, right)"])
      end

      def stub
        MethodData.build(name: "process_callback", params: "payload",
                         comment: [Generator::Confidence.todo(0.0, "the spec declares no webhook (W304); " \
                                                                   "poll fetch_status instead")],
                         lines: ["raise NotImplementedError, #{Code.str("process_callback: no webhook in the spec")}"])
      end
    end
  end
end
