# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The objects the generated spec hands to the service: the credentials hash and the platform
    # Operation, both derived from fixtures.json (the create request and its success response) so
    # that what the service sends back equals the fixture by construction. Values the fixture does
    # not carry get a "test-<name>" placeholder.
    class SpecSubject
      PLACEHOLDER = "test-%{name}"
      FALLBACK_AMOUNT = 100
      SHORT_LITERAL = 80

      def initialize(data)
        @data = data
        @spec = data.spec
        @canon = data.canon
        @operation = data.context.create_operation
        @request = data.fixture("create_request", "request") || {}
      end

      # The payout method the spec exercises: the one the fixture request names when it is a known
      # method of the spec, else the default of the create signature.
      def request_method
        @request_method ||= begin
          methods = operation&.request_methods
          value = methods && dig(request, methods.discriminator_path)
          methods&.values&.include?(value) ? value : data.service.default_request_method
        end
      end

      def id = field_value("external_id") || placeholder("operation")
      def currency = field_value("currency") || amount_field_constant("currency")

      # operation.amount: the fixture amount converted back into platform units.
      def amount
        @amount ||= AmountHelper.reverse(amount_field&.conversion, field_value("amount")) || fallback_amount
      end

      # The provider id the operation carries, from the create success example or the status example.
      def provider_operation_id
        @provider_operation_id ||= success_id || placeholder("provider-id")
      end

      # { child => value } for the requisite fields of the exercised payout method, in field order.
      def requisite
        @requisite ||= requisite_fields.to_h do |field|
          child = field.canonical.delete_prefix(ConditionsMethod::REQUISITE_PREFIX)
          [child, dig(request, field.provider_path) || placeholder(child)]
        end
      end

      # { "api_key" => "test-api_key", ... } in canon order; the merchant id comes from the fixture.
      def credentials
        @credentials ||= credential_keys.to_h { |key| [key, credential_value(key)] }
      end

      # The value the service will send for a request field with FieldSource +source+ (nil when the
      # platform supplies nothing: ENV constants, missing sources, omitted fields).
      def sent_value(source)
        case source.kind
        when :constant then source.key
        when :discriminator then request_method
        when :amount then AmountHelper.apply(source.key, amount)
        when :accessor then accessor_value(source.key)
        when :credential then credentials[source.key]
        when :requisite then requisite[source.key]
        end
      end

      # Lines of `Provider::Operation.new(...)` for the `operation` let; member names come from the
      # canon accessors, as in the contract stub.
      def operation_lines
        values = { "external_id" => id, "amount" => amount, "currency" => currency,
                   "provider_operation_id" => provider_operation_id }
        entries = values.map { |canonical, value| "#{member(canonical)}: #{Code.literal(value)}" }
        entries << "#{member("requisite")}: #{requisite_literal}"
        Code.hash_lines(entries, open: "#{canon.namespace}::Operation.new(", close: ")")
      end

      # "{ api_key: 'test-api_key', callback_secret: 'test-callback_secret' }".
      def credentials_literal
        "{ #{credentials.map { |key, value| "#{Code.key(key)} #{Code.literal(value)}" }.join(", ")} }"
      end

      private

      attr_reader :data, :spec, :canon, :operation, :request

      def placeholder(name) = format(PLACEHOLDER, name:)
      def dig(hash, path) = CallbackOutcome.dig(hash, path.to_s)

      def field(canonical) = operation&.request_fields&.find { |item| item.canonical == canonical }
      def amount_field = field("amount")

      def field_value(canonical)
        item = field(canonical) or return nil
        dig(request, item.provider_path)
      end

      def amount_field_constant(canonical) = field(canonical)&.constant

      def fallback_amount
        AmountLimits.for(operation, canon).find { |limit| limit.name == "MIN_AMOUNT" }&.value || FALLBACK_AMOUNT
      end

      def success_id
        create_id = success_body_id(operation, "create_request")
        create_id || success_body_id(data.context.status_operation, "fetch_status")
      end

      def success_body_id(target, fixture_key)
        return nil unless target

        path = data.service.provider_id_path(target) or return nil
        body = data.fixture(fixture_key, "response_#{target.success_codes.first}") or return nil
        dig(body, path)
      end

      def requisite_fields
        ConditionsMethod.requisite_fields(operation).select do |field|
          PayloadBuilder.in_branch?(field, request_method, operation)
        end
      end

      def member(canonical) = canon.accessor(canonical).split(".", 2).last

      # The requisite hash literal: { 'sbp' => { 'phone' => '7900...' } }, nested over several lines
      # when one line would not fit.
      def requisite_literal
        inner = requisite.map { |child, value| "#{Code.str(child)} => #{Code.literal(value)}" }
        one_line = "{ #{Code.str(request_method)} => { #{inner.join(", ")} } }"
        return one_line if one_line.length <= SHORT_LITERAL

        nested = Code.hash_lines(inner, open: "#{Code.str(request_method)} => {", close: "}").join("\n")
        Code.hash_lines([nested], open: "{", close: "}").join("\n")
      end

      def accessor_value(canonical)
        { "external_id" => id, "currency" => currency, "provider_operation_id" => provider_operation_id }[canonical]
      end

      def credential_keys
        keys = canon.credential_keys(spec.authentication.type)
        keys += [canon.callback_secret_key] if spec.webhook&.signature
        keys += [canon.merchant_account_key] if field("merchant_account")
        keys.uniq
      end

      def credential_value(key)
        return placeholder(key) unless key == canon.merchant_account_key

        field_value("merchant_account") || placeholder(key)
      end
    end
  end
end
