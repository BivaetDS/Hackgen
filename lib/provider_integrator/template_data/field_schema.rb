# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    # Rebuilds a JSON Schema (draft 2020-12) from the flattened FieldMappings of the IR so the
    # fixtures can be validated with json_schemer without the generator ever reading the OpenAPI
    # document. Fields of oneOf branches and conditionally required fields are optional here:
    # their requirement depends on the branch, which a single schema cannot express.
    module FieldSchema
      SCALAR_KEYS = { "enum" => :enum, "pattern" => :pattern, "minimum" => :minimum, "maximum" => :maximum,
                      "minLength" => :min_length, "maxLength" => :max_length }.freeze

      module_function

      # { "type" => "object", "properties" => ..., "required" => [...] } for +fields+.
      def for(fields)
        root = object_node
        fields.each { |field| place(root, field) }
        root
      end

      def object_node = { "type" => "object", "properties" => {} }

      def place(root, field)
        *parents, last = field.provider_path.split(".")
        parent = parents.reduce(root) { |node, segment| child_object(node, segment) }
        attach(parent, last.delete_suffix("[]"), node_for(field, last))
        (parent["required"] ||= []) << last.delete_suffix("[]") if required?(field)
      end

      def attach(parent, name, node)
        parent["properties"][name] = merge_existing(parent["properties"][name], node)
      end

      def node_for(field, segment)
        segment.end_with?("[]") ? { "type" => "array", "items" => leaf(field) } : leaf(field)
      end

      def required?(field) = field.required && !field.branch && !field.conditional_required

      # The object node for +segment+ under +node+ (creating it, or descending into array items).
      def child_object(node, segment)
        name = segment.delete_suffix("[]")
        entry = node["properties"][name] ||= object_node
        entry = entry["items"] ||= object_node if segment.end_with?("[]")
        entry["properties"] ||= {}
        entry
      end

      # A container may be placed before its children (keep children) or after (keep facts).
      def merge_existing(existing, node)
        return node unless existing

        existing.merge(node) { |_key, old, new| old.is_a?(Hash) && new.is_a?(Hash) ? old.merge(new) : new }
      end

      def leaf(field)
        node = {}
        node["type"] = field.nullable ? [field.type, "null"] : field.type if field.type
        SCALAR_KEYS.each do |key, member|
          value = field.public_send(member)
          node[key] = value unless value.nil?
        end
        node["properties"] = {} if field.type == "object"
        node
      end
    end
  end
end
