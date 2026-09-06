# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders <slug>_service.rb: builds the TemplateData::Service (every decision), renders
    # service.rb.erb (layout only) and normalizes the result with RuboCop in memory.
    class ServiceGenerator
      TEMPLATE = "service.rb.erb"

      def initialize(context)
        @context = context
      end

      # The generated service as a Models::GeneratedFile.
      def call
        data = TemplateData::Service.new(@context)
        source = RubyFormatter.format(Template.render(TEMPLATE, data), name: @context.service_file_name)
        Models::GeneratedFile.build(kind: :service, name: @context.service_file_name,
                                    path: @context.path_for(@context.service_file_name), content: source)
      end
    end
  end
end
