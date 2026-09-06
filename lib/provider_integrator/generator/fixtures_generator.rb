# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders fixtures.json. The content is a plain Hash (TemplateData::Fixtures) serialized with
    # JSON.pretty_generate in insertion order, so the file keeps the reference layout
    # (create_request, fetch_status, callback, ...) instead of sorted keys; the order is fixed by
    # the spec, so the output stays byte-identical across runs.
    class FixturesGenerator
      FILE_NAME = "fixtures.json"

      def initialize(context)
        @context = context
      end

      def call
        content = "#{JSON.pretty_generate(TemplateData::Fixtures.new(@context).to_h)}\n"
        Models::GeneratedFile.build(kind: :fixtures, name: FILE_NAME, path: @context.path_for(FILE_NAME), content:)
      end
    end
  end
end
