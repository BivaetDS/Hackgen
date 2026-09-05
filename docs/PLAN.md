# Генератор интеграций Space Payments — объединённый план (редакция «без ограничения по времени»)

Источники: командный `PLAN.md` (структура, контракты, роли, коды событий, валидатор) + исследовательский отчёт (стек, алгоритмы, канонический контракт, матрица баллов, синтетические спеки).

Принцип этой редакции: план не привязан к датам. Работа упорядочена по ценности для результата и по зависимостям — волнами. Каждая волна завершается проверяемым критерием; следующая начинается только после него. Так проект в любой момент находится в состоянии «показать можно», а объём растёт монотонно.

---

## 1. Цель, ограничения, принципы

```
provider_api.yaml → анализ → ProviderSpec (JSON) → правила Space Payments
                  → <slug>_service.rb + INTEGRATION.md + fixtures.json (+ доп.) → проверка → output/
```

Ограничения (дисквалификация): большинство кода на Ruby; никаких нейросетей в рантайме; только open-source.

Принципы:
1. Детерминированный компилятор: правила, словари, взвешенный скоринг. Повторный запуск — байт-в-байт тот же результат.
2. Парсер отдаёт семантику, не Ruby (`{conversion: {type: multiply, value: 100}}`, а не `(operation.amount * 100).to_i`).
3. Что из спеки не выводится — не угадывается: `TODO` в коде + запись в отчёт + warning в CLI.
4. Не блокировать результат без необходимости: `/balance` вне контракта не мешает сгенерировать create/status/webhook.
5. Внешне похоже на эталон из ТЗ (имена методов, `STATUS_MAP`, `ERROR_MAP`, формат вывода CLI), внутри — лучше эталона (единицы в хелпере, порог из `minimum`, `auth_headers` во всех запросах, 409 как успех, `Retry-After` из заголовка).
6. Каждое утверждение о сгенерированном коде доказывается автоматически: синтаксис, контракт, RSpec, прогон против мок-провайдера, детерминизм.

---

## 2. Архитектура и структура репозитория

```
provider-integrator/
├── Gemfile  README.md  ASSUMPTIONS.md  Rakefile  Dockerfile  compose.yaml  config.ru
├── bin/integrate                         # Thor CLI
├── app/web.rb  app/views/                # тонкий веб-слой (Sinatra/Roda) поверх того же ядра
├── lib/provider_integrator.rb            # Zeitwerk
└── lib/provider_integrator/
    ├── parser.rb                         # Parser.call(path:, overrides:) → Result
    ├── parser/      loader.rb validator.rb spec_reader.rb(openapi3_parser) swagger2_converter.rb
    │                operation_extractor.rb schema_extractor.rb
    ├── normalizer/  operation_classifier.rb authentication.rb field_mapper.rb money_units.rb
    │                conditional_required.rb status_mapper.rb error_classifier.rb webhook_analyzer.rb confidence.rb
    ├── models/      provider_spec.rb operation.rb field_mapping.rb event.rb result.rb
    ├── dictionaries/ operations.yml fields.yml statuses.yml errors.yml canonical_contract.yml
    ├── generator.rb                      # Generator.call(spec:, provider:, output_dir:) → Result
    ├── generator/   service_generator.rb documentation_generator.rb fixtures_generator.rb
    │                base_contract_generator.rb rspec_generator.rb mock_server_generator.rb
    │                report_generator.rb output_validator.rb regeneration_diff.rb
    ├── template_data/  service_template_data.rb documentation_template_data.rb fixtures_template_data.rb
    └── templates/   service.rb.erb integration.md.erb fixtures.json.erb base_contract.rb.erb
                     provider_spec.rb.erb mock_server.rb.erb
spec/
├── fixtures/specs/  novapay.yaml bearerpay.yaml rublepay.yaml numstatus.yaml cardpay.yaml legacy_swagger2.yaml
│                    real_public_*.yaml invalid_*.yaml
├── fixtures/normalized_novapay.json  generated_manifest.json     # заглушки для параллельной работы
├── golden/<spec>/   все выходные файлы
├── parser/ normalizer/ generator/ integration/ web/
examples/  overrides.example.yml
```

Владение: `parser/ normalizer/ models/ dictionaries/` — Dev A («мозг»); `generator/ template_data/ templates/` — Dev B («фабрика»); `bin/ app/ spec/integration spec/fixtures/specs README ASSUMPTIONS Docker` — Dev C («продукт»).

