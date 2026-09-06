# Контракт IR `ProviderSpec` (ir_version 1) и правила анализаторов

Этот документ — исполняемая часть `docs/PLAN.md §3`: точная форма промежуточного представления (IR), которое
`Parser.call` производит, а `Generator.call` потребляет, плюс правила, по которым парсер заполняет каждое
поле. Эталон значений — `spec/fixtures/normalized_novapay.json` (тест парсера сравнивает с ним IR
NovaPay целиком). Изменение контракта — только через раздел «Процедура изменения» в конце.

Код моделей: `lib/provider_integrator/models/*.rb` (`Data.define`, `Models::Base`). Словари:
`lib/provider_integrator/dictionaries/*.yml`. JSON-схема IR: `lib/provider_integrator/schemas/provider_spec.schema.json`.

## 0. Инварианты

- IR — чистые JSON-данные: `Hash` со строковыми ключами, `Array`, `String`, `Integer`, `Float`, `true/false/nil`.
  Сериализация только через `JsonCanon.generate` (ключи отсортированы, массивы в исходном порядке, `\n` в конце).
- Каждая модель сериализуется **со всеми** членами (nil явно). `from_h` отвергает неизвестные и отсутствующие ключи.
- Детерминизм: одинаковая спека → байт-в-байт одинаковый IR. Порядок операций — порядок `paths` в документе, внутри
  пути — порядок методов в документе; порядок полей — порядок `properties` (обход в глубину: контейнер, затем дети).
- Все `confidence` — `Float` в [0, 1], округлённые до двух знаков (`round(2)`); `1.0` остаётся `1.0`.
- Парсер отдаёт семантику, не Ruby: `conversion: {type: multiply, value: 100}`, а не код.
- Строки из спеки (описания, имена) кладутся как есть (без экранирования); экранирует генератор через `Inflector`.
- `evidence` — массив коротких строк (форматы ниже), которые генератор копирует в комментарии и отчёт.
- Все текстовые сравнения (основы, синонимы, ключевые слова) — без учёта регистра (downcase обеих сторон).

## 1. Модели

Обозначения: `?` — может быть `nil`; `[X]` — массив X (пустой массив, не nil, если нечего положить).

### ProviderSpec
| член | тип | правило |
|---|---|---|
| ir_version | Integer | всегда `1` |
| provider | Provider | см. ниже |
| spec_format | SpecFormat | `openapi` — строка версии (`"3.0.3"`), `converted_from` — `"2.0"` после конвертации Swagger, иначе nil |
| servers | [Server] | `servers[]` спеки в исходном порядке; `environment`: url или description (downcase) содержит `sandbox|test|stag|dev|uat` → `sandbox`; иначе `prod|live` → `production`; иначе `unknown` |
| authentication | Authentication | §2.2 |
| operations | [Operation] | все операции спеки, включая вебхук и операции вне контракта |
| statuses | [StatusMapping] | §2.7: объединение enum-значений всех полей с canonical `status` в порядке первого появления |
| webhook | Webhook? | §2.9; nil, если вебхук не найден (W304) |
| gateway_config | GatewayConfig? | §2.10; nil, если нет create-операции |
| overrides_applied | [OverrideApplied] | §2.11 |
| events | [Event] | §3; отсортированы |
| extensions | Hash | корневые ключи документа `x-*` (без изменений); `{}` если нет |

### Provider
`title` = `info.title`; `version` = `info.version` (строка); `description` = `info.description.strip` или nil;
`slug` = первый токен `title` (split по пробелам), downcase, без символов вне `[a-z0-9]`; пустой → `"provider"`.
CLI `--provider` **не** меняет `provider.slug` в IR (это имя для класса, его подставляет генератор).

