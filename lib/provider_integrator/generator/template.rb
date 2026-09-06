# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders one ERB template from lib/provider_integrator/templates with a TemplateData object as
    # its only binding. Templates hold layout, never decisions: everything they print is a ready
    # String or Array on `data`. Leftover ERB tags in the output are a template bug (GenerationError).
    class Template
      DIR = File.join(LIB_ROOT, "templates")
      LEFTOVER = /<%|%>/

      # Renders +name+ ("service.rb.erb") with +data+; the result always ends with exactly one LF.
      def self.render(name, data)
        new(name).render(data)
      end

      def initialize(name)
        @name = name
        @path = File.join(DIR, name)
        raise GenerationError, "template #{name} not found" unless File.file?(@path)
      end

      def render(data)
        erb = ERB.new(Files.read(@path), trim_mode: "-")
        erb.location = [@path, 1]
        output = erb.result(TemplateBinding.new(data).context)
        raise GenerationError, "template #{@name} left ERB tags in its output" if output.match?(LEFTOVER)

        "#{output.rstrip}\n"
      end

      # The binding a template sees: only `data`.
      class TemplateBinding
        attr_reader :data

        def initialize(data)
          @data = data
        end

        def context = binding
      end
    end
  end
end
