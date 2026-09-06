# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The "requires confirmation" list shared by INTEGRATION.md and generation_report.json: every
    # warning of the analysis plus the critical inferences that are reported even at full
    # confidence (docs/PLAN.md 5: amount units, conditional requirements, signature, statuses,
    # gateway config). Each item points at the place in the generated service to look at.
    class Confirmations
      Item = Data.define(:code, :level, :message, :evidence, :where, :location)

      CRITICAL_INFOS = %w[I201 I301 I401 I402 I403 I601].freeze
      WHERE = {
        "W101" => "operation methods (name and role)", "W102" => "extra methods", "W104" => "BASE_URL",
        "W105" => "extra methods", "W106" => "fetch_status (stub)", "W201" => "STATUS_MAP", "W202" => "ERROR_MAP",
        "W203" => "process_callback (unknown_event)", "W204" => "STATUS_MAP", "W301" => "verify_signature!",
        "W302" => "process_callback", "W303" => "process_callback", "W304" => "process_callback (stub)",
        "W401" => "build_*_payload, MIN_AMOUNT", "W402" => "check_conditions, REQUIRED_REQUISITES",
        "W403" => "build_*_payload (TODO)", "W405" => "ProviderGateway config", "W501" => "auth_headers",
        "W502" => "operation methods", "W601" => "output directory", "I201" => "STATUS_MAP",
        "I301" => "verify_signature!", "I401" => "build_*_payload, MIN_AMOUNT",
        "I402" => "check_conditions, REQUIRED_REQUISITES", "I403" => "ProviderGateway config", "I601" => "overrides.yml"
      }.freeze
      EVIDENCE_KEYS = %w[signals evidence].freeze

      def initialize(spec)
        @spec = spec
      end

      # Items in IR event order (warnings first, then the critical infos).
      def items
        @items ||= @spec.events.select { |event| event.warning? || CRITICAL_INFOS.include?(event.code) }
                        .map { |event| item(event) }
      end

      def to_a = items.map(&:to_h)

      private

      def item(event)
        details = event.details || {}
        evidence = EVIDENCE_KEYS.filter_map { |key| details[key] }.flatten.map(&:to_s)
        Item.new(code: event.code, level: event.level, message: event.message, evidence:,
                 where: WHERE.fetch(event.code, "-"), location: event.location)
      end
    end
  end
end
