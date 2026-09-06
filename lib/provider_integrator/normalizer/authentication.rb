# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Reads securitySchemes and the per-operation security requirements into one Authentication
    # (docs/IR_CONTRACT.md 2.2). When a spec declares several schemes the one most operations use
    # wins and the rest are kept as alternatives, so INTEGRATION.md can list them.
    class Authentication
      TYPES = {
        "apikey" => "api_key", "http.bearer" => "http_bearer", "http.basic" => "http_basic",
        "oauth2" => "oauth2", "oauth2.clientcredentials" => "oauth2_client_credentials"
      }.freeze

      def initialize(document:, log:, canon: Dictionaries.canonical_contract)
        @document = document
        @log = log
        @canon = canon
      end

      # Builds Models::Authentication from the document; +usage+ is { scheme name => operation count }.
      def call(usage:, operation_count:)
        schemes = document.security_schemes
        return none if schemes.empty?

        ranked = schemes.keys.sort_by { |name| [-usage.fetch(name, 0), schemes.keys.index(name)] }
        build(ranked, schemes, usage, operation_count)
      end

      # Scheme names an operation must satisfy: its own security, else the document default.
      def requirements_for(operation)
        declared = operation.node["security"] || document.global_security
        return [] unless declared.is_a?(Array)

        declared.flat_map { |requirement| requirement.is_a?(Hash) ? requirement.keys : [] }.uniq
      end

      # True when the operation explicitly opts out of authentication.
      def public?(operation) = operation.node["security"].is_a?(Array) && operation.node["security"].empty?

      private

      attr_reader :document, :log, :canon

      def build(ranked, schemes, usage, operation_count)
        name = ranked.first
        others = ranked.drop(1)
        node = schemes.fetch(name)
        type = type_of(node, name)
        location, parameter = placement(node, type)
        Models::Authentication.new(
          type:, scheme_name: name, location:, name: parameter, bearer_format: node["bearerFormat"],
          token_url: token_url(node), scopes: scopes(node), credentials_key: credentials_key(type),
          confidence: confidence(name, others, usage, operation_count), source: "security_schemes",
          evidence: evidence(name, node, type, usage, operation_count),
          alternatives: others.map { |other| alternative(other, schemes.fetch(other)) }
        )
      end

      def none
        Models::Authentication.new(type: "none", scheme_name: nil, location: nil, name: nil, bearer_format: nil,
                                   token_url: nil, scopes: [], credentials_key: nil, confidence: 1.0,
                                   source: "security_schemes", evidence: ["no securitySchemes declared"],
                                   alternatives: [])
      end

      def alternative(name, node)
        type = type_of(node, name, report: false)
        location, parameter = placement(node, type)
        Models::AuthAlternative.new(scheme_name: name, type:, location:, name: parameter)
      end

      def type_of(node, name, report: true)
        declared = node["type"].to_s.downcase
        key = declared == "http" ? "http.#{node["scheme"].to_s.downcase}" : declared
        key = "oauth2.clientcredentials" if declared == "oauth2" && client_credentials?(node)
        type = TYPES[key]
        return type if type

        log.add("W501", scheme_name: name, type: node["type"].to_s) if report
        "unknown"
      end

      def placement(node, type)
        return [node["in"], node["name"]] if type == "api_key"
        return %w[header Authorization] if type.start_with?("http_")

        type.start_with?("oauth2") ? %w[header Authorization] : [nil, nil]
      end

      def client_credentials?(node) = node.dig("flows", "clientCredentials").is_a?(Hash)

      def token_url(node) = node.dig("flows", "clientCredentials", "tokenUrl")

      def scopes(node)
        flows = node["flows"]
        return [] unless flows.is_a?(Hash)

        flows.values.grep(Hash).flat_map { |flow| (flow["scopes"] || {}).keys }.uniq
      end

      def credentials_key(type) = Array(canon.fetch("credentials")[type]).first

      # One scheme, or one clearly used more than the others, is certain; a tie is not.
      def confidence(name, others, usage, operation_count)
        return 1.0 if others.empty?
        return 1.0 if usage.fetch(name, 0) > (operation_count / 2.0)

        others.any? { |other| usage.fetch(other, 0) == usage.fetch(name, 0) } ? 0.7 : 1.0
      end

      def evidence(name, node, type, usage, operation_count)
        scheme = node["scheme"] ? " #{node["scheme"]}" : ""
        location, parameter = placement(node, type)
        where = location ? " in #{location} #{parameter}" : ""
        oauth = type == "oauth2_client_credentials" ? " (clientCredentials #{token_url(node)})" : ""
        ["securitySchemes.#{name}: #{node["type"]}#{scheme}#{where}#{oauth}",
         "security: #{name} used by #{usage.fetch(name, 0)} of #{operation_count} operations"]
      end
    end
  end
end
