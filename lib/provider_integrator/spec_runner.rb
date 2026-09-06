# frozen_string_literal: true

require "open3"
require "rbconfig"

module ProviderIntegrator
  # Runs the generated service spec with the current Ruby and installed RSpec executable. The
  # command is an argv array (never a shell), and both streams are captured for the CLI diagnostic.
  class SpecRunner
    SUMMARY = /(\d+) examples?, (\d+) failures?/

    def self.call(spec_path:, chdir:) = new(spec_path:, chdir:).call

    def initialize(spec_path:, chdir:)
      @spec_path = spec_path
      @chdir = chdir
    end

    # Returns Models::SpecRun; unavailable RSpec and spawn failures are data, not exceptions.
    def call
      rspec = Gem.bin_path("rspec-core", "rspec")
      output, process = Open3.capture2e(RbConfig.ruby, rspec, File.basename(@spec_path), "--format", "progress",
                                        "--no-color", chdir: @chdir)
      build(output, process.exitstatus)
    rescue Gem::Exception => e
      Models::SpecRun.failed("RSpec is unavailable: #{e.message}")
    rescue SystemCallError => e
      Models::SpecRun.failed("RSpec could not be started: #{e.message}")
    end

    private

    def build(output, exit_status)
      match = SUMMARY.match(output)
      return Models::SpecRun.failed("RSpec finished without an example summary", output:, exit_status:) unless match

      Models::SpecRun.new(examples: match[1].to_i, failures: match[2].to_i, output:, exit_status:, error: nil)
    end
  end
end