Стек (MIT/Ruby-лицензия): `openapi3_parser` (чтение + $ref + циклы, 3.0/3.1), `json_schemer` (валидация спеки, примеров, fixtures), `Psych.safe_load`, ERB, `Prism`/`ruby -c`, RuboCop `-A`, Thor + pastel/tty-table, RSpec + WebMock, Zeitwerk, Sinatra (веб-слой и мок-провайдер), Rack::Test.

---

## 3. Контракты между модулями (Волна 0)

### 3.1 Parser / Generator

```ruby
r = ProviderIntegrator::Parser.call(path: "provider_api.yaml", overrides: "overrides.yml")
r.success?  r.spec  # ProviderSpec   r.events  # [Event(code, level, message, location)]

g = ProviderIntegrator::Generator.call(spec: r.spec, provider: "novapay", output_dir: "./output")
g.success?  g.files  # [{path:, sha256:}]   g.events
```

### 3.2 ProviderSpec (сериализуется в JSON — это manifest/IR)

```json
{
  "provider": {"title": "NovaPay Payout API", "slug": "novapay", "version": "1.0.0"},
  "servers": {"sandbox": "https://api.sandbox.novapay.example/v1", "production": "https://api.novapay.example/v1"},
  "authentication": {"type": "api_key", "location": "header", "name": "X-API-Key", "confidence": 1.0},
  "operations": [
    {"kind": "create", "in_contract": true, "canonical_method": "create_request",
     "operation_id": "createPayout", "method": "POST", "path": "/payouts",
     "idempotency": {"location": "header", "name": "Idempotency-Key"},
     "success_codes": [201, 409], "idempotent_duplicate_codes": [409],
     "request_fields": [
       {"canonical": "amount", "provider_path": "amount", "type": "integer", "required": true,
        "conversion": {"type": "multiply", "value": 100, "unit_from": "major", "unit_to": "minor"},
        "confidence": 0.92, "evidence": ["description: копейках", "minimum: 100000", "422 example: kopecks"]},
       {"canonical": "requisite.bank_code", "provider_path": "recipient.bank_code", "required": false,
        "conditional_required": {"when": "recipient.type", "equals": "sbp"}, "confidence": 0.6,
        "evidence": ["description: обязателен для type=sbp"]}
     ],
     "response_fields": [{"canonical": "provider_operation_id", "provider_path": "id"}],
     "errors": [
       {"http": 429, "provider_code": "rate_limit_exceeded", "canonical": "rate_limit",
        "action": "retry_with_backoff", "retry_after": "header"},
       {"http": 401, "provider_code": "unauthorized", "canonical": "invalid_credentials", "action": "fatal_block_provider"}
     ],
     "confidence": 0.95},
    {"kind": "status", "canonical_method": "fetch_status", "method": "GET", "path": "/payouts/{payout_id}"},
    {"kind": "cancel",  "in_contract": false, "method": "POST", "path": "/payouts/{payout_id}/cancel"},
    {"kind": "balance", "in_contract": false, "method": "GET",  "path": "/balance"}
  ],
  "status_map": {"pending": "in_progress", "processing": "in_progress", "completed": "approved",
                 "failed": "rejected", "cancelled": "rejected"},
  "webhook": {"path": "/webhooks/payout", "source": "path_heuristic|callbacks",
              "signature": {"header": "X-NovaPay-Signature", "algorithm": "hmac-sha256", "canonicalization": "unknown"},
              "events": {"payout.completed": "approved", "payout.failed": "rejected",
                         "payout.processing": "in_progress", "payout.cancelled": "rejected"},
              "id_field": "payout_id", "error_code_path": "error.code"},
  "events": [{"code": "W301", "level": "warning", "message": "HMAC canonicalization not specified; assuming raw body → hex"}]
}
```

Правило добавления поля: обсудить → добавить в контракт → обновить `normalized_novapay.json` → использовать.

### 3.3 Реестр событий

