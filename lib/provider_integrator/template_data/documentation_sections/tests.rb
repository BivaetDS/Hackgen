# frozen_string_literal: true

module ProviderIntegrator
  module TemplateData
    module DocumentationSections
      # "Тесты": what the generated RSpec covers per contract method, how to run it, and that the
      # contract stub and its HTTP client stand in for the platform during that run.
      class Tests
        def initialize(doc)
          @doc = doc
          @context = doc.context
          @canon = doc.canon
        end

        def sections
          [doc.section("Тесты", lines)]
        end

        private

        attr_reader :doc, :context, :canon

        def spec_data = context.spec_data

        def lines
          ["`#{context.spec_file_name}` - RSpec поверх `#{Generator::FixturesGenerator::FILE_NAME}` через WebMock " \
           "(сеть не нужна), #{spec_data.example_count} примеров:", "", *coverage_lines, "", *run_lines]
        end

        def coverage_lines
          spec_data.coverage.map { |method, summary, count| "- `#{method}` (#{count}): #{summary}" }
        end

        def run_lines
          ["- Запуск из каталога с файлами: `rspec #{context.spec_file_name}` (гемы `rspec`, `webmock`); " \
           "то же делает `bin/integrate --run-spec` сразу после генерации",
           "- `#{Generator::BaseContractGenerator::FILE_NAME}` (`#{canon.base_service_class}`, " \
           "`#{canon.namespace}::#{BaseContract::HTTP_CLIENT}` на Net::HTTP) - заглушки для автономного прогона " \
           "(docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие " \
           "`#{canon.base_service}` и `client`",
           signature_line].compact
        end

        def signature_line
          verifier = spec_data.verifier
          return nil unless verifier && !verifier.asymmetric?

          "- Подпись webhook в тестах считается тем же выражением, что в `verify_signature!` " \
            "(#{verifier.algorithm.upcase}, #{verifier.encoding}); секрет - " \
            "`#{canon.credential(canon.callback_secret_key)}`"
        end
      end
    end
  end
end
