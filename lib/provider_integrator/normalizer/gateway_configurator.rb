# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # Derives the ProviderGateway config ("sbp_payout" / "RUB_SBP_WITHDRAW") from three facts of the
    # create operation: the currency it pins, the default payout method and the direction of the
    # money (docs/IR_CONTRACT.md 2.10). Each fact read from a weaker source costs confidence, and
    # the result is always reported (I403) because the platform keys its routing on it.
    class GatewayConfigurator
      BASE_CONFIDENCE = 0.9
      PENALTY = 0.3
      MIN_CONFIDENCE = 0.3
      DEFAULT_METHOD = "default"
      UNKNOWN_CURRENCY = "XXX"
      # The primary sources of a direction keyword; anything below costs confidence.
      PRIMARY_DIRECTION_SOURCES = %i[operation_id path tag].freeze

      def initialize(operations: Dictionaries.operations, canon: Dictionaries.canonical_contract)
        @operations = operations
        @canon = canon
      end

      # Builds Models::GatewayConfig for the create +operation+ (a Models::Operation) whose request
      # fields are +fields+ (Models::FieldMapping); +title+ is info.title.
      def call(operation:, fields:, title:)
        currency = currency_of(fields)
        method = method_of(operation)
        direction = direction_of(operation, title)
        penalties = [currency[:primary], method[:primary], direction[:primary]].count(false)
        build(currency, method, direction, penalties)
      end

      # True when the direction had to fall back to the dictionary default (the caller raises W405).
      def defaulted?(direction) = direction[:source] == :default

      private

      attr_reader :operations, :canon

      def build(currency, method, direction, penalties)
        facts = { direction: direction[:value], currency: currency[:value], method: method[:value] }
        Models::GatewayConfig.new(
          **names_for(facts), **facts,
          confidence: [BASE_CONFIDENCE - (PENALTY * penalties), MIN_CONFIDENCE].max.round(2),
          evidence: [currency[:evidence], method[:evidence], direction[:evidence]]
        )
      end

      # The two platform-side names, rendered from the canon templates of this direction.
      def names_for(facts)
        template = canon.fetch("gateway_config").fetch(facts.fetch(:direction))
        values = { method: facts.fetch(:method), currency: facts.fetch(:currency) || UNKNOWN_CURRENCY }
        { external_method: render(template.fetch("external_method"), values),
          gateway: render(template.fetch("gateway"), values) }
      end

      def render(template, values)
        template.gsub(/%\{(\w+)\}/) do
          key = Regexp.last_match(1)
          value = values.fetch(key.downcase.to_sym).to_s
          key == key.upcase ? value.upcase : Inflector.snake_case(value)
        end
      end

      # A currency fixed by an enum or const is a fact; one that only appears in an example is a hint.
      def currency_of(fields)
        field = fields.find { |item| item.canonical == "currency" }
        return { value: nil, primary: false, evidence: "currency: unknown (unknown)" } unless field

        if field.constant
          { value: field.constant.to_s, primary: true, evidence: "currency: #{field.constant} (enum constant)" }
        elsif field.example
          { value: field.example.to_s, primary: false, evidence: "currency: #{field.example} (example)" }
        else
          { value: nil, primary: false, evidence: "currency: unknown (unknown)" }
        end
      end

      def method_of(operation)
        methods = operation.request_methods
        return { value: DEFAULT_METHOD, primary: false, evidence: no_method_evidence } unless methods

        { value: methods.default, primary: true,
          evidence: "request method: #{methods.default} (default of #{methods.discriminator_path})" }
      end

      def no_method_evidence = "request method: #{DEFAULT_METHOD} (no requisite type)"

      # Where the money goes: withdraw or deposit, read from the strongest source that says so.
      def direction_of(operation, title)
        sources(operation, title).each do |source, label, tokens|
          hit = direction_hit(tokens)
          next unless hit

          return { value: hit[:direction], source:, primary: PRIMARY_DIRECTION_SOURCES.include?(source),
                   evidence: "direction: #{hit[:direction]} (token '#{hit[:token]}' in #{label})" }
        end
        default_direction
      end

      def default_direction
        value = directions.fetch("default")
        { value:, source: :default, primary: false, evidence: "direction: #{value} (default)" }
      end

      def sources(operation, title)
        [[:operation_id, "operationId #{operation.operation_id}", Tokens.identifier(operation.operation_id)],
         [:path, "path #{operation.path}", Tokens.path(operation.path)]] +
          operation.tags.map { |tag| [:tag, "tag #{tag}", Tokens.tag(tag)] } +
          [[:summary, "summary", Tokens.words(operation.summary)],
           [:description, "description", Tokens.words(operation.description)],
           [:title, "info.title", Tokens.words(title)]]
      end

      def direction_hit(tokens)
        directions.each do |direction, stems|
          next if direction == "default"

          token = Tokens.match(tokens, stems)
          return { direction:, token: } if token
        end
        nil
      end

      def directions = operations.fetch("direction")
    end
  end
end