| Код | Уровень | Когда |
|---|---|---|
| E001–E009 | error | YAML невалиден; неизвестная версия OpenAPI; нет `paths`/`info`; `$ref` не разрешается; цикл глубже лимита; файл > лимита; внешний `$ref` недоступен |
| E101 | error | Не найдена ни одна create-операция |
| E201 | error | Сгенерированный Ruby не проходит синтаксис / незаполненный ERB-плейсхолдер |
| W101 | warning | Операция классифицирована с низкой уверенностью |
| W102 | info | Операция вне контракта (`cancel`, `balance`) — сгенерирована как дополнительная |
| W103 | info | Swagger 2.0 сконвертирован в OpenAPI 3.0 перед разбором |
| W201 | warning | Статус без автоматического маппинга → дефолт `in_progress` + TODO |
| W202 | warning | Провайдерский код ошибки без канонического аналога |
| W301 | warning | HMAC назван, канонизация не определена |
| W302 | warning | Вебхук найден эвристикой по тегу/пути, не через `callbacks` |
| W401 | warning | Единицы суммы не определены → множитель 1 + TODO |
| W402 | warning | Условная обязательность выведена из текста описания |
| W403 | warning | Поле спеки не сопоставлено ни с одним каноническим полем |
| W501 | warning | Схема авторизации неизвестного типа |
| W601 | warning | Повторная генерация: в целевом файле есть ручные правки (см. regeneration_diff) |
| E001 | error | Файл не читается или не является валидным YAML/JSON |
| E002 | error | Версия OpenAPI/Swagger отсутствует или не поддерживается (поддерживаются 2.0, 3.0.x, 3.1.x) |
| E003 | error | В документе нет `paths` (или он пуст) |
| E004 | error | В документе нет `info`/`info.title` |
| E005 | error | Локальный `$ref` указывает на отсутствующий компонент |
| E006 | error | Цикл `$ref` глубже лимита |
| E007 | error | Файл больше лимита размера или вложенность глубже лимита |
| E008 | error | Внешний `$ref` (файл/URL) не поддерживается |
| E009 | error | Структурная валидация OpenAPI (openapi3_parser) вернула ошибки |
| W104 | warning | В спеке нет `servers` — `BASE_URL` придётся задать вручную |
| W105 | warning | Несколько кандидатов на одну роль контракта (например, два create) — выбран лучший, остальные как доп. методы |
| W203 | warning | Значение события вебхука без канонического статуса — сервис ответит `unknown_event` |
| W303 | warning | Событие вебхука и поле `status` расходятся — приоритет у `status` |
| W304 | warning | Вебхук не найден — `process_callback` сгенерирован заглушкой |
| W502 | warning | Операция (не вебхук) без `security`, хотя у других операций оно есть |
| I101 | info | Операция классифицирована (kind, confidence) — для каждой операции, показывается в `--verbose` |
| I102 | info | `operationId` отсутствовал и синтезирован из метода и пути |
| I201 | info | Зафиксирован статус-маппинг (критичный вывод — сообщается всегда) |
| I301 | info | Зафиксирована конвенция подписи вебхука (критичный вывод — сообщается всегда) |
| I401 | info | Зафиксированы единицы суммы с перечислением сигналов (критичный вывод — сообщается всегда) |
| I402 | info | Зафиксирована условная обязательность, выведенная структурно (discriminator/if-then/override) |
| I601 | info | Применён override из `overrides.yml` |

Уровни: `error` — результат невозможен; `warning` — результат есть, нужна проверка; `info` — дополнительно найдено. В `--strict` warnings → exit 4.

---

## 4. Канонический контракт и неизвестный `BaseService`

`BaseService` командам не дан. Решение — зафиксировать канон и сгенерировать заглушку.

**`dictionaries/canonical_contract.yml`** (всё, что невыводимо из спеки, реконструировано по эталону ТЗ):

```yaml
methods: [check_conditions, create_request, fetch_status, process_callback]
statuses: [in_progress, approved, rejected]
error_codes: [validation_error, invalid_credentials, insufficient_balance, rate_limit, internal_error, not_found]
helpers:
  client: "client.post(url, json:, headers:) / client.get(url, headers:) → response(.status, .body, .headers)"
  result: ["success", "failure(symbol, code_string)", "Result#failed?"]
  callbacks: [approve_operation(provider_id), reject_operation(provider_id, error_code)]
  exceptions: [Provider::RateLimitError, Provider::UnauthorizedError]
operation_fields: [id, amount, currency, provider_operation_id, payout_requisite]   # amount в рублях (major units)
credentials: { api_key: "credentials[:api_key]", callback_secret: "credentials[:callback_secret]" }
gateway_config: { external_method: "<method>_payout", gateway: "<CUR>_<METHOD>_WITHDRAW" }
```

**Генерируем `output/base_contract.rb`** — заглушки `Provider::BaseService`, `Provider::Result`, `Provider::Operation`, классы ошибок, с шапкой `# ДОПУЩЕНИЕ: реальный BaseService предоставляет Space Payments; файл нужен для автономного запуска тестов`.

