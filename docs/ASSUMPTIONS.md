# Допущения и подтверждённые факты

Источник истины по приоритету: `docs/TZ.md` (эталон и разбалловка) → ответы экспертов (`docs/PLAN.md §4`) → план.
Каждый дефолт ниже указывает место в коде или словаре, где он меняется. Изменение дефолта не требует правки
шаблонов — только словаря.

## 1. Подтверждено экспертами (не допущения)

| # | Факт | Где закреплено |
|---|---|---|
| 1 | `request_method` — логический тип действия (способ выплаты `sbp`/`card` или `status`), не HTTP-метод. При нескольких способах выплаты в enum реквизитов сервис ветвится `case request_method` с `build_<type>_payload` на ветку, дефолт — первое значение enum | IR `operations[].request_methods` (`docs/IR_CONTRACT.md §2.5`), `fields.yml → request_methods` |
| 2 | Сервис шлёт запрос через абстрактный `client` и возвращает ответ; `provider_operation_id` сохраняет платформа. Реальных запросов на хакатоне нет — доказательства через WebMock/RSpec; мок-сервер — доп. идея | `canonical_contract.yml → helpers.client`, `output/base_contract.rb` |
| 3 | `process_callback(payload)` получает уже разобранный JSON. Подпись и сырое тело берутся из payload по конвенции `payload['raw_body']`, `payload.dig('headers', '<Signature-Header>')`; без `raw_body` — `JSON.generate(payload['body'] \|\| payload)` с W301 | `canonical_contract.yml → callback_payload`, `signature_defaults` |
| 4 | Канон статусов: `pending/processing → in_progress`, `completed → approved`, `failed/cancelled → rejected`; отдельного «отменено» нет. 402 → `retry_later` | `statuses.yml → synonyms`, `errors.yml → http` |
| 5 | Адрес, авторизация и параметры подключения — только из OpenAPI: `BASE_URL = ENV.fetch('<SLUG>_BASE_URL', servers[0])`, имя заголовка из `securitySchemes`, секреты через общий `credentials[...]` | `canonical_contract.yml → env, credentials` |
| 6 | Production-`BaseService` и harness не предоставляются; жюри сравнивает с эталоном ТЗ. Заглушка `base_contract.rb` — единственный способ показать работающий код | `Generator::BaseContractGenerator` |
| 7 | Вся реализация, включая сгенерированный код, — на Ruby | `CLAUDE.md` |
| 8 | Файл переопределений (`overrides.yml`) с фиксированными ключами — общий механизм, не привязка к провайдеру | `schemas/overrides.schema.json`, `docs/IR_CONTRACT.md §2.11` |

## 2. Допущения с дефолтами (вопросы заданы, ответов нет)