### Authentication
`type`: `api_key | http_bearer | http_basic | oauth2_client_credentials | oauth2 | none | unknown`.
`scheme_name` — ключ в `securitySchemes`; `location`: `header | query | cookie` (для http-схем `header`);
`name`: имя заголовка/параметра (`X-API-Key`; для http-схем `Authorization`); `bearer_format`, `token_url`
(flow clientCredentials), `scopes` ([String], `[]` если нет); `credentials_key` — первый ключ из
`canonical_contract.yml → credentials[type]` (`api_key`, `token`, `login`, `client_id`); для `none/unknown` nil.
`confidence`: 1.0 если схема одна или используется большинством операций; 0.7 при равенстве кандидатов.
`source`: `security_schemes | override`; `alternatives`: остальные схемы (AuthAlternative: scheme_name, type, location, name).
Без `securitySchemes` → `type: none`, confidence 1.0, evidence `["no securitySchemes declared"]`.
Неизвестный тип (openIdConnect, mutualTLS) → `unknown` + W501.
evidence: `"securitySchemes.<Name>: <openapi type>[ <scheme>] in <location> <name>"`,
`"security: <Name> used by <n> of <m> operations"`.

### Operation
| член | правило |
|---|---|
| kind | `create | status | cancel | balance | webhook | refund | list | unknown` (§2.1) |
| in_contract | true для первого выбранного кандидата каждого из `create`, `status`, `webhook` |
| canonical_method | `canonical_contract.yml → contract_roles[kind]` для `in_contract: true`; `extra_methods[kind]` для `cancel/balance/refund/list`; nil для `unknown` и для вторых кандидатов контрактных kind (генератор именует их из `operation_id`) |
| operation_id | из спеки; если нет — синтез `<method>_<path_tokens>` в snake_case (`post_payouts`), событие I102; синтезированный id **не** участвует в скоринге |
| method | HTTP-глагол верхним регистром (`POST`) |
| path | путь как в спеке |
| summary, description | как в спеке (`strip`), nil если нет |
| tags | [String], `[]` если нет |
| security | имена схем, применимых к операции (собственный `security` или глобальный); `[]` при `security: []` |
| public | `security == []` |
| classification | Classification (§2.1) |
| idempotency | Idempotency? — параметр с canonical `idempotency_key` (`location` = `in`, `name`, `required`, `format`) |
| parameters | [Parameter] — все параметры операции и path-item, `$ref` разрешены |
| request_body | RequestBody? |
| request_fields | [FieldMapping] — плоский список полей схемы тела (первый media type); `[]` если тела нет |
| response_fields | [FieldMapping] — поля схемы **первого успешного** ответа (`kind: success`); `[]` если нет |
| responses | [Response] — все объявленные ответы в порядке спеки |
| success_codes | коды ответов с `kind` `success` или `idempotent_duplicate`, по возрастанию |
| idempotent_duplicate_codes | коды с `kind: idempotent_duplicate` |
| errors | [ErrorMapping] — по одному на ответ с `kind: error`, в порядке ответов |
| request_methods | RequestMethods? — только для `kind: create` (§2.5); иначе nil |
| confidence | = `classification.confidence` |

### Classification
`confidence` (§2.1), `source`: `scoring | extension | override | callbacks`; `scores`: Hash kind → Integer для всех
семи kind (нули включительно); `evidence`: строки в порядке источников operationId → path/структура → tag → text;
внутри одного источника — в порядке `operations.yml → kinds`.

### Parameter
`name`, `in` (`path|query|header|cookie`), `required` (Boolean; path → true), `type`/`format` из схемы (nil если нет),
`description`, `example` (параметра или схемы), `enum` (nil если нет), `canonical`:
- path-параметр: имя в snake_case; если оно — синоним `external_id` из `fields.yml` → `external_id`; если содержит
  токен из `operations.yml → path_parameters.not_provider_id_stems` → nil; если последний токен ∈ `id_stems` →
  `provider_operation_id`; иначе nil;
- header/query/cookie: роль по `fields.yml → parameters` в порядке `idempotency_key → signature → auth`; элемент
  списка без `_` — основа (любой токен snake_case-имени начинается с неё), с `_` — точное имя; иначе nil.

### RequestBody
`content_type` — первый media type; `required` (Boolean, default false); `schema_name` — имя компонента, если
схема — `$ref` (иначе nil); `example` — по правилу композиции §2.12; `examples` — Hash имя → `value` всех
именованных примеров в порядке спеки (`{}` если нет).