**Подтверждено экспертами в чате (не допущения):**
- `request_method` — не HTTP-метод, а логический тип действия (payment_method шлюза либо `status`/`check`). Следствие: если спека содержит несколько способов выплаты (`recipient.type: [sbp, card]`), генератор строит ветвление `case request_method` с отдельным `build_<type>_payload` на каждую ветку, дефолт — первый в enum. Это общее правило, а не частный случай NovaPay.
- Сервис делает запрос через абстрактный `client` и **отдаёт ответ**; сохранение `provider_operation_id` происходит на платформе, вне сервиса. Реальный запрос к провайдеру на хакатоне делать не нужно → доказательства через WebMock/RSpec, мок-сервер — доп. идея, не обязательство.
- `process_callback(payload)` получает **уже разобранный JSON**, не сырое тело. Следствие для подписи: `verify_signature!` берёт подпись и сырое тело из payload по конвенции (`payload['raw_body']`, `payload.dig('headers', '<Signature-Header>')`), при отсутствии `raw_body` — `JSON.generate(payload['body'] || payload)` с явным warning W301, что канонизация по пересобранному JSON ненадёжна. Конвенция описана в INTEGRATION.md и в `base_contract.rb`.
- Статусы — канон из INTEGRATION.md задания: pending/processing → in_progress, completed → approved, failed/cancelled → rejected (отдельного «отменено» нет). 402 — `retry_later`. Допущения — в INTEGRATION.md.
- Адрес, авторизация и параметры подключения берутся **только из OpenAPI**; отдельного конфига регистрации провайдера у платформы нет → `BASE_URL = ENV.fetch(..., servers[0])`, имя заголовка из `securitySchemes`, credentials — через общий `credentials[:api_key]`.
- Production-класс `BaseService` и harness предоставлены не будут; примеры сервиса, документации и фикстур — те, что в описании кейса. Значит, заглушка `base_contract.rb` — единственный способ показать работающий код, и жюри будет сравнивать с эталоном ТЗ.
- Реализация должна быть на Ruby (включая генерируемый код).

**`ASSUMPTIONS.md`** — оставшиеся допущения (вопросы заданы в чате, ответов пока нет; дефолты ниже применены в коде и шаблонах, при ответе правится только `canonical_contract.yml`):
1. Поля `operation`: дефолт — как в эталоне, реквизиты одним хешем `payout_requisite` с ключом по типу (`dig('sbp', 'phone')`), плоских полей нет.
2. Возврат `create_request`: дефолт — `success(provider_operation_id: body['id'], status: STATUS_MAP.fetch(body['status'], 'in_progress'), response: body)`; 409 с `PayoutResponse` обрабатывается тем же путём.
3. Первый аргумент `failure`: дефолт — только символы, видимые в эталоне (`:unauthorized`, `:too_many_requests`, `:unprocessable_entity`) плюс `:provider_error` для 5xx; второй — i18n-ключ `provider.<canonical_code>`.
4. `check_conditions`: `super` вызывается первым, как в эталоне; при `failed?` — возвращаем результат базового.
5. Методы вне контракта (`cancel`, `fetch_balance`) — публичные, с комментарием «вне контракта BaseService», в INTEGRATION.md отдельной секцией.
6. `client` не ретраит и не бросает `RateLimitError` сам: сервис маппит 429/401 в исключения `Provider::RateLimitError`/`UnauthorizedError` и ловит их `rescue`, как в эталоне; `Retry-After` читается из заголовка ответа.
7. `amount_limit_exceeded` — дефолт `terminal_reject` с пометкой «возможен суточный лимит провайдера: проверить договор»; переопределяется через `error_actions` в overrides.

---

## 5. Алгоритмы — ключевые решения

**Overrides — общий механизм, не хардкод.** Эксперты подтвердили: файл переопределений не считается привязкой к провайдеру, если это механизм с фиксированными ключами. Схема `overrides.yml` (валидируется json_schemer, ключи общие для всех провайдеров):

```yaml
operations:            { createPayout: create, getBalance: extra }         # kind операции
amount_unit:           { "CreatePayoutRequest.amount": minor }              # minor|major
required_if:           [{ field: recipient.bank_code, when: recipient.type, equals: sbp }]
signature:             { header: X-NovaPay-Signature, algorithm: hmac-sha256, encoding: hex, message: raw_body }
status_map:            { awaiting_compliance: in_progress }
error_actions:         { amount_limit_exceeded: terminal_reject }
```

Каждый применённый override фиксируется в отчёте как `source: override`. Для NovaPay overrides не нужны — эталонные значения выводятся эвристиками и совпадают с каноном, подтверждённым экспертами (копейки; `bank_code` при `sbp`; HMAC-SHA256(raw body, secret) → hex).

**Классификация операций.** Приоритет: (1) явный override (`overrides.yml`, затем `x-space-payments-operation`) → (2) скоринг: `operationId` +5, путь/HTTP-форма +3, тег +2, summary/description +1, структурные бонусы (POST+body без `{id}` → create; GET с `{id}` → status; тег/путь `webhook|callback` → webhook; `/cancel`; `balance`); (3) `callbacks`/`webhooks` секции OpenAPI → webhook с высокой уверенностью. Уверенность = `(best − second)/(best + 1)`. Ниже порога → `kind: unknown` + W101.

