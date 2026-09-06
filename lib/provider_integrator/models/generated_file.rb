# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One output file held in memory until the pipeline writes it: `name` is the file name inside
    # the output directory, `path` the target path, `content` the exact bytes (LF endings) and
    # `sha256` their digest. `kind` names the artefact (service | base_contract | documentation |
    # fixtures | report) so callers can find a file without parsing its name.
    GeneratedFile = Data.define(:kind, :name, :path, :content, :sha256) do
      # Builds the file, computing the digest from +content+.
      def self.build(kind:, name:, path:, content:)
        new(kind: kind.to_s, name:, path:, content:, sha256: JsonCanon.sha256(content))
      end

      # { "path" => name, "sha256" => digest } for the generation report (no content).
      def manifest = { "path" => name, "sha256" => sha256 }
    end
  end
end
