# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Everything one generation run shares: the IR, the provider slug chosen for names, the
    # Space Payments canon and the output directory. Template data objects read from here so
    # naming decisions (class, ENV prefix, file names) are made exactly once.
    class Context
      attr_reader :spec, :slug, :output_dir

      def initialize(spec:, provider: nil, output_dir: "./output")
        @spec = spec
        @slug = provider.nil? || provider.empty? ? spec.provider.slug : provider
        raise ArgumentError, "provider slug #{@slug.inspect} is not a safe identifier" unless Inflector.slug?(@slug)

        @output_dir = output_dir
      end

      # The Space Payments canon (dictionaries/canonical_contract.yml).
      def canon = Dictionaries.canonical_contract

      # "AcmepayService".
      def class_name = "#{Inflector.class_name(slug)}Service"

      # "ACMEPAY".
      def constant_prefix = Inflector.constant_case(slug)

      # "acmepay_service.rb".
      def service_file_name = "#{Inflector.identifier(slug)}_service.rb"

      # "ACMEPAY_BASE_URL" and friends from canonical_contract.yml -> env.
      def env_name(key)
        template = canon.dig("env", key.to_s) or raise GenerationError, "no env template for #{key}"
        format(template, SLUG: constant_prefix)
      end

      # Target path for +name+ inside the output directory.
      def path_for(name) = File.join(output_dir, name)

      def create_operation = spec.operation_for("create_request")
      def status_operation = spec.operation_for("fetch_status")
      def webhook = spec.webhook

      # Operations generated as public methods outside the contract, in spec order.
      def extra_operations = spec.operations.reject { |operation| operation.in_contract || operation.kind == "webhook" }

      # The server the generated BASE_URL defaults to: the first sandbox, else the first declared.
      def default_server
        spec.servers.find { |server| server.environment == "sandbox" } || spec.servers.first
      end

      # The service template data, built once and shared by the service and documentation generators.
      def service_data
        @service_data ||= TemplateData::Service.new(self)
      end
    end
  end
end
