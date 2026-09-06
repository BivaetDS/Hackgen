# frozen_string_literal: true

require "bundler/setup"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

namespace :golden do
  desc "Regenerate golden outputs under spec/golden/ (commit the diff with an explanation); " \
       "rake \"golden:update[novapay,bearerpay]\" adds or refreshes the named specs"
  task :update, [:names] do |_task, args|
    require_relative "lib/provider_integrator"
    # Rake treats every comma-delimited value after the first as an "extra" when the task has
    # one named argument. Keep accepting both `update[a,b]` and a whitespace-delimited first arg.
    names = [args[:names], *args.extras].flat_map { |value| value.to_s.split(/[,\s]+/) }.reject(&:empty?)
    written = ProviderIntegrator::Golden.update!(names.empty? ? ProviderIntegrator::Golden.present : names)
    puts written.empty? ? "no golden directories (pass names: rake \"golden:update[novapay]\")" : written
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

CRLF = "\r\n"
LF = "\n"

desc "Normalize CRLF to LF in text files (rubocop -A rewrites files as CRLF on Windows)"
task :lf do
  patterns = ["lib/**/*.{rb,erb,yml,json}", "spec/**/*.{rb,yml,yaml,json}", "bin/*", "Rakefile", "Gemfile",
              "*.md", "docs/*.md", "examples/*"]
  fixed = Dir[*patterns].select do |path|
    next false unless File.file?(path)

    content = File.binread(path)
    next false unless content.include?(CRLF)

    File.binwrite(path, content.gsub(CRLF, LF))
    true
  end
  puts fixed.empty? ? "line endings already LF" : "normalized: #{fixed.join(", ")}"
end

desc "Quality gate: RSpec + RuboCop + dictionary schemas"
task check: %i[spec rubocop lint:dictionaries]

task default: :check
