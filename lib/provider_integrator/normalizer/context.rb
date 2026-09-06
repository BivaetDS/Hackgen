# frozen_string_literal: true

module ProviderIntegrator
  module Normalizer
    # The services one parse run shares: the document being read, the event log, the overrides and
    # every analyzer. Passing this one object around keeps the analyzers stateless and makes it
    # obvious that they all read the same dictionaries.
    class Context
      attr_reader :document, :log, :overrides

      def initialize(document:, log:, overrides:)
        @document = document
        @log = log
        @overrides = overrides
      end

      def extractor = @extractor ||= Parser::SchemaExtractor.new(document)
      def composer = @composer ||= Parser::ExampleComposer.new(document)
      def classifier = @classifier ||= OperationClassifier.new
      def field_mapper = @field_mapper ||= FieldMapper.new
      def error_classifier = @error_classifier ||= ErrorClassifier.new
      def status_mapper = @status_mapper ||= StatusMapper.new
      def money_units = @money_units ||= MoneyUnits.new
      def conditional = @conditional ||= ConditionalRequired.new
      def signature_analyzer = @signature_analyzer ||= SignatureAnalyzer.new
      def gateway = @gateway ||= GatewayConfigurator.new
      def authentication = @authentication ||= Authentication.new(document:, log:)
      def canon = Dictionaries.canonical_contract
    end
  end
end
