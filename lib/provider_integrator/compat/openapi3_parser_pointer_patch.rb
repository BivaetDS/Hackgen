# frozen_string_literal: true

require "openapi3_parser"

module ProviderIntegrator
  # Runtime shims for third-party gems. Required explicitly from lib/provider_integrator.rb
  # (not autoloaded) so a patch is in place before any spec is read.
  module Compat
    # openapi3_parser 0.10.1 merges JSON pointers with File.expand_path, which on Windows prepends
    # the current drive letter ("C:") to the pointer and breaks every Operation lookup with a
    # NoMethodError on a nil parent node. This module re-implements the merge with pure segment
    # arithmetic: "." is skipped, ".." pops a segment, numeric strings become Integers (exactly as
    # Pointer.from_fragment does) and the absolute flag of the base pointer is preserved.
    module Openapi3ParserPointerPatch
      NUMERIC_SEGMENT = /\A\d+\z/

      private

      # Same contract as the private MergePointers#merge_pointers it replaces.
      def merge_pointers(pointer_a, pointer_b)
        segments = pointer_a.segments.map { |segment| coerce_segment(segment) }
        pointer_b.segments.each do |segment|
          case segment.to_s
          when "." then next
          when ".." then segments.pop
          else segments << coerce_segment(segment)
          end
        end
        Openapi3Parser::Source::Pointer.new(segments, absolute: pointer_a.absolute)
      end

      def coerce_segment(segment)
        segment.is_a?(String) && segment.match?(NUMERIC_SEGMENT) ? segment.to_i : segment
      end
    end
  end
end

Openapi3Parser::Source::Pointer::MergePointers.prepend(ProviderIntegrator::Compat::Openapi3ParserPointerPatch)
