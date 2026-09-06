# frozen_string_literal: true

module ProviderIntegrator
  module Parser
    # Flattens a JSON Schema into the ordered list of fields the IR carries: depth first, container
    # before its children, array items under "<path>[]", oneOf/anyOf branches tagged with the
    # discriminator value they belong to (docs/IR_CONTRACT.md 1 FieldMapping, 2.6).
    class SchemaExtractor
      MAX_DEPTH = 12
      # One flattened schema field. +branch+ is nil unless the field lives in a single oneOf branch.
      Field = Struct.new(:path, :name, :schema, :required, :branch, :pointer, keyword_init: true)
      # The oneOf/anyOf variant a field belongs to.
      BranchInfo = Struct.new(:discriminator_path, :value, keyword_init: true)

      # Where the walk currently is: the pointer of the node, the provider_path prefix, the pointers
      # already on the stack (cycle guard) and the nesting depth.
      Cursor = Struct.new(:pointer, :prefix, :seen, :depth, keyword_init: true) do
        # A cursor one level down, at +pointer+ with provider_path +prefix+.
        def descend(pointer:, prefix:) = Cursor.new(pointer:, prefix:, seen: seen + [pointer], depth: depth + 1)

        # A cursor at the same depth, used when a composition keyword is unwrapped in place.
        def sibling(pointer:) = Cursor.new(pointer:, prefix:, seen: seen + [pointer], depth: depth)

        # provider_path of the property +name+ under this cursor.
        def path_for(name) = prefix.empty? ? name.to_s : "#{prefix}.#{name}"

        def revisiting?(pointer) = depth.positive? && seen.include?(pointer)
      end

      def initialize(document)
        @document = document
      end

      # Flattened fields of +schema+ (a node, possibly a $ref) addressed by +pointer+.
      def call(schema, pointer, prefix: "")
        resolved = document.deref(schema, pointer)
        return [] unless resolved.node.is_a?(Hash)

        walk(resolved.node, Cursor.new(pointer: resolved.pointer, prefix:, seen: [resolved.pointer], depth: 0))
      end

      # The component name of +schema+ when it is a $ref into components, else nil.
      def schema_name(schema, pointer) = document.deref(schema, pointer).schema_name

      # Resolves +schema+ and merges its allOf members into one node.
      def flatten(schema, pointer)
        resolved = document.deref(schema, pointer)
        return {} unless resolved.node.is_a?(Hash)

        merge_all_of(resolved.node, resolved.pointer)
      end

      # JSON Schema if/then rules ("if type is sbp, then bank_code is required") anywhere in the
      # tree, as [{path:, when:, equals:}] in document order.
      def if_then_rules(schema, pointer, prefix: "")
        resolved = document.deref(schema, pointer)
        return [] unless resolved.node.is_a?(Hash)

        conditionals(resolved.node, resolved.pointer, prefix, 0)
      end

      # The oneOf/anyOf variants of +schema+: { discriminator_path:, values:, source: } or nil.
      def variants(schema, pointer, prefix: "")
        resolved = document.deref(schema, pointer)
        return nil unless resolved.node.is_a?(Hash)

        node = merge_all_of(resolved.node, resolved.pointer)
        composition_variants(node, resolved.pointer, prefix) ||
          nested_variants(node, resolved.pointer, prefix)
      end

      private

      attr_reader :document

      def composition_variants(node, pointer, prefix)
        key = composition_key(node)
        return nil unless key

        discriminator = discriminator_path(node, prefix)
        values = node[key].each_with_index.map do |member, index|
          resolved = document.deref(member, Pointer.join(pointer, key, index.to_s))
          branch_value(node, member, resolved, index.to_s)
        end
        { discriminator_path: discriminator, values:, source: discriminator ? "discriminator" : "one_of" }
      end

      def nested_variants(node, pointer, prefix)
        cursor = Cursor.new(pointer:, prefix:, seen: [pointer], depth: 0)
        each_property(node, cursor).each do |name, resolved|
          found = variants(resolved.node, resolved.pointer, prefix: cursor.path_for(name))
          return found if found
        end
        nil
      end

      def conditionals(node, pointer, prefix, depth)
        return [] if depth > MAX_DEPTH

        own = if_then_nodes(node, pointer).flat_map { |member| rules_of(member, prefix) }
        own + nested_conditionals(merge_all_of(node, pointer), pointer, prefix, depth)
      end

      def nested_conditionals(node, pointer, prefix, depth)
        cursor = Cursor.new(pointer:, prefix:, seen: [pointer], depth:)
        each_property(node, cursor).flat_map do |name, resolved|
          next [] unless SchemaFacts.object?(resolved.node) && !cursor.revisiting?(resolved.pointer)

          conditionals(resolved.node, resolved.pointer, cursor.path_for(name), depth + 1)
        end
      end

      # The node itself plus its allOf members: several if/then rules usually live side by side there.
      def if_then_nodes(node, pointer)
        members = node["allOf"]
        return [node] unless members.is_a?(Array)

        [node] + members.each_with_index.filter_map do |member, index|
          document.deref(member, Pointer.join(pointer, "allOf", index.to_s)).node
        end
      end

      def rules_of(node, prefix)
        return [] unless node["if"].is_a?(Hash) && node["then"].is_a?(Hash)

        name, value = condition_pair(node["if"])
        required = node["then"]["required"]
        return [] if name.nil? || !required.is_a?(Array)

        prefixed(required, prefix).map { |path| { path:, when: prefixed([name], prefix).first, equals: value } }
      end

      def prefixed(names, prefix)
        names.map { |name| prefix.empty? ? name.to_s : "#{prefix}.#{name}" }
      end

      def condition_pair(condition)
        properties = condition["properties"]
        return [nil, nil] unless properties.is_a?(Hash)

        name, sub = properties.first
        value = sub.is_a?(Hash) ? SchemaFacts.constant(sub) : nil
        value.nil? ? [nil, nil] : [name, value]
      end

      def walk(schema, cursor)
        return [] if cursor.depth > MAX_DEPTH

        node = merge_all_of(schema, cursor.pointer)
        composition = composition_key(node)
        composition ? branches(node, cursor, composition) : properties(node, cursor)
      end

      def properties(node, cursor)
        required = node["required"].is_a?(Array) ? node["required"].map(&:to_s) : []
        each_property(node, cursor).flat_map do |name, resolved|
          path = cursor.path_for(name)
          field = Field.new(path:, name: name.to_s, schema: resolved.node, branch: nil,
                            required: required.include?(name.to_s), pointer: resolved.pointer)
          [field] + children(resolved, path, cursor)
        end
      end

      def each_property(node, cursor)
        properties = node["properties"].is_a?(Hash) ? node["properties"] : {}
        properties.filter_map do |name, child|
          resolved = document.deref(child, Pointer.join(cursor.pointer, "properties", name.to_s))
          [name, resolved] if resolved.node.is_a?(Hash)
        end
      end

      def children(resolved, path, cursor)
        node = resolved.node
        return [] if cursor.revisiting?(resolved.pointer)
        return array_children(node, path, cursor, resolved.pointer) if SchemaFacts.array?(node)
        return [] unless SchemaFacts.object?(node)

        walk(node, cursor.descend(pointer: resolved.pointer, prefix: path))
      end

      def array_children(node, path, cursor, pointer)
        return [] unless node["items"].is_a?(Hash)

        items = document.deref(node["items"], Pointer.join(pointer, "items"))
        return [] unless items.node.is_a?(Hash)
        # The array node itself is never the cycle; the items schema is ("children" of the same
        # component). Without this guard a self-referencing array grows exponentially until MAX_DEPTH.
        return [] if cursor.revisiting?(items.pointer)

        walk(items.node, cursor.descend(pointer: items.pointer, prefix: "#{path}[]"))
      end

      # oneOf/anyOf: a field present in exactly one branch keeps that branch, a field shared by
      # several loses it (it is unconditional) and is required only when every branch requires it.
      def branches(node, cursor, key)
        discriminator = discriminator_path(node, cursor.prefix)
        collected = node[key].each_with_index.flat_map do |member, index|
          member_fields(node, member, cursor, [key, index.to_s], discriminator)
        end
        merge_branches(collected)
      end

      def member_fields(node, member, cursor, path_segments, discriminator)
        resolved = document.deref(member, Pointer.join(cursor.pointer, *path_segments))
        return [] unless resolved.node.is_a?(Hash)

        branch = branch_for(node, member, resolved, path_segments.last, discriminator)
        walk(resolved.node, cursor.sibling(pointer: resolved.pointer))
          .map { |field| field.branch.nil? ? tagged(field, branch) : field }
      end

      def branch_for(node, member, resolved, index, discriminator)
        return nil unless discriminator

        BranchInfo.new(discriminator_path: discriminator, value: branch_value(node, member, resolved, index))
      end

      def tagged(field, branch)
        return field if branch.nil?

        Field.new(path: field.path, name: field.name, schema: field.schema, required: field.required,
                  branch:, pointer: field.pointer)
      end

      def merge_branches(fields)
        fields.group_by(&:path).map do |_, group|
          next group.first if group.one?

          first = group.first
          Field.new(path: first.path, name: first.name, schema: first.schema,
                    required: group.all?(&:required), branch: nil, pointer: first.pointer)
        end
      end

      def branch_value(node, member, resolved, index)
        mapping = node.dig("discriminator", "mapping")
        reference = member.is_a?(Hash) ? member["$ref"] : nil
        from_mapping = mapping.key(reference) if mapping.is_a?(Hash) && reference
        from_mapping || (resolved.schema_name && Inflector.snake_case(resolved.schema_name)) || index
      end

      def discriminator_path(node, prefix)
        property = node.dig("discriminator", "propertyName")
        return nil unless property.is_a?(String) && !property.empty?

        prefix.empty? ? property : "#{prefix}.#{property}"
      end

      def composition_key(node)
        %w[oneOf anyOf].find { |key| node[key].is_a?(Array) && !node[key].empty? }
      end

      # Resolves allOf into one node: properties in first-seen order, required unioned, other
      # keywords taken from the outer node first, then from each member in order.
      def merge_all_of(node, pointer)
        members = node["allOf"]
        return node unless members.is_a?(Array) && !members.empty?

        members.each_with_index.reduce(node.except("allOf")) do |merged, (member, index)|
          merge_member(merged, member, Pointer.join(pointer, "allOf", index.to_s))
        end
      end

      def merge_member(merged, member, pointer)
        resolved = document.deref(member, pointer)
        return merged unless resolved.node.is_a?(Hash)

        merge_two(merged, merge_all_of(resolved.node, resolved.pointer))
      end

      def merge_two(left, right)
        merged = right.merge(left)
        merged["properties"] = merge_properties(left["properties"], right["properties"])
        merged.delete("properties") if merged["properties"].empty?
        required = (left["required"] || []) | (right["required"] || [])
        merged["required"] = required unless required.empty?
        merged
      end

      # +outer+ is the enclosing (already merged) node: it wins on a conflict and keeps its position,
      # because the order of the properties is the order of the fields in the IR.
      def merge_properties(outer, inner)
        (outer || {}).merge(inner || {}) { |_key, from_outer, _from_inner| from_outer }
      end
    end
  end
end