### FieldMapping
| член | правило |
|---|---|
| provider_path | путь через точку (`recipient.bank_code`), элементы массива — `items[]` (`items[].sku`) |
| canonical | §2.3; nil если не сопоставлено |
| type | `type` схемы (`string|integer|number|boolean|object|array`); в 3.1 массив типов → первый не-`null`, `nullable: true`; nil если нет |
| format | как в схеме или nil |
| required | входит ли имя в `required` **родительского** объекта |
| nullable | `nullable: true` (3.0) или `null` в списке типов (3.1); иначе false |
| enum | список или nil |
| constant | единственное значение enum или `const`; иначе nil |
| pattern, minimum, maximum, min_length, max_length, description, example, default | как в схеме (`strip` для description) или nil |
| conversion | Conversion? — только для request-полей create-операции с `money: true` (§2.4) |
| conditional_required | ConditionalRequired? — только для request-полей (§2.6) |
| branch | Branch? — для полей внутри ветки `oneOf/anyOf` с `discriminator` (`discriminator_path`, `value`) |
| confidence, evidence, source | §2.3 |

### Conversion
`type`: `multiply | divide | to_decimal_string | identity`; `value`: множитель (Integer) или nil для `identity/to_decimal_string`;
`unit_from`: `major` (единицы `operation.amount`), `unit_to`: `minor | major`; `confidence`, `evidence` (§2.4), `source`: `scoring | override`.

### ConditionalRequired
`when` — provider_path поля-условия, `equals` — значение, `source`: `description | discriminator | if_then | override`,
`confidence` из `fields.yml → conditional_required.confidence`, `evidence` (§2.6).

### Response
`http` (Integer; ответ `default` → `0`), `description`, `schema_name` (имя компонента или nil), `kind`: `success` (2xx,
кроме идемпотентного дубля) | `idempotent_duplicate` (409 со схемой, равной схеме первого успешного ответа) |
`error` (4xx/5xx) | `other` (1xx/3xx/`default`); `content_type` (первый media type или nil); `example` (§2.12);
`headers` — [ResponseHeader] объявленных заголовков: `name`, `type` (схемы), `description`, `canonical`:
`retry_after`, если snake_case имени ∈ `errors.yml → retry_after.headers`, иначе nil.

### ErrorMapping
Для каждого ответа `kind: error`: `http`, `provider_code` (§2.8), `canonical` (код из `canonical_contract.yml →
error_codes`), `action` (из `actions`), `retry_after`: `"header"` если ответ объявляет заголовок с canonical
`retry_after`; `"body"` если snake_case имени поля схемы ответа ∈ `errors.yml → retry_after.body_fields`; иначе nil;
`description` и `example` ответа; `confidence`, `evidence`, `source`: `example | enum | http_default | override`.

### RequestMethods
`discriminator_path` — provider_path поля-переключателя (`recipient.type`), `values` — значения в порядке enum,
`default` — первое, `source`: `enum | discriminator | one_of | override`, `confidence` из `fields.yml → request_methods.confidence`.

### StatusMapping
`provider` — значение как строка (числа → `"1"`), `canonical` — `in_progress | approved | rejected`,
`confidence`/`source` (`dictionary | token | description | numeric_default | default | override`), `evidence` (§2.7).

### Webhook
| член | правило |
|---|---|
| path, method, operation_id, summary | из операции-вебхука; для `callbacks` — путь выражения callback, method из него |
| source | `override | extension | callbacks | path_heuristic | tag_heuristic | operation_id_heuristic` — первый применимый в этом порядке (для скоринга: совпала основа пути → path, иначе тега → tag, иначе operationId) |
| confidence | = confidence классификации операции; для callbacks 1.0 |
| evidence | = evidence классификации |
| signature | Signature? (§2.9) |
| event_field | provider_path поля события: кандидаты — все поля payload (обход в глубину), чей последний сегмент ∈ `fields.yml → webhook.event_field`; приоритет — порядок списка, при равенстве — верхний уровень раньше вложенного, затем порядок обхода; nil если нет |
| events | [WebhookEvent] — значения enum поля события в порядке спеки (`[]` если поля/enum нет) |
| status_field | аналогично по `webhook.status_field`, исключая `fields.yml → canonical.status.exclude` |
| id_field | provider_path первого поля payload с canonical `provider_operation_id` (верхний уровень раньше вложенного) или nil |
| external_id_field | первое поле с canonical `external_id` или nil |
| error_code_path, error_message_path | первое поле с canonical `error.code` / `error.message` или nil |
| payload_fields | [FieldMapping] тела вебхука (= `request_fields` операции-вебхука) |
| examples | Hash имя → value именованных примеров тела; если только `example` → `{"default" => value}`; `{}` если нет |
| response | WebhookResponse? — первый 2xx ответ: `http`, `example` (§2.12) |