**Сопоставление полей.** Приоритет: override → словарь синонимов → тип/формат/pattern/enum → ключевые слова описания → example → W403. Enum из одного значения → константа. Вложенность через путь. `oneOf/anyOf` с `discriminator` → ветки по значению дискриминатора.

**Единицы сумм — скоринг трёх сигналов:** описание (`копе|kopeck|cent|minor` +3), текст примеров ошибок (+3), `minimum` (кратно 100/1000 и ≥ 10 000: +2); `format: decimal`/строка/`рубл|major` → major. ≥3 → minor, множитель 100. Иначе W401, множитель 1 с TODO. Порог `check_conditions` — из `minimum` с учётом единиц.

**Условная обязательность.** Структурно: `if/then`, `oneOf/anyOf + discriminator` (высокая). Текстово: regex по описанию (средняя, W402). Результат — проверка в `check_conditions` и `compact`-сборка payload.

**Статусы.** Словарь `statuses.yml` со строковыми и числовыми синонимами. Неизвестный → `in_progress` + W201. Событие вебхука маппится отдельно; при конфликте события и `status` приоритет у `status`, warning.

**Ошибки — два уровня.** Канонический код + действие: 400/422 `terminal_reject`; 401/403 `fatal_block_provider`; 402 `retry_later`; 404 `unknown_state`; 409 с success-схемой `idempotent_success`, с error-схемой `conflict`; 429 `retry_with_backoff` (+ `retry_after: header`); 5xx `retry_alert_ops`. Провайдерский `enum` кодов уточняет канон.

**Пороги уверенности.** ≥0.75 — генерируем без TODO; 0.4–0.75 — код + `# TODO(confidence 0.6)` + warning; <0.4 — заглушка `raise NotImplementedError` + запись в отчёт.

**Критичные выводы никогда не молчат** (позиция экспертов: «молча угадывать критичное хуже»). Единицы суммы, условная обязательность, кодировка и канонизация подписи, статус-маппинг — даже при высокой уверенности попадают в `generation_report.json`, в раздел INTEGRATION.md «Требует подтверждения» и в вывод CLI как `info` с перечислением сигналов, на которых основан вывод. Комментарий с evidence ставится в код всегда, TODO — только при средней/низкой уверенности.

Подробный псевдокод — в исследовательском отчёте, раздел 4.

---

## 6. Выходные артефакты

| Файл | Статус | Содержание |
|---|---|---|
| `<slug>_service.rb` | ТЗ | Структура эталона: `BASE_URL = ENV.fetch`, 4 метода, ветвление `case request_method` по способам выплаты из enum реквизитов, `private` хелперы `build_*_payload`, `parse_*_response`, `auth_headers`, `verify_signature!` (raw body, hex, `secure_compare`), `STATUS_MAP`, `ERROR_MAP`, `ERROR_ACTIONS`; методы вне контракта с пометкой; TODO по уверенности |
| `INTEGRATION.md` | ТЗ | Авторизация и хранение credentials; ENV; таблица методов (в т.ч. вне контракта); idempotency; маппинг полей с единицами; маппинг статусов; ошибки HTTP → provider code → действие; webhook и подпись с допущением; ProviderGateway config; раздел «Требует проверки» (все W-события) |
| `fixtures.json` | ТЗ | Структура эталона; источники: examples → property examples → детерминированные по типу → `"_synthetic": true`; валидируется json_schemer против схем спеки |
| `generation_report.json` | доп. | События, уверенности, применённые правила и overrides, SHA-256 файлов |
| `base_contract.rb` | доп. | Заглушка канона |
| `<slug>_service_spec.rb` | доп. | RSpec + WebMock поверх fixtures.json: 201/409/422/429, fetch_status, callback approve/reject, signature fail |
| `<slug>_mock_server.rb` | доп. | Sinatra-мок провайдера из спеки: маршруты, валидация тел json_schemer, ответы из examples, отдача вебхука с подписью. Позволяет прогнать сгенерированный сервис end-to-end без сети |

---

## 7. CLI и веб

CLI — основной вывод текстуально близок к эталону из ТЗ, детали в `--verbose`:

