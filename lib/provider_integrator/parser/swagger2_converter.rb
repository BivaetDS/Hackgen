# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Rewrites a Swagger 2.0 document into the OpenAPI 3.0 shape the rest of the pipeline reads, so
    # legacy providers cost nothing downstream: host/basePath become servers, definitions become
    # components.schemas, body and formData parameters become a requestBody, and response schemas
    # move under content. The conversion is announced with W103; nothing else changes.
    class Swagger2Converter
      TARGET_VERSION = "3.0.3"
      DEFAULT_CONSUMES = "application/json"
      DEFAULT_PRODUCES = "application/json"
      FORM_TYPE = "application/x-www-form-urlencoded"
      SECTIONS = { "definitions" => "schemas", "parameters" => "parameters", "responses" => "responses" }.freeze
      # 2.0 puts these on the parameter or header itself; 3.0 puts them into a "schema".
      SCHEMA_KEYS = %w[type format items enum default pattern minimum maximum exclusiveMinimum exclusiveMaximum
                       minLength maxLength minItems maxItems uniqueItems multipleOf].freeze
      REF_REWRITES = { "#/definitions/" => "#/components/schemas/", "#/parameters/" => "#/components/parameters/",
                       "#/responses/" => "#/components/responses/" }.freeze

      def self.call(loaded:, log:) = new(loaded:, log:).call

      def initialize(loaded:, log:)
        @source = loaded.document
        @log = log
        @swagger = loaded.swagger
      end

      # A Loader::Loaded holding the converted document.
      def call
        converted = rewrite_refs(build)
        log.add("W103")
        Loader::Loaded.new(document: converted, openapi: TARGET_VERSION, swagger: @swagger)
      end

      private

      attr_reader :source, :log

      def build
        base = source.except(*%w[swagger host basePath schemes consumes produces definitions securityDefinitions
                                 parameters responses paths])
        base.merge("openapi" => TARGET_VERSION, "info" => source["info"], "servers" => servers,
                   "paths" => paths, "components" => components)
      end

      def servers
        host = source["host"]
        return source["servers"] || [] unless host

        scheme = Array(source["schemes"]).first || "https"
        [{ "url" => "#{scheme}://#{host}#{source["basePath"]}" }]
      end

      def components
        existing = source["components"].is_a?(Hash) ? source["components"] : {}
        existing.merge(moved_sections)
      end

      def moved_sections
        moved = SECTIONS.filter_map { |from, to| [to, section(from, source[from])] if source[from].is_a?(Hash) }.to_h
        schemes = security_schemes
        schemes.empty? ? moved : moved.merge("securitySchemes" => schemes)
      end

      # Reusable responses and parameters need the same rewriting as the inline ones.
      def section(from, node)
        case from
        when "responses" then node.transform_values { |response| response_object({}, response) }
        when "parameters" then node.transform_values { |parameter| parameter_object(parameter) }
        else node
        end
      end

      # A non-body parameter carries its type inline in 2.0 and inside "schema" in 3.0.
      def parameter_object(parameter)
        return parameter unless parameter.is_a?(Hash) && parameter["in"] != "body"
        return parameter if parameter.key?("schema")

        schema = parameter.slice(*SCHEMA_KEYS)
        return parameter if schema.empty?

        parameter.except(*SCHEMA_KEYS, "collectionFormat").merge("schema" => schema)
      end

      def header_object(header)
        return header unless header.is_a?(Hash) && !header.key?("schema")

        schema = header.slice(*SCHEMA_KEYS)
        schema.empty? ? header : header.except(*SCHEMA_KEYS, "collectionFormat").merge("schema" => schema)
      end

      def security_schemes
        declared = source["securityDefinitions"]
        return {} unless declared.is_a?(Hash)

        declared.transform_values { |scheme| security_scheme(scheme) }
      end

      def security_scheme(scheme)
        case scheme["type"].to_s
        when "basic" then { "type" => "http", "scheme" => "basic", "description" => scheme["description"] }.compact
        when "oauth2" then oauth2(scheme)
        else scheme
        end
      end

      def oauth2(scheme)
        flow = { "tokenUrl" => scheme["tokenUrl"], "authorizationUrl" => scheme["authorizationUrl"],
                 "scopes" => scheme["scopes"] || {} }.compact
        name = scheme["flow"].to_s == "application" ? "clientCredentials" : "authorizationCode"
        { "type" => "oauth2", "flows" => { name => flow }, "description" => scheme["description"] }.compact
      end

      def paths
        (source["paths"] || {}).transform_values { |item| path_item(item) }
      end

      def path_item(item)
        return item unless item.is_a?(Hash)

        item.to_h do |key, node|
          next [key, node] unless Document::HTTP_METHODS.include?(key.to_s.downcase) && node.is_a?(Hash)

          [key, operation(node)]
        end
      end

      def operation(node)
        parameters = Array(node["parameters"])
        body, rest = split_parameters(parameters)
        converted = node.except("parameters", "consumes", "produces")
        converted["parameters"] = rest unless rest.empty?
        converted["requestBody"] = body if body
        converted["responses"] = responses(node)
        converted
      end

      def split_parameters(parameters)
        body = parameters.find { |parameter| parameter["in"] == "body" }
        form = parameters.select { |parameter| parameter["in"] == "formData" }
        rest = parameters.reject { |parameter| %w[body formData].include?(parameter["in"]) }
        [request_body(body, form), rest.map { |parameter| parameter_object(parameter) }]
      end

      def request_body(body, form)
        return json_body(body) if body
        return nil if form.empty?

        { "required" => form.any? { |parameter| parameter["required"] == true },
          "content" => { FORM_TYPE => { "schema" => form_schema(form) } } }
      end

      def json_body(body)
        media = source["consumes"]&.first || DEFAULT_CONSUMES
        { "required" => body["required"] == true, "description" => body["description"],
          "content" => { media => { "schema" => body["schema"] || {} } } }.compact
      end

      # formData parameters describe one object; rebuild it so the field extractor sees a schema.
      def form_schema(form)
        required = form.select { |parameter| parameter["required"] == true }.map { |parameter| parameter["name"] }
        properties = form.to_h { |parameter| [parameter["name"], property(parameter)] }
        schema = { "type" => "object", "properties" => properties }
        required.empty? ? schema : schema.merge("required" => required)
      end

      def property(parameter)
        parameter.except("name", "in", "required", "collectionFormat", "allowEmptyValue")
      end

      def responses(node)
        (node["responses"] || {}).transform_values { |response| response_object(node, response) }
      end

      def response_object(node, response)
        return response unless response.is_a?(Hash)

        converted = response["headers"].is_a?(Hash) ? response.merge("headers" => headers(response)) : response
        converted["schema"] ? with_content(node, converted) : converted
      end

      def with_content(node, response)
        media = node["produces"]&.first || source["produces"]&.first || DEFAULT_PRODUCES
        content = { media => { "schema" => response["schema"] }.merge(examples(response)) }
        response.except("schema", "examples").merge("content" => content)
      end

      def headers(response)
        response["headers"].transform_values { |header| header_object(header) }
      end

      def examples(response)
        example = response["examples"]
        return {} unless example.is_a?(Hash) && !example.empty?

        { "example" => example.values.first }
      end

      # "#/definitions/X" and friends only exist in 2.0; rewrite them everywhere at once.
      def rewrite_refs(node)
        case node
        when Hash
          node.to_h { |key, value| [key, key == "$ref" ? rewrite_ref(value) : rewrite_refs(value)] }
        when Array then node.map { |value| rewrite_refs(value) }
        else node
        end
      end

      def rewrite_ref(value)
        return value unless value.is_a?(String)

        REF_REWRITES.each { |from, to| return value.sub(from, to) if value.start_with?(from) }
        value
      end
    end
  end
end
