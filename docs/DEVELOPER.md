# DEVELOPER.md — краткий гайд для senior Ruby

Пользовательская документация — `README.md`. Здесь — то, что нужно, чтобы менять код, не ломая инварианты.

## Что это

Детерминированный генератор: OpenAPI/Swagger провайдера → Ruby-сервис под контракт `Provider::BaseService`
+ `INTEGRATION.md` + `fixtures.json` + исполняемый RSpec + `base_contract.rb` + `generation_report.json`.
Без LLM, без сети в рантайме. Ruby ≥ 3.3, чистый Ruby (Thor, Zeitwerk, ERB), без Rails.

```bash
bundle install && bundle exec rake check          # RSpec + RuboCop + схемы словарей
bundle exec ruby bin/integrate --spec docs/provider_api.yaml --provider novapay --run-spec
```

## Конвейер (`lib/provider_integrator/`)

```
CLI (Thor)  →  Pipeline  →  Parser.call  →  ProviderSpec (IR, JSON-сериализуемый)
                          →  Generator.call → GeneratedFile[]  →  OutputValidator
                          →  Files.write   →  SpecRunner (--run-spec, отдельный процесс, без shell)
```

| Слой | Каталог | Обязанность |
|---|---|---|
| Чтение спеки | `parser/` | `Loader` (Psych.safe_load, лимиты 5 МБ / глубина 100), `RefResolver` (только локальные `$ref`), `Swagger2Converter`, `Validator` (openapi3_parser как кросс-проверка), `SchemaExtractor`, `ExampleComposer` |
| Семантика | `normalizer/` | По одному классу на решение: `OperationClassifier` (взвешенный скоринг), `FieldMapper`, `MoneyUnits`, `StatusMapper`, `ErrorClassifier`, `SignatureAnalyzer`, `WebhookAnalyzer`, `ConditionalRequired`, `Overrides`. Собирает `Models::ProviderSpec` через `SpecBuilder` |
| IR | `models/` | `Data`/`Struct`-модели, контракт зафиксирован в `docs/IR_CONTRACT.md`. **Менять — только после согласования: контракт общий на трёх разработчиков** |
| Данные для шаблонов | `template_data/` | Presentation-модели (`CreateMethod`, `CallbackMethod`, `Canon`, `Fixtures`, `Documentation*`). Вся логика здесь, не в ERB |
| Генерация | `generator/` + `templates/*.erb` | `ServiceGenerator`, `RspecGenerator`, `FixturesGenerator`, `DocumentationGenerator`, `BaseContractGenerator`, `ReportGenerator`; `RubyFormatter` гоняет RuboCop через API со `stdin:`; `OutputValidator` — Prism + RuboCop + JSON Schema + контрактные проверки |
| Знания | `dictionaries/*.yml` | `operations`, `fields`, `statuses`, `errors`, `canonical_contract`. Единственное место доменного знания; валидируются JSON Schema (`schemas/`) |
| Диагностика | `events.rb`, `event_log.rb`, `reporter/` | Реестр `E…/W…/I…` в `Events::ROWS`; всё неоднозначное → событие + `TODO(confidence …)` в коде + «Требует подтверждения» в INTEGRATION.md |

Границы модулей возвращают `Models::Result`/`ParseResult`/`GenerationResult`/`PipelineResult`, не бросают.
Исключения только `SpecError`/`GenerationError`, ловятся в `Pipeline`. Exit codes: `0` ok, `1` internal,
`2` args, `3` spec, `4` warnings при `--strict`, `5` невалидный вывод или красный сгенерированный RSpec, `6` write.

## Инварианты, которые проверяются тестами

- **Детерминизм**: два прогона → одинаковые SHA-256. Запрещены `Time.now`, `rand`, `SecureRandom`,
  `Hash#inspect`, `object_id` в чём-либо, влияющем на вывод. Ключи сортируются (`JsonCanon`), порядок — по спеке.
- **Анти-хардкод**: `grep -ri novapay lib/` пуст. Провайдер-специфика живёт только в спеке и словарях.
- **Канон Space Payments** — только `dictionaries/canonical_contract.yml`; `STATUS_MAP`/`ERROR_MAP`/хелперы
  в шаблонах не хардкодятся.
- **Недоверенный ввод**: имена из спеки проходят `Inflector` (зарезервированные слова, спецсимволы),
  никакого `eval`/`send` с пользовательскими строками, backtrace только под `--verbose`.
- **Внешний вид сервиса** повторяет эталон `docs/TZ.md`; сравнение — `docs/GENERATOR_VS_REFERENCE.md`.

## Тесты

```
spec/unit/…            анализаторы: позитив, негатив, неоднозначность
spec/golden/<name>/    байт-в-байт эталоны для каждой спеки из spec/fixtures/specs/
spec/integration/      generated_specs_spec.rb — сгенерированный RSpec зелёный против base_contract.rb
                       invalid_specs_spec.rb  — E-коды на битых спеках
spec/spec_runner_spec.rb, template_data/…
```

Golden обновляются только `bundle exec rake "golden:update[name]"` с осмысленным диффом в коммите.
Сгенерированный код не запускается без WebMock. Реальной сети в тестах нет.

## Как добавить

- **Правило/синоним** → соответствующий `dictionaries/*.yml`, без имени провайдера → `rake check` → при смене
  вывода `golden:update` + просмотр диффа.
- **Новую неоднозначность** → строка в `Events::ROWS` + `docs/PLAN.md §3.3` + контрактный тест реестра.
- **Регрессионную спеку** → `spec/fixtures/specs/<name>.yaml` → `spec/golden/<name>/` → `golden:update[<name>]`.
- **Поле IR** → сначала `docs/IR_CONTRACT.md` и согласование, потом `models/` + `SpecBuilder` + `to_h`.

## Рабочий процесс

- Волны по `docs/PLAN.md §10` (текущая — `docs/PLAN_WAVE3.md`). Волна закрыта, когда зелёный
  `bundle exec rspec && bundle exec rubocop` и выполнен её критерий.
- Приоритет источников при расхождении: `docs/TZ.md` → ответы экспертов `docs/PLAN.md §4` → план.
- Коммит на задачу: `wave3(generator): …`. Идеи вне волны — `docs/BACKLOG.md`. Допущения — `docs/ASSUMPTIONS.md`.
- Все файлы LF. На Windows после `rubocop -A` — `rake lf`. На macOS — Ruby через rbenv, не системный 2.6.
- Стиль: `frozen_string_literal`, маленькие классы с одной обязанностью, docstring на публичных методах,
  в ERB только `<%= %>`, `<% each %>`, `<% if %>`. Skill `ruby-cli-conventions` описывает фактический код и
  обновляется в конце каждой волны.

## Docker

```bash
docker build -t provider-integrator .
docker compose run --rm integrator --spec /workspace/specs/provider.yaml --provider novapay --output /workspace/output --run-spec
```

Контейнер не root, `./specs` монтируется read-only, `./output` — для результата.