```
$ ./bin/integrate --spec provider_api.yaml --provider novapay
Parsing spec... OpenAPI 3.0.3, NovaPay Payout API 1.0.0
Found 5 endpoints: POST /payouts, GET /payouts/{payout_id}, POST /payouts/{payout_id}/cancel,
                  POST /webhooks/payout, GET /balance
  create_request   → POST /payouts (confidence 0.95)
  fetch_status     → GET /payouts/{payout_id}
  process_callback → POST /webhooks/payout
  extra            → cancel, balance (вне контракта)
Auth: ApiKeyAuth (header: X-API-Key)
Webhook signature: X-NovaPay-Signature (HMAC-SHA256)
Generating service... / integration guide... / test fixtures... / report...
Validating output... Ruby syntax OK, fixtures valid, 4/4 contract methods, RSpec 9 examples 0 failures
Completed with 2 warnings:
  W301 HMAC canonicalization not specified — see INTEGRATION.md → «Требует проверки»
  W402 conditional requirement for recipient.bank_code inferred from description
Output: ./output/novapay/
```

Флаги: `--spec`, `--provider`, `--output`, `--overrides PATH`, `--analyze-only`, `--strict`, `--verbose`, `--diff` (показать расхождения с существующим output без перезаписи), `--run-spec` (сразу запустить сгенерированный RSpec), `--help`, `--version`. Exit codes: 0 ok; 1 внутренняя; 2 аргументы; 3 спека; 4 неоднозначность в strict; 5 генерация; 6 запись.

Веб (тонкий слой на том же ядре, без SPA): `/` загрузка YAML + slug → `/analysis` (эндпоинты, auth, статусы, webhook, warnings с подсветкой уверенности) → `/result` (файлы, проверки, preview, Download ZIP). Ограничение размера, whitelist slug, временная директория на запрос, без выполнения сгенерированного кода, без стек-трейсов наружу. Docker: один образ, без БД, не root, healthcheck. Публичный деплой — не нужен; демо локально.

---

## 8. Валидация результата (output_validator.rb)

`Prism.parse(src).success?`; `JSON.parse(fixtures.json)`; наследование от `BaseService`; 4 метода; нет остатков ERB; обязательные секции INTEGRATION.md; fixtures валидны против схем; SHA-256 в отчёте; RuboCop `-A`; опционально — запуск сгенерированного RSpec против `base_contract.rb` и прогон против сгенерированного мок-сервера.

---

## 9. Тесты и доказательство универсальности

- **Unit** (Dev A): битый YAML, нет `paths`, неизвестный/циклический/внешний `$ref`, Bearer/OAuth2/Basic, без webhook, `callbacks`, неизвестный статус, unit inference (копейки / рубли-decimal / без сигналов), conditional_required из описания и из `oneOf`, Swagger 2.0 конвертация.
- **Golden** (Dev B/C): `spec/golden/<spec>/*` для каждой спеки; `rake golden:update` с диффом.
- **Детерминизм**: два прогона → идентичные SHA-256.
- **Контрактный** (Dev C): сгенерированный RSpec зелёный на всех спеках с create; сгенерированный сервис проходит против сгенерированного мока.
- **Анти-хардкод**: `grep -ri novapay lib/` пуст; шаблоны не содержат провайдерских значений.

| Спека | Отличие | Что доказывает |
|---|---|---|
| S1 `bearerpay.yaml` | Bearer; `/transfers`; без webhook; статусы `NEW/SENT/DONE/DECLINED` | другие методы/поля/auth; деградация без webhook |
| S2 `rublepay.yaml` | decimal-строка в рублях; депозит (pay-in); `oneOf`+`discriminator` | единицы major; условная обязательность структурно |
| S3 `numstatus.yaml` | статусы числами; вебхук через `callbacks`; подпись в теле; OAuth2 client credentials | статусный словарь; `callbacks`; альтернативная подпись |
| S4 `cardpay.yaml` | карточная выплата; несколько create-операций (sbp+card); 3.1 (`type: [string, null]`) | выбор между кандидатами; OpenAPI 3.1 |
| S5 `legacy_swagger2.yaml` | Swagger 2.0; нет operationId; нет примеров; `x-www-form-urlencoded` | конвертация; классификация по пути; синтетические fixtures |
| S6 `real_public_*.yaml` | реальная публичная спека платёжного API (урезанная) | убедительнее любой синтетики — жюри видит чужой документ |
| `invalid_*.yaml` | битый YAML; нет `paths`; неразрешимый `$ref`; нет create | E-коды, exit 3, без падения |

---

## 10. Порядок работы: волны по ценности

Каждая волна имеет критерий завершения. Порядок внутри волны — свободный, между волнами — строгий. Ресинк команды — на границе волн; заморозка не по дате, а по факту завершения Волны 3 (после неё новые фичи не начинаются, только дальнейшие волны как есть или багфикс).