### Signature
`location`: `header | body | query`; `name` — имя заголовка/поля; `algorithm`: `hmac-sha256 | hmac-sha512 | hmac-sha1 |
hmac-md5 | sha256 | sha512 | sha1 | md5 | rsa-sha256 | ed25519 | unknown`; `encoding`: `hex | base64 | unknown`; `message`:
`raw_body | concatenated_fields | unknown`; `secret`: `callback_secret` (ключ credentials, из `canonical_contract.yml`);
`confidence`: 0.9 при найденном алгоритме и месте; 0.5 если найдено только место (алгоритм unknown);
`evidence` (§2.9); `source`: `parameter | field | description | override`.
Signature = nil, если ни параметр с canonical `signature`, ни поле payload из `fields.yml → webhook.signature_field` не найдены.

### WebhookEvent
`value` — значение enum; `canonical_status` — по §2.7 через токены значения (nil если нет → W203);
`confidence`, `source` (`dictionary | token | override | none`). `none` — ровно тот случай, когда
`canonical_status` = nil: значение события не сопоставлено, confidence 0.0, событие W203.

### GatewayConfig
§2.10: `external_method`, `gateway`, `direction` (`withdraw | deposit`), `currency` (код или nil), `method`
(способ выплаты по умолчанию или `"default"`), `confidence`, `evidence`.

### OverrideApplied
`key` — раздел overrides.yml (`operations | amount_unit | required_if | signature | status_map | error_actions`),
`target` — к чему применено (`createPayout`, `CreatePayoutRequest.amount`), `value` — что подставлено (строка/хеш),
`note` — nil или пояснение.

### Event
`code` из реестра `lib/provider_integrator/events.rb`, `level`, `message` (рендер шаблона), `location` (§3),
`details` — все плейсхолдеры шаблона (канонизировано: строковые ключи, отсортированы) или nil.

## 2. Правила анализаторов

Общая формула уверенности для скоринговых решений: `confidence = (best − second) / (best + 1)`, где `best` —
лучший суммарный балл, `second` — следующий. Результат `round(2)`. При `best == 0` → 0.0.

### 2.1 Классификация операций (`operations.yml`)
Приоритет источников: `overrides.yml → operations` (source `override`, confidence 1.0) → расширение
`x-space-payments-operation` на операции (source `extension`, 1.0) → скоринг (source `scoring`).
Секция `callbacks` операции создаёт **дополнительный** Webhook (source `callbacks`, 1.0), если ни одна операция
не классифицирована как webhook.

Токенизация: operationId — по границам camelCase, `_`, `-`, `.`, цифрам; путь — сегменты без `{…}`, каждый ещё
по `_`, `-`, `.`; теги — по пробелам, `_`, `-`; summary+description — по `[^\p{L}\p{N}]+`. Всё в нижний регистр.
Совпадение основы: `token.start_with?(stem)`, кроме токенов из `exclude_tokens` этого kind (точное равенство —
такие токены не совпадают ни с одной основой kind). Для kind `webhook` любой токен operationId из
`exclude_operation_id_tokens` обнуляет все баллы webhook этой операции.

Баллы на kind (каждый источник даёт балл kind не более одного раза):
1. operationId (только настоящий, не синтезированный): сильная основа → +5. Слабая основа → +2, **только если**
   (a) ни у одного kind не совпала сильная основа и (b) этот kind получил балл от пути/структуры (п. 2).
2. путь: основа `path`-списка kind в сегменте → +3; иначе структурное правило → +3: create — `POST` + тело + без
   `{…}` в пути + ни один сегмент не начинается с `excluded_path_stems`; status — `GET` + `{…}` в пути; cancel —
   `DELETE` + `{…}` в пути; list — `GET` без `{…}` и без `excluded_path_stems`.
