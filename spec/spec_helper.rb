# frozen_string_literal: true

require "bundler/setup"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "provider_integrator"
require "webmock/rspec"

# No spec may reach the network: the product never does either.
WebMock.disable_net_connect!

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

RSpec.configure do |config|
  # Golden service specs share Provider::* constants and are proved one by one in child processes
  # by spec/integration/generated_specs_spec.rb; do not also load all six into the repository suite.
  config.exclude_pattern = "spec/golden/**/*_spec.rb"
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed

  config.include FixtureHelpers
end
