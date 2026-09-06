# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # The constants of the generated service: BASE_URL and the ENV-backed URLs at the top,
    # STATUS_MAP / ERROR_MAP / ERROR_ACTIONS at the bottom (where the reference service keeps them).
    class ServiceConstants
      # { http => ErrorMapping } as ERROR_MAP sees it: contract operations first, then the extras;
      # the first mapping of a status wins, statuses ascending.
      def self.error_mappings(spec, context)
        errors = (spec.contract_operations + context.extra_operations).flat_map(&:errors)
        errors.each_with_object({}) { |error, acc| acc[error.http] ||= error }.sort.to_h
      end

      def initialize(service)
        @service = service
        @canon = service.canon
        @spec = service.spec
        @context = service.context
      end

      def top
        [base_url, token_url, *env_constants, request_methods, *amount_limits, required_requisites].compact
      end

      def bottom
        [status_map, error_map, error_actions].compact
      end

      private

      attr_reader :service, :canon, :spec, :context

      def base_url
        server = context.default_server
        name = Code.str(context.env_name("base_url"))
        return no_server_url(name) unless server

        comment = ["#{server.environment.capitalize} by default#{other_servers(server)}."]
        ConstantData.single("BASE_URL", "ENV.fetch(#{name}, #{Code.str(server.url)})", comment:)
      end

      # "; production: https://..." for the servers BASE_URL does not default to.
      def other_servers(default)
        others = spec.servers.reject { |item| item.equal?(default) }.map { |item| "#{item.environment}: #{item.url}" }
        others.empty? ? "" : "; #{others.join(", ")}"
      end

      def no_server_url(name)
        ConstantData.single("BASE_URL", "ENV.fetch(#{name})",
                            comment: ["No servers in the spec (W104): set the URL in the environment."])
      end

      def token_url
        return nil unless service.need?(:token_url)

        url = service.flag(:token_url)
        name = Code.str(context.env_name("token_url"))
        expression = url ? "ENV.fetch(#{name}, #{Code.str(url)})" : "ENV.fetch(#{name})"
        ConstantData.single("TOKEN_URL", expression, comment: ["OAuth2 token endpoint (securitySchemes)."])
      end

      def env_constants
        service.env_constants.map do |canonical|
          name = Code.str(context.env_name(canonical))
          ConstantData.single(canonical.upcase, "ENV.fetch(#{name}, nil)",
                              comment: ["Sent in the request body as #{canonical}; configure per environment."])
        end
      end

      def request_methods
        methods = context.create_operation&.request_methods
        return nil unless methods

        comment = ["Payout methods accepted as request_method (#{methods.source} of #{methods.discriminator_path}); " \
                   "the first is the default."]
        ConstantData.single("REQUEST_METHODS", "#{Code.word_array(methods.values)}.freeze", comment:)
      end

      def amount_limits
        AmountLimits.for(context.create_operation, canon).map do |limit|
          ConstantData.single(limit.name, Code.literal(limit.value), comment: [limit.comment])
        end
      end

      def required_requisites
        requisites = ConditionsMethod.required_requisites(context.create_operation)
        return nil unless requisites

        comment = ["Canonical requisite names each payout method needs (required in the schema, or required when " \
                   "the method matches - see INTEGRATION.md)."]
        if requisites.is_a?(Array)
          return ConstantData.single("REQUIRED_REQUISITES", "#{Code.word_array(requisites)}.freeze", comment:)
        end

        entries = requisites.map { |branch, names| "#{Code.str(branch)} => #{Code.word_array(names)}" }
        ConstantData.hash("REQUIRED_REQUISITES", entries, comment:)
      end

      def status_map
        return nil if spec.statuses.empty?

        entries = spec.statuses.map do |mapping|
          todo = Generator::Confidence.todo_if_needed(mapping.confidence, mapping.evidence.join("; "))
          Code::Entry["#{Code.str(mapping.provider)} => #{Code.str(mapping.canonical)}", todo]
        end
        ConstantData.hash("STATUS_MAP", entries, comment: ["Provider status -> Space Payments status (statuses.yml); " \
                                                           "evidence per status in INTEGRATION.md."])
      end

      def error_mappings = @error_mappings ||= self.class.error_mappings(spec, context)

      def error_map
        return nil if error_mappings.empty?

        entries = error_mappings.map do |http, error|
          Code::Entry["#{http} => #{Code.str(error.canonical)}", low_confidence(error)]
        end
        ConstantData.hash("ERROR_MAP", entries, comment: ["HTTP status -> canonical error code (Space Payments); " \
                                                          "provider codes and evidence in INTEGRATION.md."])
      end

      def error_actions
        return nil if error_mappings.empty?

        entries = error_mappings.map { |http, error| "#{http} => #{Code.str(error.action)}" }
        ConstantData.hash("ERROR_ACTIONS", entries, comment: ["HTTP status -> what the platform should do " \
                                                              "(canonical_contract.yml -> actions)."])
      end

      def low_confidence(error)
        Generator::Confidence.todo_if_needed(error.confidence, "HTTP #{error.http}: #{error.evidence.join("; ")}")
      end
    end
  end
end