| Волна | Что делается (A / B / C) | Критерий завершения | Баллы, которые закрывает |
|---|---|---|---|
| **0. Контракты** | Все трое: ProviderSpec JSON, интерфейсы Parser/Generator, реестр E/W, `normalized_novapay.json`, `generated_manifest.json`, `canonical_contract.yml`, ASSUMPTIONS.md с вопросами | Контракт зафиксирован в репо, каждый может работать автономно | — (фундамент) |
| **1. Сквозной NovaPay** | A: loader/validator/spec_reader/extractors/классификатор/auth/status/error/units/conditional/webhook. B: service/INTEGRATION/fixtures/base_contract по шаблонам. C: CLI формата эталона, output_validator, события | `./bin/integrate` на NovaPay → 3 файла; валидатор зелёный; вывод близок к эталону | Разбор 20/20; Генерация 25/25; Преобразование 15/15; Понятность 6+4 / 4+3+3; Качество 6 / 4 |
| **2. Доказательства** | C: `invalid_*`, S1, S2, golden, детерминизм, анти-хардкод тест. A: правки по S1/S2, `overrides.yml`. B: `generation_report.json`, `rspec_generator`, TODO по уверенности в коде | Регрессия зелёная на NovaPay+S1+S2+invalid; RSpec сгенерированного сервиса проходит; `grep novapay lib/` пуст | Универсальность 15/15 / 10/10; Ошибки разбора 4 / 3; Док и fixtures 13; Доп. идеи (часть) |
| **3. Полнота и инструкция** | C: README (запуск, настройка, поддерж./неподдерж. элементы, troubleshooting), ASSUMPTIONS с ответами экспертов, Dockerfile. B: полировка INTEGRATION.md, cancel/balance как доп. методы. A: S3, `callbacks`, числовые статусы | Проект запускается на чистой машине по README; S3 зелёная | Инструкция 3; Полнота 8; Инфо по настройке 5 / 5+4 |
| **4. Сильные доп. идеи** | B: `mock_server_generator`, e2e «сервис ↔ мок» (реальные запросы к провайдеру не требуются — это только демонстрация). A: S4 (3.1, несколько create), S5 (Swagger 2.0 конвертер). C: `--diff`/`regeneration_diff`, S6 реальная спека | e2e против мока зелёный; S4–S6 зелёные; diff показывает ручные правки | Доп. идеи 6; усиление Универсальности и Выступления |
| **5. Веб и упаковка** | C: Sinatra `/`→`/analysis`→`/result`+ZIP, Rack::Test, compose. A/B: подсветка уверенности в `/analysis` | Веб и CLI дают идентичные файлы (SHA совпадает) | Демонстрация; доп. идеи |
| **6. Защита** | Все: сценарий, 3+ репетиции с таймером, ответы на вопросы, резервная запись | Демо укладывается в 7 минут стабильно | Выступление 6 |

Если по ходу выясняется, что времени всё же не хватает — граница отсечения проходит между волнами, не внутри: завершённая Волна 2 без Волн 4–5 даёт больше баллов, чем все волны, начатые наполовину.

---

## 11. Матрица баллов (сжато)

| Подпункт (Эксп / Тех) | Что даёт балл | Отв. | Проверка |
|---|---|---|---|
| Методы+параметры (8 / 5+5) | operation_classifier, schema_extractor, `--analyze-only` | A | JSON: 5 операций, поля с типами |
| Авторизация, статусы, ошибки (7 / 4+3) | authentication, status_mapper, error_classifier | A | `status_map`, `errors[].action` |
| Webhook и условия (5 / 3) | webhook_analyzer (path + `callbacks`), idempotency, Retry-After | A | JSON `webhook`, W301 |
| Формирует/шлёт запросы (10 / 5+5) | `create_request` + `build_payload` + `auth_headers` | B | RSpec: POST с телом и `X-API-Key`; e2e против мока |
| Ответы/статусы/ошибки (8 / 4+4) | `parse_*_response`, `STATUS_MAP`, rescue/ERROR_MAP, 409 | B | RSpec 201/409/422/429 |
| Уведомления + конфиг (7 / 4+3) | `process_callback`, `verify_signature!`, `ENV.fetch` | B | RSpec approve/reject/bad signature |
| Поля и статусы (8 / 5+4) | field_mapper + status_mapper | A/B | golden diff |
| Форматы/единицы/обяз. поля (7 / 3+3) | money_units, conditional_required, compact payload | A | S2 + NovaPay bank_code тест |
| Разные спеки (7 / 5) | S1–S6 | C/A | регрессия зелёная |
| Не привязано к провайдеру (5 / 3) | словари + canonical_contract.yml | A | анти-хардкод тест |
| Расширение/неподдерж. (3 / 1+1) | overrides.yml, реестр W-кодов, report | C | правило без правки кода |
| Запуск, процесс, сообщения (15 / 4+3+3) | CLI формата эталона, exit codes, события, веб | C | демо + invalid_* |
| Инфо по настройке (5 / 5+4) | INTEGRATION.md, README | B/C | секции есть |
| fixtures.json (— / 4) | fixtures_generator | B | валидны против схем |
| Структура кода (6 / 4) | parser/normalizer/generator + Zeitwerk | A | обзор на защите |
| Ошибки разбора/генерации (4 / 3) | validator, E-коды, output_validator | C | invalid_* → сообщение, exit 3 |
| Инструкция (— / 3) | README | C | чистая машина |
| Доп. идеи (6) | report, RSpec-генератор, мок-сервер, diff, base_contract | B/C | показать на защите |
| Выступление (6) | сценарий + репетиции | все | таймер |
| Полнота (8) | 4 метода + cancel/balance + 3 файла + док + веб | все | чек-лист ТЗ |

