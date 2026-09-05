# frozen_string_literal: true

module ProviderIntegrator
  # Thor command-line interface (`bin/integrate`). Wave 0 ships the skeleton only: `version`
  # and an `integrate` command whose options mirror docs/TZ.md but which refuses to run until the
  # pipeline lands in wave 1. Output formatting, exit-code mapping and the Reporter arrive then.
  class CLI < Thor
    default_command :integrate
    map %w[--version -v] => :version

    # Thor exits with status 1 whenever a command raises Thor::Error.
    def self.exit_on_failure? = true

    desc "version", "Print the provider-integrator version"
    def version
      say "provider-integrator #{VERSION}"
    end

    desc "integrate", "Generate a provider integration from an OpenAPI spec"
    option :spec, type: :string, desc: "Path to the provider OpenAPI document (YAML or JSON)"
    option :provider, type: :string, desc: "Provider slug used for class and file names"
    option :output, type: :string, default: "./output", desc: "Directory for the generated files"
    option :overrides, type: :string, desc: "Path to an overrides.yml with fixed-key hints"
    option :lang, type: :string, default: "ruby", desc: "Target language (only ruby is supported)"
    def integrate
      raise Thor::Error, "integrate is not implemented until wave 1"
    end
  end
end
