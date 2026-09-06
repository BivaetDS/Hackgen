# Provider Integrator

Детерминированный Ruby-генератор интеграций Space Payments. Он читает OpenAPI/Swagger-документ провайдера,
строит канонический IR и выпускает готовый сервис, инструкцию подключения, fixtures, исполняемый RSpec,
локальный контрактный harness и отчёт о допущениях. В рантайме нет LLM и обращений к внешним API.

## Быстрый запуск

После клонирования достаточно трёх команд (Ruby 3.3+ и Bundler):

```bash
bundle install
bundle exec rake check
bundle exec ruby bin/integrate --spec docs/provider_api.yaml --provider novapay --run-spec
```

Результат появится в `output/novapay/`. Повторный прогон с теми же входами даёт идентичные байты.

## Как устроен конвейер

```text
OpenAPI YAML/JSON
  -> безопасная загрузка и разрешение локальных $ref
  -> нормализация: операции, auth, поля, статусы, ошибки, webhook
  -> ProviderSpec IR
  -> генераторы Ruby / Markdown / JSON / RSpec
  -> синтаксис + RuboCop + JSON Schema + контрактные проверки
  -> output/<provider>/
```

Знания предметной области находятся в `lib/provider_integrator/dictionaries/*.yml`, а не в ветках под
конкретного провайдера. Неоднозначности получают стабильный код `W…`, попадают в CLI,
`generation_report.json` и раздел «Требует подтверждения» в `INTEGRATION.md`.

## CLI

```bash
bundle exec ruby bin/integrate \
  --spec provider.yaml \
  --provider acmepay \
  --output ./output \
  --overrides examples/overrides.example.yml \
  --lang ruby \
  --run-spec \
  --verbose
```

Флаги:

| Флаг | Назначение |
|---|---|
| `--spec PATH` | обязательный OpenAPI YAML/JSON |
| `--provider SLUG` | имя класса и каталога; по умолчанию выводится из `info.title` |
| `--output DIR` | корень результата, по умолчанию `./output` |
| `--overrides PATH` | проверяемые ручные уточнения для того, чего нет в спецификации |
| `--analyze-only` | вывести канонический IR в stdout, ничего не генерировать |
| `--strict` | считать наличие warnings ошибкой с exit code 4 |
| `--run-spec` | после записи выполнить сгенерированный RSpec без сетевого доступа |
| `--verbose` | показать info-события, locations и диагностический backtrace |
| `--lang ruby` | целевой язык; сейчас поддерживается только Ruby |
| `--version`, `-v` | версия программы |

Exit codes: `0` успех, `1` внутренняя ошибка, `2` неверные аргументы, `3` непригодная спецификация,
`4` warnings в strict-режиме, `5` невалидный результат или упавший сгенерированный RSpec,
`6` ошибка записи. При `--analyze-only` stdout содержит только JSON, диагностика идёт в stderr.

## Overrides

Формат зафиксирован JSON Schema `lib/provider_integrator/schemas/overrides.schema.json`. Полный
комментированный образец — `examples/overrides.example.yml`:

```bash
bundle exec ruby bin/integrate --spec provider.yaml --overrides examples/overrides.example.yml
```

Допустимые секции: `operations`, `amount_unit`, `required_if`, `signature`, `status_map`,
`error_actions`. Каждое реально применённое значение записывается в IR как `overrides_applied` и событие I601.

## Поддержка OpenAPI

Поддерживаются OpenAPI 3.0/3.1 и Swagger 2.0 (конвертируется с W103), локальные `$ref`, JSON и
form-urlencoded request bodies, `oneOf`/`anyOf`/discriminator, callbacks, path/query/header параметры,
ApiKey, Bearer, Basic и OAuth2 client credentials, строковые и числовые статусы, examples и response headers.

Осознанные ограничения:

- внешние файловые и URL `$ref` не загружаются — E008;
- неизвестная версия — E002, отсутствующие `paths` — E003, битый `$ref` — E005, цикл — E006;
- неизвестная auth-схема сохраняется как требующая настройки — W501;
- невыводимые статусы, поля, единицы и подпись не угадываются молча — W201/W401/W403/W301;
- отсутствие status/webhook отражается в сгенерированном контрактном методе — W106/W304;
- спецификация ограничена 5 МБ и глубиной 100 уровней — E007.

Полный реестр событий находится в `lib/provider_integrator/events.rb`, контракт IR — в
`docs/IR_CONTRACT.md`, текущие допущения — в `docs/ASSUMPTIONS.md`.

## Как расширить правила

1. Выберите словарь: `operations.yml`, `fields.yml`, `statuses.yml`, `errors.yml` или
   `canonical_contract.yml`.
2. Добавьте общее правило или синоним без названия конкретного провайдера.
3. Выполните `bundle exec rake check`: JSON Schema проверит форму словаря, RSpec — поведение.
4. Если меняется ожидаемая генерация, обновите golden через
   `bundle exec rake "golden:update[имя_спеки]"` и просмотрите diff.

Новый вид неоднозначности требует записи в `ProviderIntegrator::Events::ROWS`, синхронной строки в
`docs/PLAN.md §3.3` и контрактного теста реестра.

## Как добавить спецификацию в регрессию

1. Положите её в `spec/fixtures/specs/<name>.yaml`.
2. Создайте каталог `spec/golden/<name>` и добавьте ожидаемые особенности в unit/contract specs.
3. Выполните `bundle exec rake "golden:update[<name>]"` (после первого обновления каталог поддерживается автоматически).
4. Запустите `bundle exec rake check`; интеграционный тест выполнит сгенерированный RSpec в отдельном процессе.

## Docker

```bash
docker build -t provider-integrator .
mkdir -p specs output && cp docs/provider_api.yaml specs/provider.yaml
docker compose run --rm integrator --spec /workspace/specs/provider.yaml --provider novapay --output /workspace/output --run-spec
```

Контейнер работает не от root. `compose.yaml` монтирует `./specs` только для чтения и `./output` для результата.

## Troubleshooting

- `Your Ruby version …` — установите Ruby 3.3+ и снова выполните `bundle install`.
- `E001` — проверьте YAML/JSON и путь; алиасы YAML запрещены намеренно.
- `E005`/`E006`/`E008` — сделайте `$ref` локальным, существующим и ацикличным.
- Exit 4 — повторите без `--strict` и разберите warnings в `generation_report.json`.
- Exit 5 с `--run-spec` — файлы сохранены; запустите RSpec из каталога результата для подробностей.
- Не используйте системный Ruby 2.6 на macOS; выберите Ruby 3.3+ через rbenv/asdf.

## Лицензии и безопасность

Все зависимости перечислены в `Gemfile` с лицензиями. Спецификация считается недоверенным вводом:
используются `Psych.safe_load`, лимиты размера/глубины, whitelist slug и запуск RSpec argv-массивом без shell.
Сетевые обращения сгенерированных тестов запрещены WebMock.