| # | Допущение | Дефолт | Где меняется |
|---|---|---|---|
| 1 | Поля `Operation` платформы | `id`, `amount` (рубли, major units), `currency`, `provider_operation_id`, `payout_requisite` — один хеш с ключом по способу выплаты (`dig('sbp', 'phone')`), плоских полей нет | `canonical_contract.yml → operation.accessors`, `operation.requisite_access` |
| 2 | Возврат `create_request` | `success(provider_operation_id: body['id'], status: STATUS_MAP.fetch(body['status'], 'in_progress'), response: body)`; 409 с success-схемой — тем же путём (`idempotent_success`) | шаблон `service.rb.erb` (`parse_create_response`), `errors.yml → http."409"` |
| 3 | Аргументы `failure` | Первый — только символы из эталона (`:unauthorized`, `:too_many_requests`, `:unprocessable_entity`) плюс `:provider_error` для остального; второй — i18n-ключ `provider.<canonical>`; третий — именованные детали `provider_code:`, `retry_after:` (допущение 19) | `canonical_contract.yml → error_codes`, `TemplateData::ServiceHelpers#provider_error_method` |
| 4 | `check_conditions` | Сначала `super`; при `failed?` — возвращаем результат базового; порог суммы — из `minimum` с учётом единиц; условно обязательные реквизиты проверяются здесь | шаблон `service.rb.erb`, `fields.yml → money_units`, `conditional_required` |
| 5 | Методы вне контракта | Публичные `cancel_request`, `fetch_balance`, `refund_request`, `list_requests` с комментарием «вне контракта BaseService», отдельная секция INTEGRATION.md | `canonical_contract.yml → extra_methods` |
| 6 | `client` не ретраит и не бросает исключений сам | Сервис маппит 429/401 в `Provider::RateLimitError`/`Provider::UnauthorizedError` и ловит их `rescue`, как в эталоне; `Retry-After` читается из заголовка ответа | `canonical_contract.yml → helpers.exceptions`, `errors.yml → retry_after` |
| 7 | `amount_limit_exceeded` | `terminal_reject` с пометкой «возможен суточный лимит провайдера — проверить договор» | `errors.yml → provider_codes[amount_limit]`, переопределяется `overrides.yml → error_actions` |
| 8 | Единицы суммы, когда сигналов нет | Множитель 1 (`identity`) + `TODO(confidence …)` + W401; порог `minor_threshold: 3` | `fields.yml → money_units` |
| 9 | Кодировка и канонизация подписи, когда спека молчит | `HMAC-SHA256(raw_body, credentials[:callback_secret])` → hex, сравнение `secure_compare`; всегда W301 + I301 | `canonical_contract.yml → signature_defaults` |
| 10 | Статус без маппинга | `in_progress` + W201 + TODO; числовые статусы без описания — по типичной конвенции (`0/1/2`) с уверенностью 0.5 | `statuses.yml → default, numeric` |
| 11 | ProviderGateway config | `external_method: <method>_payout`, `gateway: <CUR>_<METHOD>_WITHDRAW` (для депозитов `_deposit` / `_DEPOSIT`) | `canonical_contract.yml → gateway_config` |
| 12 | Направление операции при отсутствии ключевых слов | `withdraw` (выплата) с пониженной уверенностью | `operations.yml → direction.default` |
| 13 | Slug провайдера в IR | Первое слово `info.title` в нижнем регистре; CLI `--provider` задаёт имя класса и файлов, но не меняет IR | `docs/IR_CONTRACT.md → Provider` |
| 14 | Ответ вебхука | Первый 2xx ответ операции-вебхука; если не объявлен — сервис не формирует HTTP-ответ (платформа отвечает сама) | `docs/IR_CONTRACT.md → Webhook.response` |
| 15 | Порог уверенности | ≥ 0.75 — код без TODO; 0.4–0.75 — код + `TODO(confidence …)` + warning; < 0.4 — заглушка `NotImplementedError` + запись в отчёт; подпись с неизвестной кодировкой/канонизацией — не выше 0.6 | `Generator::Confidence` (константы порогов), `operations.yml → thresholds` |
| 16 | Тело `application/x-www-form-urlencoded` | `client.post(url, form: payload, headers:)` — именованный аргумент `form` по аналогии с `json` (у платформы такого хелпера может не быть) | `canonical_contract.yml → helpers.client.post_form, content_types` |
| 17 | Коды, которые сервис возвращает сам (`unknown_event`, `amount_too_low`, `missing_requisite`, `invalid_signature`, …) | Символ и i18n-ключ как в эталоне: `failure(:unprocessable_entity, 'unknown_event')`; для подписи — `:unauthorized` | `canonical_contract.yml → service_codes` |
| 18 | Идентификатор мерчанта в теле запроса (`merchant_id`, `shop_id`, `terminal_id`) | Берётся из `credentials[:merchant_id]` | `fields.yml → canonical.merchant_account`, `canonical_contract.yml → credentials.merchant_account` |
| 19 | `success`/`failure` принимают именованные детали | `success(provider_operation_id:, status:, response:)`, `failure(<символ>, <код>, provider_code:, retry_after:)`; `approve_operation(id)`, `reject_operation(id, error_code)`; `Result#failed?`, `#status`, `#provider_operation_id`, `#response` | `templates/base_contract.rb.erb`, `TemplateData::ServiceHelpers` |
| 20 | Возврат `fetch_status` | `Result` (`success(status:, response:)`), а не строка статуса, как в эталоне; `map_status(value)` остаётся приватным хелпером с тем же именем | `TemplateData::StatusMethod` |
| 21 | `callback_url` / `redirect_url` / OAuth2 `token_url` в теле или конфиге | ENV-константы `<SLUG>_CALLBACK_URL`, `<SLUG>_REDIRECT_URL`, `<SLUG>_TOKEN_URL` (дефолт токена — из `securitySchemes`) | `canonical_contract.yml → env`, `TemplateData::ServiceConstants` |
| 22 | Стиль сгенерированного Ruby | RuboCop в памяти (stdin API) с `templates/rubocop_generated.yml`: одинарные кавычки, табличные rockets, `STATUS_MAP`/`ERROR_MAP` после `private`, как в эталоне | `Generator::RubyFormatter` |

## 3. Что не выводится из спеки и всегда требует подтверждения

Единицы суммы, условная обязательность реквизитов, кодировка/канонизация подписи, статус-маппинг — даже при высокой
уверенности попадают в `generation_report.json`, в раздел INTEGRATION.md «Требует подтверждения» и в вывод CLI как
`info` с перечислением сигналов (события I201, I301, I401, I402).
