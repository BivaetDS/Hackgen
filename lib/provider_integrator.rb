# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "psych"
require "json_schemer"
require "openapi3_parser"
require "thor"
require "zeitwerk"

require_relative "provider_integrator/version"
require_relative "provider_integrator/compat/openapi3_parser_pointer_patch"

# provider-integrator: a deterministic compiler from a payment-provider OpenAPI spec to a
# Space Payments integration (Ruby service, INTEGRATION.md, fixtures.json). Rules, dictionaries
# and weighted scoring only: no network and no ML at runtime.
module ProviderIntegrator
  # Base class for the library's own exceptions; only fatal conditions raise, everything
  # else travels as events inside a Result.
  class Error < StandardError; end

  # The input spec cannot be used at all (unreadable, not OpenAPI, unresolvable $ref, ...).
  class SpecError < Error; end

  # A template or output step failed in a way the pipeline cannot recover from.
  class GenerationError < Error; end

  # Absolute path of lib/provider_integrator (dictionaries, schemas and templates live there).
  LIB_ROOT = File.expand_path("provider_integrator", __dir__)

  @loader = Zeitwerk::Loader.for_gem
  @loader.inflector.inflect("cli" => "CLI")
  # version.rb and the compat shim are required explicitly above; data files are not Ruby.
  @loader.ignore("#{__dir__}/provider_integrator/version.rb")
  @loader.ignore("#{__dir__}/provider_integrator/compat")
  @loader.ignore("#{__dir__}/provider_integrator/dictionaries/*.yml")
  @loader.ignore("#{__dir__}/provider_integrator/schemas/*.json")
  @loader.setup

  class << self
    # The Zeitwerk loader; exposed so specs can eager load the whole tree.
    attr_reader :loader
  end
end
