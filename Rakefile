# frozen_string_literal: true

require "bundler/setup"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

namespace :golden do
  desc "Regenerate golden outputs under spec/golden/ (commit the diff with an explanation)"
  task :update do
    require_relative "lib/provider_integrator"
    ProviderIntegrator::Golden.update!
  end
end

namespace :lint do
  desc "Validate lib/provider_integrator/dictionaries/*.yml against their JSON schemas"
  task :dictionaries do
    require_relative "lib/provider_integrator"
    report = ProviderIntegrator::Schemas.dictionary_errors
    report.each do |name, errors|
      puts(errors.empty? ? "#{name}: ok" : "#{name}:\n  #{errors.join("\n  ")}")
    end
    abort "dictionary validation failed" if report.values.any? { |errors| !errors.empty? }
  end
end

desc "Quality gate: RSpec + RuboCop"
task check: %i[spec rubocop]

task default: :check
