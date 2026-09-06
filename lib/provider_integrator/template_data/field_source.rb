# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Decides where a request field's value comes from on the platform side: an Operation
    # accessor, a credentials entry, an ENV constant, a requisite of the current payout method,
    # a constant from the spec, or nothing (omitted, or nil with a TODO when required). Each
    # answer carries the Ruby expression for the service and a human description for INTEGRATION.md.
    class FieldSource
      Source = Data.define(:expression, :comments, :doc, :omitted, :env_constant, :helper) do
        def omitted? = omitted
      end

      UNITS_UNKNOWN = "amount units could not be determined from the spec (W401); passed as is"

      # +scope+ (a Scope) says which payout method the payload is for and how it is referenced.
      def initialize(operation, canon:, context:, scope: Scope.build)
        @operation = operation
        @canon = canon
        @context = context
        @scope = scope
      end

      # The Source for +field+ (a FieldMapping of the operation's request body).
      def for(field)
        return discriminator if discriminator?(field)
        return by_canonical(field) if field.canonical

        constant_or_unmapped(field)
      end

      private

      attr_reader :operation, :canon, :scope

      def discriminator?(field)
        methods = operation.request_methods
        (methods && field.provider_path == methods.discriminator_path) || field.canonical == "requisite.type"
      end

      def discriminator
        if scope.branch
          source(scope.method_source, doc: "константа #{Markdown.code(scope.method_source)} (ветка request_method)")
        else
          source(scope.method_source, doc: Markdown.code(scope.method_source))
        end
      end

      def by_canonical(field)
        case field.canonical
        when "amount" then amount(field)
        when "currency" then currency(field)
        when "external_id", "provider_operation_id" then accessor(field.canonical)
        when "merchant_account" then credential(canon.merchant_account_key)
        when "callback_url", "redirect_url" then env_constant(field.canonical)
        when /\Arequisite\./ then requisite(field)
        else constant_or_unmapped(field)
        end
      end

      def amount(field)
        base = canon.accessor("amount")
        conversion = field.conversion || fallback_conversion_for(field)
        return source(base, doc: Markdown.code(base)) unless conversion

        converted(base, conversion, borrowed: field.conversion.nil?)
      end

      # Another operation's amount (refund, quote) gets the create conversion when the types agree.
      def fallback_conversion_for(field)
        scope.fallback_conversion if scope.fallback_conversion && field.type
      end

      def converted(base, conversion, borrowed:)
        helper = AmountHelper.for(conversion)
        return identity_amount(base, conversion) unless helper

        comments = conversion_comments(conversion, borrowed)
        source("#{helper.name}(#{base})", doc: "#{Markdown.code(base)} #{helper.doc}", comments:, helper:)
      end

      # identity with value 1 means the units could not be determined (W401): amount passed as is.
      def identity_amount(base, conversion)
        comments = conversion.value == 1 ? [Generator::Confidence.todo(conversion.confidence, UNITS_UNKNOWN)] : []
        source(base, doc: "#{Markdown.code(base)} (major units, без преобразования)", comments:)
      end

      def conversion_comments(conversion, borrowed)
        text = "Evidence: #{conversion.evidence.join("; ")}"
        todo = Generator::Confidence.todo_if_needed(conversion.confidence, "confirm the amount units with the provider")
        borrowed_note = borrowed ? "Units assumed equal to create_request (not analysed for this operation)" : nil
        [text, todo, borrowed_note].compact
      end

      def currency(field)
        return constant(field) if field.constant

        accessor("currency")
      end

      def accessor(canonical)
        expression = canon.accessor(canonical)
        source(expression, doc: Markdown.code(expression))
      end

      def credential(key)
        expression = canon.credential(key)
        source(expression, doc: Markdown.code(expression))
      end

      def env_constant(canonical)
        source(canonical.upcase, doc: "ENV #{Markdown.code(@context.env_name(canonical))}", env_constant: canonical)
      end

      def requisite(field)
        child = field.canonical.split(".", 2).last
        expression = canon.requisite_access(scope.method_source, Code.str(child))
        doc = Markdown.code("#{canon.accessor("requisite")}[#{scope.method_source}][#{Code.str(child)}]")
        source(expression, doc:, comments: conditional_comments(field))
      end

      def conditional_comments(field)
        condition = field.conditional_required
        return [] unless condition

        text = "required when #{condition.when} = #{condition.equals} (#{condition.evidence.join("; ")})"
        [Generator::Confidence.todo_if_needed(condition.confidence, text) || text]
      end

      def constant_or_unmapped(field)
        return constant(field) unless field.constant.nil?
        return omitted unless field.required

        todo = Generator::Confidence.todo(field.confidence,
                                          "required field #{field.provider_path} has no platform source" \
                                          "#{field.canonical ? " for #{field.canonical}" : " (W403)"}")
        source("nil", doc: "TODO: нет источника на платформе", comments: [todo])
      end

      def constant(field)
        literal = Code.literal(field.constant)
        source(literal, doc: "константа #{Markdown.code(literal)}")
      end

      def omitted
        Source.new(expression: nil, comments: [], doc: "не отправляется: нет источника на платформе",
                   omitted: true, env_constant: nil, helper: nil)
      end

      def source(expression, doc:, comments: [], env_constant: nil, helper: nil)
        Source.new(expression:, comments:, doc:, omitted: false, env_constant:, helper:)
      end
    end
  end
end
