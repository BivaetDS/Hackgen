# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Decides which operation plays which BaseService role. A spec can offer two candidates for the
    # same role (card payouts and SBP payouts, say); the best-scoring one becomes the contract method
    # and the rest are still generated, as extra public methods, with W105 saying so. Roles that
    # nobody fills are reported too: a missing create is fatal, a missing status or webhook is not.
    class ContractRoles
      def initialize(log:, canon: Dictionaries.canonical_contract)
        @log = log
        @canon = canon
      end

      # Returns the operations with in_contract and canonical_method filled in, in the same order.
      def call(operations, refs)
        assigned = assign(operations)
        assigned.each_with_index { |operation, index| report(operation, refs[index]) }
        assigned
      end

      private

      attr_reader :log, :canon

      def roles = canon.fetch("contract_roles")
      def extras = canon.fetch("extra_methods")

      def assign(operations)
        chosen = roles.keys.to_h { |kind| [kind, elect(operations, kind)] }
        operations.each_with_index.map { |operation, index| assign_one(operation, chosen[operation.kind] == index) }
      end

      def assign_one(operation, elected)
        return operation.with(in_contract: true, canonical_method: roles.fetch(operation.kind)) if elected

        operation.with(in_contract: false, canonical_method: extras[operation.kind])
      end

      # The index of the operation that wins +kind+: the highest score, ties broken by spec order.
      def elect(operations, kind)
        candidates = operations.each_index.select { |index| operations[index].kind == kind }
        return nil if candidates.empty?

        candidates.max_by { |index| [operations[index].classification.scores.fetch(kind, 0), -index] }
      end

      def report(operation, ref)
        details = { operation_id: operation.operation_id, method: operation.method, path: operation.path }
        log.add("I101", **details, kind: operation.kind, confidence: operation.confidence, location: ref.pointer)
        report_confidence(operation, ref, details)
        return if operation.in_contract

        log.add("W102", **details, kind: operation.kind, location: ref.pointer)
      end

      def report_confidence(operation, ref, details)
        return if operation.confidence >= Confidence.thresholds.fetch("low_confidence_below")

        log.add("W101", **details, kind: operation.kind, confidence: operation.confidence, location: ref.pointer)
      end

      public

      # Reports the roles nobody filled and the roles more than one operation wanted. A webhook
      # declared through "callbacks" fills the role without being an operation, hence +webhook+.
      def report_gaps(operations, webhook: nil)
        roles.each_key do |kind|
          candidates = operations.select { |operation| operation.kind == kind }
          filled = !candidates.empty? || (kind == "webhook" && !webhook.nil?)
          report_missing(kind) unless filled
          report_crowded(kind, candidates) if candidates.size > 1
        end
      end

      MISSING_EVENTS = { "create" => "E101", "status" => "W106", "webhook" => "W304" }.freeze

      private

      def report_missing(kind)
        code = MISSING_EVENTS[kind]
        log.add(code) if code
      end

      def report_crowded(kind, candidates)
        winner = candidates.find(&:in_contract) || candidates.first
        log.add("W105", kind:, candidates: candidates.map(&:operation_id), operation_id: winner.operation_id)
      end
    end
  end
end
