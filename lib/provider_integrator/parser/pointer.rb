# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # RFC 6901 JSON pointers, the addressing scheme of every event location and $ref in the IR
    # (docs/IR_CONTRACT.md 3): "#/paths/~1payouts~1{payout_id}/get".
    module Pointer
      module_function

      # Escapes one pointer segment ("/payouts" -> "~1payouts").
      def escape(segment) = segment.to_s.gsub("~", "~0").gsub("/", "~1")

      # Unescapes one pointer segment.
      def unescape(segment) = segment.to_s.gsub("~1", "/").gsub("~0", "~")

      # Builds "#/a/b/c" from raw (unescaped) segments.
      def build(*segments) = "#/#{segments.flatten.map { |segment| escape(segment) }.join("/")}"

      # Appends segments to an existing pointer.
      def join(pointer, *segments)
        return build(*segments) if pointer.nil? || pointer == "#"

        "#{pointer}/#{segments.flatten.map { |segment| escape(segment) }.join("/")}"
      end

      # Splits "#/a/b" into ["a", "b"]; returns nil when the reference is not a local pointer.
      def parse(reference)
        return nil unless reference.is_a?(String) && (reference == "#" || reference.start_with?("#/"))

        reference == "#" ? [] : reference[2..].split("/", -1).map { |segment| unescape(segment) }
      end

      # True when +reference+ addresses this document ("#/..."), false for file/URL references.
      def local?(reference) = !parse(reference).nil?
    end
  end
end