3. тег: основа `path`-списка kind в токене тега → +2.
4. текст: основа `text`-списка в токенах summary, затем description → +1, **только для kind, у которого уже есть
   балл от п. 1–3** (текст подтверждает, но не вводит kind); evidence — первый совпавший токен.

`kind` = argmax; равенство лучших → `unknown`. Если единственный сигнал kind — структурное правило (п. 2 без
основ, тегов и текста), confidence = `min(confidence, thresholds.structural_only_cap)`. `confidence <
unknown_below` → `unknown` + W101; `< low_confidence_below` → kind сохраняется + W101. `unknown` → W102
(генерируется как доп. метод). Несколько кандидатов на один контрактный kind → первый по порядку спеки с
максимальным баллом становится `in_contract`, остальные — `in_contract: false`, `canonical_method: nil` + W105
(один раз на kind). Нет create → E101; нет status → W106; нет webhook → W304.

evidence: `"operationId token '<token>' -> <kind> (+<w>)"`, `"path token '<token>' -> <kind> (+3)"`,
`"structure POST with body and no path id -> create (+3)"`, `"structure GET with path id -> status (+3)"`,
`"structure DELETE with path id -> cancel (+3)"`, `"structure GET without path id -> list (+3)"`,
`"tag '<tag>' -> <kind> (+2)"`, `"text '<token>' -> <kind> (+1)"`.

### 2.2 Авторизация — см. модель Authentication. W502: операция не-вебхук с `security: []`, когда у других есть схема.

### 2.3 Сопоставление полей (`fields.yml`)
Имя поля нормализуется в snake_case (camelCase, kebab-case, пробелы). Контекст поля: `request` (тело
create-операции), `response`, `webhook` (payload вебхука), `parameter`. Порядок:
1. override (`source: override`, 1.0);
2. поле, чей **ближайший сопоставленный предок** — контейнер (`requisite|error|customer`): имя в `children`
   контейнера → `<container>.<child>` (`confidence.exact`, source `dictionary`); иначе `<container>.<snake_name>`
   (`confidence.container_child`, source `container`). Дальнейшие шаги для таких полей не применяются;
3. точное совпадение имени с синонимом канонического поля (`confidence.exact`, source `dictionary`) с учётом:
   `scope` записи (`provider_operation_id` — только `response|webhook|parameter`); `request_synonyms` записи
   `external_id` — только в контексте `request`; `exclude` записи (имя из `exclude` не сопоставляется);
   контейнер сопоставляется по своим синонимам только если поле имеет `type: object` (или `properties`/`oneOf`);
4. плоские схемы (`fields.yml → flat`): имя ∈ `flat.requisite.type` → `requisite.type` (exact); имя ∈
   `children` контейнера `requisite` → `requisite.<child>` (`confidence.flat_requisite`, source `dictionary`);
   имя ∈ `flat.error.code|message` → `error.code|error.message` (exact); в контексте `response` с `kind: error`
   и `webhook` — имя ∈ `flat.error_context` → `error.code|error.message` (`confidence.context`); скалярное поле
   с именем-синонимом контейнера `error` → `error.code` (exact);
5. контекст `response|webhook`, имя оканчивается на суффикс `provider_operation_id.suffixes` →
   `provider_operation_id` (`confidence.suffix`, source `dictionary`);
6. иначе `canonical: nil`, confidence 0.0, evidence `[]`, source `none`; для `required` полей контекста
   `request` — W403.
evidence: `"fields.yml: <name> -> <canonical>"` (шаги 3–5, для суффикса `"fields.yml: suffix <suffix> ->
provider_operation_id"`), `"fields.yml: <container> child <name> -> <canonical>"` (шаг 2, exact),
`"container <container>: <name> -> <canonical>"` (шаг 2, container_child), `"fields.yml: flat <name> -> <canonical>"` (шаг 4).

### 2.4 Единицы суммы (`fields.yml → money_units`)
Для каждого request-поля create-операции с `money: true`. Совпадение основы: основа без пробела — префикс токена
текста (токены по `[^\p{L}\p{N}]+`, downcase); основа с пробелом — подстрока текста (downcase). `<слово>` в
evidence — совпавший токен (для основ с пробелом — сама основа).
- minor: description поля (+3, `"description: <слово>"`); JSON-текст (`JsonCanon.generate`) примера любого
  ответа `kind: error` операции в порядке ответов (+3 не более одного раза, `"error example (<http>): <слово>"`
  для первого совпавшего ответа); `minimum` кратен `minimum_multiple_of` и ≥ `minimum_at_least` (+2, `"minimum: <value>"`).
