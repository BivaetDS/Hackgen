# frozen_string_literal: true

module ProviderIntegrator
  module Models
    # One diagnostic emitted by the parser or generator. `code` is a registry code (E*/W*/I*),
    # `level` is "error" | "warning" | "info", `location` a JSON-pointer-like path into the spec
    # ("#/paths/~1payouts/post") or nil, `details` a JSON object with the placeholder values or nil.
    Event = Data.define(:code, :level, :message, :location, :details) do
      include Base

      def error? = level == "error"
      def warning? = level == "warning"
      def info? = level == "info"
    end
  end
end
