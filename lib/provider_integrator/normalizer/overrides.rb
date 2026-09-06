# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # The escape hatch for everything a spec does not say: a fixed-key YAML file that pins an
    # operation kind, an amount unit, a conditional requirement, the signature convention, a status
    # or an error action (docs/IR_CONTRACT.md 2.11). The keys are the same for every provider, so
    # using it is configuration, not a provider-specific branch in the code. Every hit is recorded.
    class Overrides
      EMPTY = {}.freeze

      # Reads and validates +path+ (nil yields an empty set); schema errors become E001.
      def self.load(path:, log:)
        return new({}, log) if path.nil?

        return new({}, log) unless (raw = read(path, log))

        errors = Schemas.errors(:overrides, raw)
        return new(raw, log) if errors.empty?

        log.add("E001", reason: "overrides #{path}: #{errors.join("; ")}")
        new({}, log)
      end

      def self.read(path, log)
        raw = Psych.safe_load(Files.read(path), permitted_classes: [], aliases: false, filename: path)
        return raw if raw.is_a?(Hash)

        log.add("E001", reason: "overrides #{path} is not a mapping")
        nil
      rescue Psych::Exception, SystemCallError => e
        log.add("E001", reason: "overrides #{path}: #{e.message}")
        nil
      end
      private_class_method :read

      def initialize(raw, log)
        @raw = raw
        @log = log
        @applied = []
      end

      # Models::OverrideApplied for every entry that actually changed the IR, in application order.
      attr_reader :applied

      # The kind forced for +operation_id+, or nil.
      def kind_for(operation_id) = record("operations", operation_id, section("operations")[operation_id])

      # "minor" / "major" forced for the field +path+ of the component +schema_name+, or nil.
      def amount_unit(schema_name, path)
        target = "#{schema_name}.#{path}"
        record("amount_unit", target, section("amount_unit")[target])
      end

      # { when:, equals: } forced for the field +path+, or nil.
      def required_if(path)
        entry = Array(@raw["required_if"]).find { |item| item["field"] == path }
        return nil unless entry

        record("required_if", path, { when: entry["when"], equals: entry["equals"].to_s })
      end

      # The forced signature convention as a Symbol-keyed Hash, or nil.
      def signature
        entry = @raw["signature"]
        return nil unless entry.is_a?(Hash)

        location = entry["header"] ? "header" : "body"
        forced = { location:, name: entry["header"] || entry["field"], algorithm: entry["algorithm"],
                   encoding: entry["encoding"], message: entry["message"] }.compact
        record("signature", forced[:name], forced)
      end

      # The canonical status forced for the provider status +value+, or nil.
      def status_for(value) = record("status_map", value.to_s, section("status_map")[value.to_s])

      # { provider code => action } as declared (recorded when a code is actually seen).
      def error_actions = section("error_actions")

      # Records that the error action for +code+ was applied.
      def record_error_action(code) = record("error_actions", code, section("error_actions")[code])

      # True when the file declares nothing at all.
      def empty? = @raw.empty?

      private

      def section(key) = @raw[key].is_a?(Hash) ? @raw[key] : EMPTY

      # Remembers an applied override and reports it; returns the value so callers can chain.
      def record(key, target, value)
        return nil if value.nil?

        @applied << Models::OverrideApplied.new(key:, target: target.to_s, value: presentable(value), note: nil)
        @log.add("I601", key:, target:, value: presentable(value))
        value
      end

      def presentable(value) = value.is_a?(Hash) ? JsonCanon.canonicalize(value) : value
    end
  end
end