- major: description поля (+3, `"description: <слово>"`); `format` ∈ `format_stems` (+2, `"format: <format>"`);
  `pattern` содержит одну из `pattern_stems` (+2, `"pattern: <pattern>"`); `multipleOf < 1` (+2, `"multipleOf: <v>"`);
  `type: string` (+1, `"type: string"`).
Порядок проверки и evidence: description(minor) → error examples → minimum → description(major) → format → pattern
→ multipleOf → type. Решение: `minor ≥ minor_threshold && minor > major` → `multiply` на exponent валюты
(`currency_exponents` по constant поля currency, иначе default), `unit_to: minor`; `major ≥ major_threshold &&
major > minor` → `unit_to: major`, `type: to_decimal_string` при `type: string`, иначе `identity` (value nil);
иначе (в том числе равенство) — `identity`, value 1, W401. confidence по общей формуле от (minor, major).
Всегда I401 (`unit` = minor|major|unknown, `multiplier` = value или 1, `score` = лучший балл, `signals` = evidence).

### 2.5 Способы выплаты (RequestMethods)
Для create-операции: поле с canonical `requisite.type` и enum → `source: enum`, values = enum; иначе
`discriminator.propertyName` внутри контейнера requisite → `source: discriminator`, values = ключи `mapping`
или имена схем oneOf; иначе `oneOf` без discriminator → `source: one_of`, values = имена схем ветвей
(snake_case); иначе nil. `default` — первое значение.

### 2.6 Условная обязательность
Структурно: `if/then` с `required` (source `if_then`); поле внутри ветки oneOf с discriminator, `required` в ветке
(source `discriminator`, `when` = discriminator_path, `equals` = значение ветки) → I402. Текстом: первый regex из
`description_patterns` (без учёта регистра) по description поля (source `description`) → W402; `when` — имя из
regex, разрешённое как сосед поля (тот же контейнер: `recipient.type`), если такого поля нет — как есть.
evidence: `"description: <совпавший фрагмент>"` (match[0]), `"discriminator <path> = <value>"`, `"if/then: <path> = <value>"`.

### 2.7 Статусы (`statuses.yml`)
Нормализация: строка, downcase, `[-. ]` → `_`. Совпадение с `synonyms` → source `dictionary`; числовое
значение из `numeric` → `numeric_default` + W204; описание enum-поля по `description_patterns`: текст токенизируется
по `[^\p{L}\p{N}]+`, слова `description_words` — префиксы токенов, проверка в порядке `rejected → approved →
in_progress` → source `description`; иначе `default` + W201. evidence: `"statuses.yml: <provider> -> <canonical>"`,
`"statuses.yml numeric: <v> -> <canonical>"`, `"description: <value> — <text>"`, `"default: <canonical>"`.
I201 всегда, один раз: `mapping` — пары в порядке `ProviderSpec.statuses` (сообщение перечисляет их в этом порядке;
`details.mapping` хранится с отсортированными ключами).
События вебхука: токены значения по `[._-]` с конца; последний токен совпал → `dictionary` (0.95), другой → `token` (0.85).

### 2.8 Ошибки (`errors.yml`)
`provider_code`:
1. строка `code` из примера ответа: значение первого поля примера, чей путь совпадает с полем canonical `error.code`
   схемы ответа; иначе первый ключ `code|error_code|error` со строковым значением (обход в глубину) → source `example`;
2. иначе enum поля с canonical `error.code` схемы ответа: (a) значение, равное каноническому имени HTTP-дефолта
   (`internal_error`); (b) иначе первое значение, чья запись `provider_codes` даёт **и** канон, **и** действие
   HTTP-дефолта; → source `enum`, канон и действие — HTTP-дефолта;
