# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders base_contract.rb: the stub of the platform contract the generated service and its
    # specs load when Space Payments' real BaseService is not around (docs/PLAN.md 4).
    class BaseContractGenerator
      TEMPLATE = "base_contract.rb.erb"
      FILE_NAME = "base_contract.rb"

      def initialize(context)
        @context = context
      end

      def call
        data = TemplateData::BaseContract.new(@context)
        source = RubyFormatter.format(Template.render(TEMPLATE, data), name: FILE_NAME)
        Models::GeneratedFile.build(kind: :base_contract, name: FILE_NAME, path: @context.path_for(FILE_NAME),
                                    content: source)
      end
    end
  end
end
