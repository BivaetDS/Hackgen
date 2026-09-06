# Волна 2 — доказательства: генерируемый RSpec, golden на все спеки, invalid_*, детерминизм

## Статус

Выполнено 2026-09-06. `bundle exec rake check`: 769 примеров, 0 падений; 217 файлов RuboCop,
0 замечаний; пять словарей валидны. Все шесть сгенерированных RSpec проходят в отдельных подпроцессах,
живой `--run-spec` для NovaPay даёт 20 примеров / 0 падений и byte-for-byte совпадает с golden.
Четыре `invalid_*` возвращают E001/E003/E005/E101 и exit 3 без файлов. Ядро заморожено: дальше только
багфиксы; новые возможности — в следующих волнах.

## Context

Волна 1 закрыта: `bin/integrate` за один прогон пишет пять файлов, golden есть только для NovaPay. Волна 2
(PLAN §10, PROMPT «Промпт 3») должна доказать универсальность и надёжность: сгенерированный сервис
проверяет себя сам через сгенерированный RSpec с WebMock, вывод генератора заморожен golden-каталогами,
битые спеки дают понятную ошибку, критичные выводы видны в отчёте и в INTEGRATION.md. После волны — заморозка
ядра (парсер/генератор только багфикс).

Что уже есть и не делается заново: спеки S1–S5 (`spec/fixtures/specs/*.yaml`), четыре `invalid_*.yaml`,
анти-хардкод тест, `Confirmations` (критичные выводы в отчёте и в «Требует подтверждения»), прогон S1–S5 через
генератор в `spec/generator/generator_spec.rb`.

Решения пользователя: golden для всех шести спек; флаг `--run-spec` делаем в этой волне.

Ключевой факт из разведки: `client` в `base_contract.rb` абстрактный, HTTP-реализации нет. Чтобы сгенерированный
RSpec работал через WebMock (а не через фейковый клиент), в заглушку контракта добавляется `Provider::HttpClient`
на `Net::HTTP` (допущение: платформа инжектирует свой клиент, заглушка нужна для автономного прогона).

## Шаг 1. `Provider::HttpClient` в base_contract.rb

- `templates/base_contract.rb.erb`: `require 'json'`, `'net/http'`, `'uri'`; класс `HttpClient` с
  `get(url, headers: {})`, `post(url, json: nil, form: nil, headers: {})` → `Response(status:, body: JSON или сырая
  строка или nil, headers: response.each_header.to_h)`; json → `Content-Type: application/json`, form →
  `set_form_data`. Имена методов и `Response` берутся из `TemplateData::BaseContract` (`client_methods`,
  `response_members`), новых литералов канона в шаблоне нет.
- `docs/ASSUMPTIONS.md`: допущение 23 (заглушка клиента), `Review#client_assumption` не меняется.
- Спека: `spec/generator/generator_spec.rb` — заглушка парсится Prism (уже есть), плюс в шаге 3 клиент
  проверяется реальным прогоном через WebMock.

## Шаг 2. RspecGenerator: `<slug>_service_spec.rb`

Новые файлы:
- `lib/provider_integrator/generator/rspec_generator.rb` — как `ServiceGenerator`: `TemplateData::ServiceSpec` →
  `Template.render("service_spec.rb.erb")` → `RubyFormatter.format` → `GeneratedFile(kind: :service_spec)`.
  Добавить в `Generator.generate` после `FixturesGenerator`; `Context#spec_file_name` = `"#{identifier}_service_spec.rb"`.
- `lib/provider_integrator/templates/service_spec.rb.erb` — только раскладка: шапка, `require`, `RSpec.describe`,
  `let`-блоки, `describe` на метод с готовыми примерами (`data.groups` → `ExampleData(description, lines)`).