3. иначе nil, source `http_default`.
`canonical/action` для source `example`: по `provider_codes` (первая запись, чья основа входит в нормализованный
код) → иначе по `http` (→ `default_4xx/5xx`) + W202. Провайдерский код побеждает HTTP-дефолт, **кроме** случая
`http_guard`: HTTP ∈ `http_guard.statuses` и действие записи ∈ `terminal_actions` → канон и действие HTTP-дефолта.
evidence:
`example`: `["example (<http>): code <code>", "errors.yml: <code> -> <canonical> (<action>)"]`, при http_guard
третья строка `"http <http> overrides terminal action <action записи>"`;
`enum`: `["enum <Schema>.<field>: <code>", "errors.yml: HTTP <http> -> <canonical> (<action>)"]`, где `<Schema>` — имя
компонента, владеющего enum-свойством (`PayoutError`), при inline-схеме — `inline`, `<field>` — имя свойства;
`http_default`: `["errors.yml: HTTP <http> -> <canonical> (<action>)"]`.
`note` записи попадает в evidence последней строкой `"note: <note>"`.

### 2.9 Вебхук и подпись
Вебхук = первая операция с `kind: webhook` (иначе `callbacks`, иначе nil + W304). W302 — если найден эвристикой и
источников evidence (operationId/path/tag/text) меньше двух.
Подпись: параметр операции с canonical `signature` (`location` = `in`, source `parameter`) или верхнеуровневое поле
payload, чьё имя совпадает с `fields.yml → webhook.signature_field` по правилу параметров (`location: body`,
source `field`). Тексты для поиска, в порядке: description параметра/поля → description операции → summary
операции. Алгоритм — первая основа в любом тексте: `hmac.?sha.?512` → `hmac-sha512`, `hmac.?sha.?256|hmac.?256`
→ `hmac-sha256`, `hmac.?sha.?1\b` → `hmac-sha1`, `hmac.?md5` → `hmac-md5`, `hmac` (без хеша) → `hmac-sha256`,
`sha.?512` → `sha512`, `sha.?256` → `sha256`, `sha.?1\b` → `sha1`, `md5` → `md5`, `rsa` → `rsa-sha256`, `ed25519`;
иначе `unknown`. `encoding`: `hex|hexdigest|шестнадцат` → hex, `base64` → base64, иначе unknown. `message`:
`concat|sorted|fields|конкатен|полей|склеен` → `concatenated_fields`; иначе для `location: header|query`
`raw|сыр|bytes|body|тела|payload` → `raw_body`; для `location: body` → `concatenated_fields` только при основе
`concat…`, при `raw|сыр|bytes` → `raw_body`, иначе `unknown`.
evidence — по одной строке на каждый текст, содержащий основу алгоритма, в порядке поиска:
`"parameter <name> (<in>): <description>"`, `"field <path>: <description>"`, `"operation description: <предложение>"`,
`"operation summary: <summary>"`, где `<предложение>` — предложение (split по `.`/`\n`, strip) с первым совпадением.
Если алгоритм не найден ни в одном тексте — единственная строка `"parameter <name> (<in>)"` / `"field <path>"`.
W301 при `encoding == unknown || message == unknown` (детали `default_encoding/default_message` из `signature_defaults`).
I301 всегда при наличии подписи.

### 2.10 GatewayConfig
`currency` — constant поля с canonical `currency` среди request-полей create (иначе `example`, иначе nil);
`method` — `request_methods.default` или `"default"`; `direction` — первая основа из `operations.yml → direction`
(префикс токена) в operationId → path → tags (основные источники) → summary → description create-операции →
`info.title` (дополнительные) → `default` + W405.
Шаблоны `canonical_contract.yml → gateway_config[direction]`: `%{method}` snake_case, `%{METHOD}`/`%{CURRENCY}` upcase;
без currency — `XXX`. confidence: 0.9 − 0.3 за каждый сигнал не из основного источника (currency не constant,
method `default`, direction из дополнительных источников или по умолчанию), минимум 0.3. Всегда I403.
evidence: `"currency: <code> (enum constant|example|unknown)"`, `"request method: <m> (default of <path>|no requisite type)"`,
`"direction: <d> (token '<t>' in <source>|default)"`, где `<source>` ∈ {`operationId <id>`, `path <path>`,
`tag <tag>`, `summary`, `description`, `info.title`}, `<t>` — совпавший токен.

