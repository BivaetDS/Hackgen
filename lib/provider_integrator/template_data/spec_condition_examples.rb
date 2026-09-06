# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # `describe '#check_conditions'`: the fixture operation passes; an amount outside
    # MIN_AMOUNT/MAX_AMOUNT, an operation without the requisites of REQUIRED_REQUISITES and a
    # request_method outside REQUEST_METHODS are refused with the canon service codes.
    class SpecConditionExamples < SpecExamples
      LIMITS = { "MIN_AMOUNT" => ["amount_too_low", "below", "- 1"],
                 "MAX_AMOUNT" => ["amount_too_high", "above", "+ 1"] }.freeze

      def method_name = "check_conditions"

      def examples
        @examples ||= [valid_example, *limit_examples, *requisite_example, *method_example]
      end

      def summary
        parts = ["валидная операция"]
        parts.concat(limits.map { |limit| "`#{limit.name}`" })
        parts << "`REQUIRED_REQUISITES`" if required_requisites?
        parts << "`REQUEST_METHODS`" if operation&.request_methods
        parts.join(", ")
      end

      private

      def operation = data.context.create_operation
      def limits = AmountLimits.for(operation, canon)
      def method_argument = Code.str(subject.request_method)
      def call(target = "operation") = "service.check_conditions(#{target}, #{method_argument})"

      def valid_example
        example("accepts the operation built from fixtures.json", ["expect(#{call}).to be_success"])
      end

      def limit_examples
        limits.map do |limit|
          code, wording, delta = LIMITS.fetch(limit.name)
          amount = "operation_with(#{subject_member("amount")}: described_class::#{limit.name} #{delta})"
          example("refuses an amount #{wording} #{limit.name}",
                  ["result = #{call(amount)}", "", failure_expectation(canon.service_failure_parts(code))])
        end
      end

      def requisite_example
        return [] unless required_requisites?

        empty = "operation_with(#{subject_member("requisite")}: {})"
        parts = canon.service_failure_parts("missing_requisite")
        [example("refuses an operation without the requisites of REQUIRED_REQUISITES",
                 ["result = #{call(empty)}", "", failure_expectation(parts)])]
      end

      # True when the exercised payout method needs at least one requisite.
      def required_requisites?
        requisites = ConditionsMethod.required_requisites(operation) or return false
        required = requisites.is_a?(Hash) ? requisites[subject.request_method] : requisites
        !Array(required).empty?
      end

      def method_example
        return [] unless operation&.request_methods

        parts = canon.service_failure_parts("unsupported_request_method")
        [example("refuses a request_method outside REQUEST_METHODS",
                 ["result = service.check_conditions(operation, #{Code.str("unsupported")})", "",
                  failure_expectation(parts)])]
      end

      def subject_member(canonical) = canon.accessor(canonical).split(".", 2).last
    end
  end
end
