# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Turns the flattened request fields of an operation into the lines of a Ruby Hash literal
    # for one payout method (branch): fields of other branches and requisites that are only
    # required for another payout method are left out, containers become nested hashes, and
    # every hash ends with `.compact` so optional values without a source disappear.
    class PayloadBuilder
      Result = Data.define(:lines, :env_constants, :helpers, :notes, :docs)

      # +docs+ rows: [provider path, source description, requirement, note] for INTEGRATION.md.
      def initialize(operation, canon:, context:, scope: Scope.build)
        @operation = operation
        @branch = scope.branch
        @source = FieldSource.new(operation, canon:, context:, scope:)
        @env_constants = []
        @helpers = []
        @notes = []
        @docs = []
      end

      def call
        lines = Code.hash_lines(entries(tree), close: "}.compact")
        Result.new(lines:, env_constants: @env_constants.uniq, helpers: @helpers.uniq(&:name), notes: @notes,
                   docs: @docs)
      end

      private

      attr_reader :operation, :branch

      # Fields of this branch, in spec order.
      def fields
        operation.request_fields.select { |field| in_branch?(field) }
      end

      def in_branch?(field)
        return true unless branch
        return field.branch.value == branch if field.branch

        condition = field.conditional_required
        return true unless condition && condition.when == operation.request_methods&.discriminator_path

        condition.equals == branch
      end

      # Nested Hash: segment => FieldMapping (leaf) or Hash (container), preserving field order.
      def tree
        fields.each_with_object({}) do |field, root|
          next array_note(field) if field.provider_path.include?("[]")

          *parents, name = field.provider_path.split(".")
          node = parents.reduce(root) { |acc, segment| subtree(acc, segment) }
          node[name] = container?(field) ? subtree(node, name) : field
        end
      end

      # The Hash under +segment+ of +node+, created when absent (or when a leaf sat there).
      def subtree(node, segment)
        node[segment] = {} unless node[segment].is_a?(Hash)
        node[segment]
      end

      # Containers: declared objects and the oneOf parents that carry no type of their own.
      def container?(field)
        field.type == "object" || (field.type.nil? && field.canonical.to_s.match?(/\A(requisite|error|customer)\z/))
      end

      def array_note(field)
        @notes << Generator::Confidence.todo(0.0,
                                             "array field #{field.provider_path} is not mapped (no platform source)")
        @docs << [field.provider_path, "TODO: массив, не сопоставлен", requirement(field), nil]
      end

      def entries(node)
        node.filter_map do |name, value|
          value.is_a?(Hash) ? container_entry(name, value) : leaf_entry(name, value)
        end
      end

      def container_entry(name, children)
        nested = entries(children)
        return nil if nested.empty?

        Code::Entry[Code.hash_lines(nested, open: "#{Code.key(name)} {", close: "}.compact").join("\n")]
      end

      def leaf_entry(name, field)
        source = @source.for(field)
        @docs << [field.provider_path, source.doc, requirement(field), note_for(field)]
        return nil if source.omitted?

        register(source)
        Code::Entry["#{Code.key(name)} #{source.expression}", source.comments]
      end

      def register(source)
        @env_constants << source.env_constant if source.env_constant
        @helpers << source.helper if source.helper
      end

      def requirement(field)
        condition = field.conditional_required
        return "при #{condition.when} = #{condition.equals}" if condition
        return "ветка #{field.branch.value}" if field.branch

        field.required ? "да" : "нет"
      end

      def note_for(field)
        parts = []
        parts << "enum: #{field.enum.join(", ")}" if field.enum && field.enum.size > 1
        parts << "pattern #{Markdown.code(field.pattern)}" if field.pattern
        parts << field.description if field.description
        parts.empty? ? nil : parts.join("; ")
      end
    end
  end
end
