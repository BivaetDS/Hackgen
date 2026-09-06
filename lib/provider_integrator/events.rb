# frozen_string_literal: true

module ProviderIntegrator
  # Registry of every diagnostic the pipeline can emit. A code fixes the level and a message
  # template with named placeholders; docs/PLAN.md section 3.3 documents the same table and a spec
  # keeps both in sync. Build events only through Events.build so codes never drift.
  module Events
    # One registry entry. `placeholders` are the %{names} the template needs in `details`.
    Definition = Data.define(:code, :level, :template, :placeholders, :summary) do
      # Renders the message; Arrays join with ", ", Hashes render as "key -> value" pairs.
      def render(details)
        format(template, Events.presentable(details))
      rescue KeyError => e
        raise ArgumentError, "#{code}: missing placeholder #{e.key.inspect} (needs #{placeholders.join(", ")})"
      end
    end

    LEVELS = %w[error warning info].freeze
    PLACEHOLDER = /%\{(\w+)\}/

    # [code, level, template, summary]; the summary explains "when" in one line.
    ROWS = [
      ["E001", "error", "Spec cannot be parsed: %{reason}",
       "Input file is unreadable or not valid YAML/JSON"],
      ["E002", "error", "Unsupported OpenAPI version %{version}; supported: %{supported}",
       "openapi/swagger version missing or outside 2.0, 3.0.x, 3.1.x"],
      ["E003", "error", "Document has no paths; nothing to integrate",
       "paths is missing or empty"],
      ["E004", "error", "Document has no info.title",
       "info or info.title is missing"],
      ["E005", "error", "Unresolvable $ref %{ref}",
       "A local $ref points to a missing component"],
      ["E006", "error", "$ref cycle deeper than %{limit} levels at %{ref}",
       "$ref recursion exceeds the depth limit"],
      ["E007", "error", "Input exceeds limits: %{reason}",
       "File larger than the size limit or nested deeper than the depth limit"],
      ["E008", "error", "External $ref %{ref} is not supported; only local #/ references are resolved",
       "A $ref points to another file or URL"],
      ["E009", "error", "OpenAPI structure is invalid: %{reason}",
       "openapi3_parser reports structural errors"],
      ["E101", "error", "No create operation found; cannot generate create_request",
       "No operation classified as create"],
      ["E201", "error", "Generated %{file} is invalid: %{reason}",
       "Generated Ruby fails the syntax check or contains an unfilled ERB placeholder"],
      ["W101", "warning",
       "Operation %{operation_id} (%{method} %{path}) classified as %{kind} with low confidence %{confidence}",
       "Classification confidence below the warning threshold"],
      ["W102", "info",
       "Operation %{operation_id} (%{method} %{path}) is outside the BaseService contract (kind %{kind}); " \
       "generated as an extra method",
       "cancel, balance, refund, list or unknown operations"],
      ["W103", "info", "Swagger 2.0 document converted to OpenAPI 3.0 before analysis",
       "Input was Swagger 2.0"],
      ["W104", "warning", "No servers declared; BASE_URL must be configured manually",
       "servers is missing or empty"],
      ["W105", "warning",
       "Several %{kind} candidates (%{candidates}); %{operation_id} chosen, others generated as extra methods",
       "More than one operation competes for a contract role"],
      ["W106", "warning", "No status operation found; fetch_status is generated as a stub",
       "No operation classified as status"],
      ["W201", "warning", "Status %{status} has no canonical mapping; defaulting to %{default}",
       "Provider status absent from statuses.yml"],
      ["W202", "warning",
       "Provider error code %{provider_code} (HTTP %{http}) has no canonical analog; defaulting to %{canonical}",
       "Provider error code absent from errors.yml"],
      ["W203", "warning", "Webhook event %{value} has no canonical status; the service treats it as unknown_event",
       "Webhook event value absent from statuses.yml"],
      ["W204", "warning", "Numeric status %{status} mapped by convention to %{canonical}; confirm with the provider",
       "Numeric status without a textual description mapped through statuses.yml numeric"],
      ["W301", "warning",
       "HMAC canonicalization for %{name} is not specified (encoding %{encoding}, message %{message}); " \
       "the generator assumes %{default_encoding} digest over %{default_message}",
       "Signature algorithm named but encoding/message not specified"],
      ["W302", "warning",
       "Webhook endpoint %{method} %{path} identified by %{heuristic} heuristic, not via OpenAPI callbacks",
       "Webhook found by path/tag heuristics"],
      ["W303", "warning",
       "Webhook event %{event} maps to %{event_status} but status %{status} maps to %{status_canonical}; status wins",
       "Webhook event and status field disagree"],
      ["W304", "warning", "No webhook endpoint found; process_callback is generated as a stub",
       "Spec has neither callbacks nor a webhook-like operation"],
      ["W401", "warning",
       "Amount units for %{field} in %{operation_id} could not be determined (score %{score}); multiplier 1 assumed",
       "Money-unit signals below threshold or conflicting"],
      ["W402", "warning",
       "Conditional requirement inferred from description: %{field} is required when %{when} equals %{equals} " \
       "(%{operation_id})",
       "Conditional requirement found by regex over a description"],
      ["W403", "warning", "Required request field %{field} in %{operation_id} is not mapped to any canonical field",
       "Required request field without a canonical name"],
      ["W405", "warning",
       "Direction of %{operation_id} not found in the spec; %{direction} assumed for the ProviderGateway config",
       "No withdraw/deposit keyword anywhere in the create operation or the title"],
      ["W501", "warning",
       "Security scheme %{scheme_name} of type %{type} is not supported; credentials must be configured manually",
       "Security scheme type outside the supported set"],
      ["W502", "warning",
       "Operation %{operation_id} (%{method} %{path}) declares no security while other operations do",
       "Non-webhook operation with empty security"],
      ["W601", "warning", "%{file} contains manual edits since the last generation; see regeneration diff",
       "Re-generation over a hand-edited output file"],
      ["I101", "info",
       "Operation %{operation_id} (%{method} %{path}) classified as %{kind} with confidence %{confidence}",
       "Every classified operation (verbose)"],
      ["I102", "info", "operationId missing for %{method} %{path}; synthesized %{operation_id}",
       "operationId synthesized from method and path"],
      ["I201", "info", "Status mapping recorded (%{count} statuses): %{mapping}",
       "Status map is a critical inference; always reported"],
      ["I301", "info",
       "Signature convention recorded: %{name} (%{placement}), algorithm %{algorithm}, encoding %{encoding}, " \
       "message %{message}, secret %{secret}",
       "Signature convention is a critical inference; always reported"],
      ["I401", "info",
       "Amount field %{field} in %{operation_id} uses %{unit} units (multiplier %{multiplier}, score %{score}); " \
       "signals: %{signals}",
       "Money units are a critical inference; always reported"],
      ["I402", "info",
       "Conditional requirement recorded from %{source}: %{field} is required when %{when} equals %{equals} " \
       "(%{operation_id})",
       "Conditional requirement found structurally (discriminator, if/then, override)"],
      ["I403", "info",
       "Gateway config recorded: external_method %{external_method}, gateway %{gateway} (confidence %{confidence}); " \
       "evidence: %{evidence}",
       "ProviderGateway config is a visible inference; always reported"],
      ["I601", "info", "Override %{key} applied to %{target}: %{value}",
       "An overrides.yml entry changed the IR"]
    ].freeze

    REGISTRY = ROWS.to_h do |code, level, template, summary|
      placeholders = template.scan(PLACEHOLDER).flatten.uniq.map(&:to_sym)
      [code, Definition.new(code:, level:, template:, placeholders:, summary:)]
    end.freeze

    class << self
      # All codes, sorted.
      def codes = REGISTRY.keys.sort

      # Registry entry for +code+; ArgumentError for unknown codes.
      def definition(code)
        REGISTRY.fetch(code.to_s) { raise ArgumentError, "unknown event code #{code.inspect}" }
      end

      # "error" | "warning" | "info" for +code+.
      def level(code) = definition(code).level

      # True when +code+ is registered.
      def known?(code) = REGISTRY.key?(code.to_s)

      # Builds a Models::Event. +details+ must include every placeholder of the template; extra keys
      # are kept in Event#details (canonicalized: String keys, sorted) for the report.
      def build(code, location: nil, **details)
        entry = definition(code)
        Models::Event.new(code: entry.code, level: entry.level, message: entry.render(details), location:,
                          details: details.empty? ? nil : JsonCanon.canonicalize(details))
      end

      # Symbol-keyed Hash with display Strings for message rendering.
      def presentable(details)
        details.to_h { |key, value| [key.to_sym, present(value)] }
      end

      private

      def present(value)
        case value
        when Array then value.map { |item| present(item) }.join(", ")
        when Hash then value.map { |key, item| "#{key} -> #{present(item)}" }.join(", ")
        else value.to_s
        end
      end
    end
  end
end