- `lib/provider_integrator/template_data/service_spec.rb` — собирает данные из IR **и того же хеша фикстур**
  (`TemplateData::Fixtures.new(context).to_h`), которым пишется fixtures.json: сгенерированный спек читает
  `fixtures.json` рядом с собой по ключам (`create_request.response_201`, `callback.payload` …), а ожидаемые
  значения генератор вычисляет из того же хеша, так что они согласованы по построению.
  Части (по одному классу, ≤ 200 строк каждый):
  - `template_data/spec_subject.rb` — `credentials` (ключи из `canon.credential_keys(auth.type)` + `callback_secret`
    при подписи + `merchant_id` при `merchant_account`; значения `test-<key>`), литерал `Provider::Operation`
    из фикстуры запроса: `id` = значение по пути поля `external_id`, `amount` = обратная конверсия
    (`AmountHelper#reverse`/`#apply` — новые методы рядом с `lines`, чтобы прямая и обратная арифметика жили в одном
    месте), `currency`, `provider_operation_id` = id из `response_201` (`service.provider_id_path`),
    `payout_requisite` = `{ default_branch => { child => значение из фикстуры } }` для реквизитов ветки
    (используется общий предикат ветки — вынести `PayloadBuilder#in_branch?` в `PayloadBuilder.in_branch?(field, branch, operation)`).
  - `template_data/spec_request.rb` — ожидания запроса create: URL (`Url#expression` c подстановкой
    `described_class::BASE_URL`), verb, заголовки авторизации по типу схемы (header api_key, cookie, bearer
    `Bearer test-token`, basic, oauth2 → `before { stub_request(:post, TOKEN_URL) … access_token: 'test-access-token' }`),
    query api_key → `with(query: { name => value })`, идемпотентный заголовок, и список `[путь, значение]` для тела:
    поля ветки по умолчанию, чей `FieldSource` не omitted и не `nil`/ENV; тело читается как JSON или
    `URI.decode_www_form` (form-провайдеры, значения `to_s`). Проверка блоком `a_request(...).with { |req| … dig … }`,
    без точного равенства всего тела.
  - `template_data/spec_examples.rb` — примеры по методам:
    - `create_request`: успех на первом success-коде (`success?`, `provider_operation_id`, `status` =
      `STATUS_MAP` значения из фикстуры); дубль по `idempotent_duplicate_codes` как успех; по одному примеру на
      каждый `response_<код>` ошибки: `[error, code]` из `Canon#failure_parts(canonical)` (новый метод: символ и
      i18n отдельно), `details[:provider_code]` если есть путь кода, `retry_after` = 60 при `retry_after: header`
      (стаб с заголовком `Retry-After: 60`) или значение поля фикстуры при `body`; `unsupported_request_method`
      без обращения к провайдеру.
    - `fetch_status`: GET с id, статус из `response_200` через STATUS_MAP; 404 → `provider.not_found` при наличии;
      заглушка (W106) → `raise_error(NotImplementedError)`.
    - `process_callback`: по одному примеру на каждую запись фикстур `callback*` с `expected_operation_status`
      (approved/rejected(+`error_code`)/in_progress/unknown_event), подписанный конверт
      `{ 'body', 'raw_body', 'headers' }` или подпись в теле; подпись считается тем же выражением, что и
      `verify_signature!` — вынести из `SignatureVerifier` публичные `digest_expression(secret:, message:)`,
      `message_expression(body:)`, `location/name` (один источник истины); подделанная подпись →
      `invalid_signature`; асимметричная подпись → `raise_error(NotImplementedError)`; без вебхука (W304) →
      `raise_error(NotImplementedError)`.
    - `check_conditions`: валидная операция → success; `amount_too_low` при `MIN_AMOUNT`, `amount_too_high` при
      `MAX_AMOUNT`, `missing_requisite` при `REQUIRED_REQUISITES`, `unsupported_request_method` при `REQUEST_METHODS`.
    - Методы вне контракта в спек не входят (BACKLOG).
