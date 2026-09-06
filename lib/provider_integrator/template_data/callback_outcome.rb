# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # What the generated process_callback answers for a parsed notification payload, computed at
    # generation time from the IR: the canonical status it reports, or nil when it answers
    # unknown_event. fixtures.json (expected_operation_status) and the generated spec both read
    # it here, so they agree with the service by construction. Mirrors CallbackMethod: when any
    # event value maps to a status the dispatch is by event alone; else by the status field
    # through STATUS_MAP (unknown values fall back to the default status, as map_status does).
    module CallbackOutcome
      module_function

      # Canonical status for +payload+ under +spec+ (a ProviderSpec with a webhook), or nil.
      def status(spec, payload)
        webhook = spec.webhook
        return event_status(webhook, payload) if webhook.events.any?(&:canonical_status)
        return field_status(spec, payload) if webhook.status_field

        nil
      end

      # True when the service acknowledges every payload without reading a status (no event
      # mapping and no status field): it answers success without an operation status.
      def acknowledged?(spec)
        webhook = spec.webhook
        webhook.events.none?(&:canonical_status) && webhook.status_field.nil?
      end

      def event_status(webhook, payload)
        return nil unless webhook.event_field

        event = dig(payload, webhook.event_field)
        webhook.events.find { |item| item.value == event }&.canonical_status
      end

      def field_status(spec, payload)
        value = dig(payload, spec.webhook.status_field).to_s
        spec.statuses.find { |mapping| mapping.provider == value }&.canonical || Canon.new.default_status
      end

      def dig(payload, path)
        path.split(".").reduce(payload) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
      end
    end
  end
end
