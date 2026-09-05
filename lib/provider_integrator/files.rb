# frozen_string_literal: true

module ProviderIntegrator
  # Binary-safe file access. Ruby on Windows translates LF<->CRLF in text mode, which silently
  # breaks byte-identical output and golden comparisons, so every read/write of generated or
  # compared content goes through these helpers.
  module Files
    module_function

    # Reads the whole file as UTF-8 without newline translation.
    def read(path)
      File.binread(path).force_encoding(Encoding::UTF_8)
    end

    # Writes +content+ byte-for-byte (LF endings preserved), creating parent directories.
    def write(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
      path
    end
  end
end