- Правка ядра, найденная при разведке: `ConditionsMethod.requisite_fields` включает поле-дискриминатор
  (`REQUIRED_REQUISITES['card']` у rublepay содержит `source_type`, хотя в payload это константа ветки) — исключить
  поле с `provider_path == request_methods.discriminator_path`, как в `FieldSource#discriminator?`.
- `OutputValidator`: для `:service_spec` те же проверки, что для `base_contract` (syntax, leftovers, rubocop);
  `ValidationLine` учтёт файл автоматически (по kind проверок).
- `Reporter#generating`: строка `Generating service spec...`; `OUTPUT_ORDER` + `service_spec` после fixtures.
- INTEGRATION.md: новая секция «Тесты» (`DocumentationSections::Tests`): что покрывает спек, как запустить
  (`rspec <slug>_service_spec.rb`, нужны гемы rspec и webmock), что `base_contract.rb` и `HttpClient` — заглушки.
  `REQUIRED_SECTIONS` не расширяется.
- `templates/rubocop_generated.yml`: если RuboCop ругается на RSpec-DSL (блоки, `describe` с константой) —
  точечно отключить cop с комментарием-обоснованием, без плагина rubocop-rspec.
- Спеки: `spec/generator/rspec_generator_spec.rb` — форма файла для NovaPay точными строками (require, describe,
  стаб 201 c заголовками, подпись, 409, 429 с Retry-After), варианты IR через `Data#with` (без вебхука, подпись в
  теле, query api_key, form-тело). `spec/template_data/spec_subject_spec.rb` — литерал операции и обратная
  конверсия для multiply / to_decimal_string / identity.

## Шаг 3. Сгенерированные спеки зелёные в подпроцессе

- `spec/integration/generated_specs_spec.rb`: для каждой из шести спек фикстур — записать файлы в `Dir.mktmpdir`,
  `Open3.capture3(RbConfig.ruby, Gem.bin_path("rspec-core", "rspec"), spec_file, "--format", "progress", chdir:)`,
  ожидать exit 0 и `0 failures`, при провале печатать stdout. Один подпроцесс на спеку (~1 с каждый).
- Критерий промпта — NovaPay, S1, S2; цель — все шесть. Если S3–S5 требуют правок генератора за рамками волны,
  это фиксируется в отчёте как найденная проблема с причиной, а не `pending` без объяснения.

## Шаг 4. Golden на все шесть спек и детерминизм

- `bundle exec rake "golden:update[novapay,bearerpay,rublepay,numstatus,cardpay,legacy_swagger2]"`; коммит с
  объяснением диффа NovaPay (новый `novapay_service_spec.rb`, `HttpClient` в заглушке, секция «Тесты», манифест
  отчёта). `spec/golden_spec.rb` уже перебирает каталоги — код не меняется; убрать текст «the rest join in wave 2».
- `spec/contract/determinism_spec.rb`: для каждой спеки `Parser.call!` дважды → одинаковый канонический JSON;
  генерация дважды → одинаковые SHA всех файлов; для NovaPay второй прогон с `RubyFormatter.cache.clear`
  (холодный RuboCop), для остальных кросс-процессное доказательство даёт golden, записанный в другом процессе.

## Шаг 5. invalid_* и критичные выводы — контрактные тесты

- `spec/integration/invalid_specs_spec.rb`: таблица `{invalid_broken_yaml: E001, invalid_no_paths: E003,
  invalid_bad_ref: E005, invalid_no_create: E101}` → CLI in-process: exit 3, stderr =
  `The spec cannot be used:\n  E… …`, без кадров `.rb:\d+`, stdout пуст, `--output` каталог пуст.
- `spec/contract/confirmations_spec.rb`: для шести спек коды `generation_report.json → requires_confirmation`
  == коды таблицы «Требует подтверждения» в INTEGRATION.md == warnings IR + критичные infos (I201 при статусах,
  I301 при подписи, I401 при денежном поле, I403 при gateway config).

