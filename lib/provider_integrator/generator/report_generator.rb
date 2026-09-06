# frozen_string_literal: true

module ProviderIntegrator
  module Generator
    # Renders generation_report.json: what was recognised and how surely, every event of the
    # analysis and the generation, the applied overrides, the TODO markers left in the code, the
    # validation summary and the SHA-256 of every other file. Canonical JSON (sorted keys).
    class ReportGenerator
      FILE_NAME = "generation_report.json"
      TODO_LINE = /^\s*#\s*(#{Regexp.escape(Confidence::MARKER)}[^\n]*)$/

      def initialize(context, files:, validation:, events:)
        @context = context
        @spec = context.spec
        @files = files
        @validation = validation
        @events = events
      end

      def call
        content = JsonCanon.generate(report)
        Models::GeneratedFile.build(kind: :report, name: FILE_NAME, path: @context.path_for(FILE_NAME), content:)
      end

      private

      attr_reader :context, :spec, :files, :validation, :events

      def report
        header.merge("events" => { "analysis" => spec.events.map(&:to_h), "generation" => events.map(&:to_h) },
                     "requires_confirmation" => TemplateData::Confirmations.new(spec).to_a,
                     "inferences" => inferences, "overrides_applied" => spec.overrides_applied.map(&:to_h),
                     "todos" => todos)
      end

      def header
        { "generator" => { "name" => "provider-integrator", "version" => VERSION, "ir_version" => spec.ir_version },
          "provider" => provider, "files" => files.map(&:manifest), "validation" => validation }
      end

      def provider
        { "title" => spec.provider.title, "version" => spec.provider.version, "slug" => spec.provider.slug,
          "class_name" => "#{TemplateData::Canon.new.namespace}::#{context.class_name}",
          "service_file" => context.service_file_name }
      end

      # The critical inferences with their confidence and evidence, one entry per subject.
      def inferences
        { "operations" => spec.operations.map { |operation| operation_summary(operation) },
          "authentication" => pick(spec.authentication, %w[type scheme_name location name confidence evidence]),
          "amount_units" => amount_units, "conditional_requirements" => conditional_requirements,
          "statuses" => spec.statuses.map(&:to_h), "webhook" => webhook_summary,
          "gateway_config" => spec.gateway_config&.to_h }
      end

      def operation_summary(operation)
        pick(operation, %w[operation_id method path kind in_contract canonical_method confidence])
          .merge("evidence" => operation.classification.evidence)
      end

      def amount_units
        field_entries(:conversion)
      end

      def conditional_requirements
        field_entries(:conditional_required)
      end

      # One entry per request field carrying +member+ (a Conversion or ConditionalRequired).
      def field_entries(member)
        spec.operations.flat_map do |operation|
          operation.request_fields.select(&member).map do |field|
            { "operation_id" => operation.operation_id, "field" => field.provider_path }
              .merge(field.public_send(member).to_h)
          end
        end
      end

      def webhook_summary
        webhook = spec.webhook
        return nil unless webhook

        pick(webhook, %w[path method source confidence event_field status_field id_field])
          .merge("signature" => webhook.signature&.to_h, "events" => webhook.events.map(&:to_h))
      end

      # TODO(confidence ...) markers left in the generated Ruby, with file and line.
      def todos
        files.select { |file| file.name.end_with?(".rb") }.flat_map do |file|
          file.content.each_line.with_index(1).filter_map do |line, number|
            match = TODO_LINE.match(line) or next
            { "file" => file.name, "line" => number, "text" => match[1] }
          end
        end
      end

      def pick(model, keys) = model.to_h.slice(*keys)
    end
  end
end