### 2.11 Overrides (`overrides.yml`, схема `schemas/overrides.schema.json`)
Ключи фиксированы: `operations` {operationId → kind}, `amount_unit` {"Schema.field" → minor|major},
`required_if` [{field, when, equals}], `signature` {header|field, algorithm, encoding, message},
`status_map` {provider → canonical}, `error_actions` {provider_code → action}. Каждое применение → OverrideApplied +
I601 и `source: override` в затронутой модели.

### 2.12 Композиция примеров
Для RequestBody/Response/WebhookResponse `example`: media `example` → `value` первого из `examples` →
`example` схемы → композиция из схемы: объект — по свойствам в порядке `properties`, берутся только свойства,
давшие значение (значение найдено, если оно не nil; `false` и `0` — значения); скаляр — `example` свойства,
иначе `const`, иначе единственное значение `enum`, иначе `default`; массив — `[композиция items]`; объект без
единого значения → пропускается; пустой результат → nil.
Парсер **никогда** не придумывает значения по типу — это делает генератор фикстур и помечает `"_synthetic": true`.

## 3. События

Все события создаются через `Events.build(code, location:, **details)`; `details` = все плейсхолдеры шаблона.
`location` — JSON-pointer в документ: операция `#/paths/~1payouts~1{payout_id}/get` (`/` в ключе пути → `~1`),
поле схемы-компонента `#/components/schemas/Recipient/properties/bank_code`, поле inline-схемы —
`#/paths/<path>/<method>/requestBody/content/application~1json/schema/properties/<name>`, параметр —
`#/paths/<path>/<method>/parameters/<index>`; спека в целом — nil.

Порядок `ProviderSpec.events`: сортировка по (ранг уровня: error 0, warning 1, info 2; code; location, nil → `""`; message).
Обязательные события на NovaPay: I101 ×5, I201, I301, I401, I403, W102 ×2 (info), W301, W402 ×2.
Не должно быть: W302, W502, W403, W201, W204, W405, W106.

## 4. Что генератор выводит сам (не хранится в IR)
- Путь кода ошибки в HTTP-ответах: первое поле `response_fields` с canonical `error.code`, иначе путь ключа `code`
  в `ErrorMapping.example`, иначе только маппинг по HTTP-статусу.
- Синтетические значения фикстур по типу (`"string"`, `0`, `false`, `"2026-01-01T00:00:00Z"`), `_synthetic: true`.
- Имена в Ruby (`Inflector`): класс, константа ENV, имена методов вне контракта из `operation_id`.
- Принадлежность реквизита ветке способа выплаты: поле с `conditional_required` — только в ветке `equals`;
  остальные — во всех ветках (`compact` убирает nil).

## 5. Процедура изменения контракта
1. Обсудить (или, в автономном режиме, зафиксировать обоснование в этом документе, раздел «Ожидают подтверждения»).
2. Обновить модель, схему `provider_spec.schema.json`, `spec/support/model_examples_*.rb`, `normalized_novapay.json`.
3. Обновить парсер и генератор в одном коммите с пометкой `contract:` в сообщении.

### Ожидают подтверждения
1. **Реестр событий (волна 0, по итогам ревью словарей):** добавлены `W106` (нет status-операции), `W204` (числовой
   статус по конвенции), `W405` (направление операции по умолчанию), `I403` (gateway config записан всегда).
   Обоснование: инвариант «что не выводится — не угадывается молча»; без них заглушка `fetch_status`, конвенция
   `0/1/2` и `RUB_SBP_WITHDRAW` для депозита попадали бы в вывод без предупреждения.
2. **`WebhookEvent.source: none` (волна 1A):** значение события вебхука без канонического статуса не могло
   быть выражено — enum допускал только `dictionary | token | override`. Добавлено `none` (совпадает с
   соглашением `FieldMapping.source: none` для несопоставленного поля). Обоснование: инвариант «что не
   выводится — не угадывается»; альтернатива (подставить `in_progress`) прятала бы W203.
3. **S4 (несколько create-операций по способам выплаты, волна 4):** потребуется `RequestMethods.source: operations`
   и путь на каждое значение (`paths: {sbp: "/payouts/sbp"}`) — новый член модели. До подтверждения вторые
   create-кандидаты остаются `in_contract: false` с W105.