## Шаг 6. `--run-spec`

- `Pipeline`: опция `run_spec:`; после записи — `SpecRunner.call(spec_path:, chdir: output_dir)`
  (`lib/provider_integrator/spec_runner.rb`: `Open3.capture2e(RbConfig.ruby, rspec_bin, file)`, `rspec_bin` через
  `Gem.bin_path("rspec-core", "rspec")` с `rescue Gem::Exception` → понятная причина). Результат
  `Models::SpecRun(examples:, failures:, output:, ok?)`; observer `spec_ran(run)`; статус `:spec_failed` при провале
  или недоступном rspec → exit 5 (файлы остаются, об этом печатается).
- CLI: флаг `--run-spec`; Reporter: `Running generated spec... RSpec 14 examples, 0 failures`, при провале — вывод
  rspec в stderr. Спеки: `spec/pipeline_spec.rb` (стаб `SpecRunner`), `spec/cli_spec.rb` (флаг → строка, exit 5 при
  провале), один настоящий прогон — в `spec/integration/cli_integration_spec.rb` (`--run-spec` для NovaPay).

## Шаг 7. Документы и заморозка ядра

- `docs/CHECKPOINT.md`: команда `rspec output/novapay/novapay_service_spec.rb` (или `--run-spec`), таблица
  универсальности «спека → операции → auth → статусы → warnings» по шести спекам (собрать из `--analyze-only`),
  раздел «Состояние»: волна 2 готово, ядро заморожено.
- `docs/ASSUMPTIONS.md` (23), `docs/GENERATOR_VS_REFERENCE.md` (файл спека в «Дополнительные файлы»),
  `docs/BACKLOG.md` (extras в генерируемом спеке, мок-сервер — волна 4, подпись в fixtures.json закрыть или уточнить).
- `.claude/skills/ruby-cli-conventions/SKILL.md`: как устроен генератор спеков (данные из того же хеша фикстур,
  подпись из одного источника, `HttpClient` в заглушке), паттерн «golden на все спеки», `SpecRunner`;
  `CLAUDE.md` — только если устарели факты.

## Порядок и коммиты (стиль `wave2(generator): …`, `wave2(cli): …`, `docs: …`)

1. `HttpClient` в заглушке + допущение 23.
2. Рефакторинг точек переиспользования без изменения вывода: `Canon#failure_parts`, `SignatureVerifier` публичные
   выражения, `PayloadBuilder.in_branch?`, `AmountHelper#apply/#reverse`, фикс дискриминатора в `ConditionsMethod`
   (меняет вывод rublepay; golden его ещё нет).
3. `TemplateData::ServiceSpec` + части, шаблон, `RspecGenerator`, валидатор, Reporter, секция «Тесты»; юнит-спеки.
4. Интеграционный прогон сгенерированных спеков (шесть спек), правки генератора по результатам.
5. Golden на шесть спек, детерминизм, invalid_*, confirmations.
6. `--run-spec`.
7. Документы, skill, `bundle exec rake check`, таблица универсальности в ответе.

## Verification

- `bundle exec rake check` зелёный (ожидаемо ~780+ примеров).
- `ruby bin/integrate --spec docs/provider_api.yaml --provider novapay --run-spec` → шесть файлов в
  `output/novapay/`, строка `RSpec N examples, 0 failures`, exit 0; `diff -r output/novapay spec/golden/novapay` пуст.
- `cd output/novapay && rspec novapay_service_spec.rb` зелёный вручную; то же для `bearerpay` и `rublepay`.
- `for s in spec/fixtures/specs/invalid_*.yaml; do ruby bin/integrate --spec $s; echo $?; done` → по одной
  E-строке в stderr, exit 3, без стек-трейсов.
- `grep -ri novapay lib/` пуст; `bundle exec rake "golden:update"` без аргументов не меняет ни одного файла.