---

## 12. Защита (5–7 мин) и вопросы

Формат подтверждён организаторами: презентация нужна только топ-5, готовится после объявления финалистов; ~10 минут на команду **включая вопросы жюри**, свой экран, без ограничений по формату. Значит, рассказ — 6 минут, 3–4 минуты на вопросы; сейчас все силы — на чекпоинты, не на слайды.

Тайминг: 0:45 проблема → 1:45 живой прогон на NovaPay, сервис рядом с эталоном ТЗ: «то же, но единицы выведены, порог из `minimum`, 409 — успех, `Retry-After` из заголовка» → 1:00 «как без нейросети»: JSON-модель, словари, скоринг, уверенность → 1:00 чужая спека (S6) + битая спека → 1:00 доказательства: RSpec зелёный, e2e против мока, детерминизм, отчёт неоднозначностей → 0:30 допущения по BaseService и ответы экспертов.

Ответы: без нейросети — правила/словари/скоринг, воспроизводимо; копейки — три сигнала, при конфликте TODO; другие статусы — строка в `statuses.yml`, показать S1/S3; не выводится — не угадываем, заглушка + отчёт; почему не openapi-generator — нужен адаптер под канон, ядро на Java; BaseService не дан — заглушка контракта, допущения зафиксированы, RSpec и мок проходят; 409 — по структуре ответа идемпотентный дубль; HMAC — канонизация не в спеке, дефолт raw body + hex + secure_compare, W301; ручные правки после генерации — `--diff` и W601.

---

## 13. Риски

| Риск | Признак | План Б |
|---|---|---|
| BaseService не совпал с допущениями | ответы экспертов расходятся с `canonical_contract.yml` | правим один yml + шаблон; ASSUMPTIONS.md фиксирует источник |
| openapi3_parser падает на сложной спеке | `Error::InvalidData` | rescue → E004 с путём; собственный мини-резолвер локальных `$ref` как фолбэк |
| Недетерминизм | SHA меняется | убрать время/`Hash#inspect`, сортировать ключи, RuboCop -A |
| Захардкоженный NovaPay | S1 генерит `payouts`/`X-API-Key` | анти-хардкод тест в CI |
| Сложность не видна жюри | демо показывает только файлы | показывать `--analyze-only`, отчёт, e2e против мока |
| Демо падает | флейк на репетиции | резервная запись + прогон из golden |
| Доля не-Ruby растёт | много HTML/JS в вебе | веб без SPA, только ERB-шаблоны |

---

## 14. Definition of Done

1. `./bin/integrate --spec provider_api.yaml --provider novapay` за один запуск даёт три файла по ТЗ + report, base_contract, spec, mock.
2. Найдены 5 эндпоинтов, ApiKeyAuth, Idempotency-Key, X-NovaPay-Signature, статусы, ошибки с действиями, единицы, условная обязательность.
3. Сервис проходит синтаксис, 4 метода контракта, RSpec на fixtures зелёный, e2e против мока зелёный.
4. Повторный запуск — идентичные SHA-256; `--diff` показывает ручные правки.
5. Неоднозначности — W-события в CLI, в отчёте и как TODO в коде.
6. S1–S6 проходят без правки кода; анти-хардкод тест зелёный.
7. `invalid_*` дают понятную ошибку и exit 3.
8. Веб и CLI дают идентичный результат; проект запускается на чистой машине по README.
9. ASSUMPTIONS.md содержит допущения и ответы экспертов.
10. Демо стабильно укладывается в 7 минут.
