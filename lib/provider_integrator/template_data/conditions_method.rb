# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # check_conditions: super first (as in the reference service), then the request method, the
    # amount limits derived from the spec (in operation.amount units) and the requisites the
    # chosen payout method requires. Also computes REQUIRED_REQUISITES for the constants.
    class ConditionsMethod
      REQUISITE_PREFIX = "requisite."

      class << self
        # { payout method => [canonical child names] } when the create operation branches, else a
        # flat Array of child names; nil when the operation carries no requisite children.
        def required_requisites(operation)
          fields = requisite_fields(operation)
          return nil if fields.empty?

          methods = operation.request_methods
          return fields.select(&:required).map { |field| child(field) }.uniq unless methods

          methods.values.to_h { |branch| [branch, branch_requisites(fields, branch, methods)] }
        end

        def branch_requisites(fields, branch, methods)
          fields.select { |field| required_in?(field, branch, methods) }.map { |field| child(field) }.uniq
        end

        def requisite_fields(operation)
          return [] unless operation

          operation.request_fields.select do |field|
            field.canonical.to_s.start_with?(REQUISITE_PREFIX) && field.canonical != "requisite.type"
          end
        end

        def child(field) = field.canonical.delete_prefix(REQUISITE_PREFIX)

        def required_in?(field, branch, methods)
          condition = field.conditional_required
          return field.branch.value == branch && (field.required || condition&.equals == branch) if field.branch
          return condition.equals == branch if condition && condition.when == methods.discriminator_path

          field.required
        end
      end

      def initialize(service)
        @service = service
        @operation = service.context.create_operation
        @canon = service.canon
      end

      def public_methods_data
        [MethodData.build(name: "check_conditions", params: "operation, request_method", lines: body_lines,
                          comment: ["Pre-checks before create_request; super runs the platform checks first."])]
      end

      def private_methods_data
        requisites ? [missing_requisites_method] : []
      end

      private

      attr_reader :service, :operation, :canon

      def requisites = @requisites ||= self.class.required_requisites(operation)

      def body_lines
        lines = ["base_result = super", "return base_result if base_result.#{canon.failed_predicate}", ""]
        lines.concat(method_check, amount_checks, requisite_check)
        lines << "" unless lines.last.empty?
        lines << canon.success
      end

      def method_check
        return [] unless operation&.request_methods

        service.need(:request_methods)
        ["unless REQUEST_METHODS.include?(request_method)",
         "  return #{canon.failure_for_service_code("unsupported_request_method")}",
         "end"]
      end

      def amount_checks
        AmountLimits.for(operation, canon).flat_map do |limit|
          operator = limit.name == "MIN_AMOUNT" ? "<" : ">"
          code = limit.name == "MIN_AMOUNT" ? "amount_too_low" : "amount_too_high"
          ["# #{limit.evidence}",
           "return #{canon.failure_for_service_code(code)} if #{canon.accessor("amount")} #{operator} #{limit.name}"]
        end
      end

      def requisite_check
        return [] unless requisites

        ["missing = missing_requisites(operation, request_method)",
         "return #{canon.failure_for_service_code("missing_requisite")} unless missing.empty?"]
      end

      def missing_requisites_method
        lookup = requisites.is_a?(Hash) ? "REQUIRED_REQUISITES.fetch(request_method, [])" : "REQUIRED_REQUISITES"
        MethodData.build(name: "missing_requisites", params: "operation, request_method",
                         comment: ["Canonical requisite names the payout method needs (REQUIRED_REQUISITES) that " \
                                   "are missing from #{canon.accessor("requisite")}[request_method]."],
                         lines: ["requisite = #{canon.accessor("requisite")}.to_h[request_method] || {}",
                                 "#{lookup}.reject { |field| requisite[field] }"])
      end
    end
  end
end
