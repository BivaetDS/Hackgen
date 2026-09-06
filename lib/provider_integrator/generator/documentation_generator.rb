# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders INTEGRATION.md from TemplateData::Documentation through integration.md.erb.
    class DocumentationGenerator
      TEMPLATE = "integration.md.erb"
      FILE_NAME = "INTEGRATION.md"

      def initialize(context)
        @context = context
      end

      def call
        content = Template.render(TEMPLATE, TemplateData::Documentation.new(@context))
        Models::GeneratedFile.build(kind: :documentation, name: FILE_NAME, path: @context.path_for(FILE_NAME),
                                    content:)
      end
    end
  end
end
