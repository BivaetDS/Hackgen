# frozen_string_literal: true

module ProviderIntegrator
  # Maintenance of spec/golden/<spec>/ (byte-exact expected outputs of the whole generator for
  # the fixture specs). Driven by `rake golden:update[name,...]`; the golden spec compares the
  # files byte for byte, so every deliberate change of the output shows up as a reviewable diff.
  # The list of maintained specs is the set of directories under spec/golden (data, not code).
  module Golden
    ROOT = File.expand_path("../../spec", __dir__)
    SPECS_DIR = File.join(ROOT, "fixtures", "specs")
    GOLDEN_DIR = File.join(ROOT, "golden")

    module_function

    # Generates the current output for +name+ (a fixture spec without extension) into memory.
    def generate(name)
      spec = Parser.call!(path: File.join(SPECS_DIR, "#{name}.yaml"))
      Generator.call(spec:, output_dir: File.join(GOLDEN_DIR, name))
    end

    # Regenerates the golden directories of +names+ (default: every directory present) from the
    # current generator output; returns the paths written.
    def update!(names = present)
      names.flat_map do |name|
        result = generate(name)
        raise GenerationError, "#{name}: #{result.errors.map(&:message).join("; ")}" unless result.success?

        directory = File.join(GOLDEN_DIR, name)
        FileUtils.rm_rf(directory)
        result.files.map { |file| Files.write(File.join(directory, file.name), file.content) }
      end
    end

    # Names of the golden directories present on disk.
    def present
      Dir.children(GOLDEN_DIR).select { |entry| File.directory?(File.join(GOLDEN_DIR, entry)) }.sort
    rescue Errno::ENOENT
      []
    end
  end
end
