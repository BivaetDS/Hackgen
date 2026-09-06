# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders <slug>_service_spec.rb: the RSpec file that proves the generated service against
    # fixtures.json through WebMock (TemplateData::ServiceSpec decides, service_spec.rb.erb lays
    # out), normalized with RuboCop in memory like the service itself.
    class RspecGenerator
      TEMPLATE = "service_spec.rb.erb"

      def initialize(context)
        @context = context
      end

      # The generated spec as a Models::GeneratedFile of kind :service_spec.
      def call
        name = @context.spec_file_name
        source = RubyFormatter.format(Template.render(TEMPLATE, @context.spec_data), name:)
        Models::GeneratedFile.build(kind: :service_spec, name:, path: @context.path_for(name), content: source)
      end
    end
  end
end
