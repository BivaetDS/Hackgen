# NovaPay Integration Guide

Сгенерировано provider-integrator 0.1.0 из «NovaPay Payout API» 1.0.0 (OpenAPI 3.0.3). Сервис: `Provider::NovapayService` (`novapay_service.rb`), контракт `Provider::BaseService`.

## Авторизация

- Тип: api_key (`ApiKeyAuth`)
- Header: `X-API-Key: <credentials.api_key>`
- Хранение: `providers.credentials` (encrypted), ключи: `api_key`, `callback_secret`
- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется подписью (см. «Webhook signature»)
- Evidence: securitySchemes.ApiKeyAuth: apiKey in header X-API-Key; security: ApiKeyAuth used by 4 of 5 operations

## Настройка

| Параметр | Откуда | Значение по умолчанию / назначение |
|---|---|---|
| `NOVAPAY_BASE_URL` | ENV | `https://api.sandbox.novapay.example/v1` (sandbox) |
| servers (production) | спека | `https://api.novapay.example/v1` |
| `credentials[:api_key]` | providers.credentials | авторизация запросов (ApiKeyAuth) |
| `credentials[:callback_secret]` | providers.credentials | секрет подписи webhook |

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|---|---|---|---|
| create_request | POST /payouts | Создать выплату | Idempotency-Key header |
| fetch_status | GET /payouts/{payout_id} | Получить статус выплаты | - |
| process_callback | POST /webhooks/payout | Webhook уведомление о смене статуса | X-NovaPay-Signature |
| check_conditions | - | предпроверки: `super`, сумма >= 1000, реквизиты способа выплаты (`REQUIRED_REQUISITES`) | - |

## Методы вне контракта

| Метод | Endpoint | Назначение | Kind | Уверенность |
|---|---|---|---|---|
| cancel_request | POST /payouts/{payout_id}/cancel | Отменить выплату | cancel | 0.9 |
| fetch_balance | GET /balance | Баланс провайдера | balance | 0.9 |

Публичные методы сервиса вне `Provider::BaseService`; платформа вызывает их по своему усмотрению.

## Способы выплаты (request_method)

- Значения: `sbp` (по умолчанию), `card` - из enum поля `recipient.type` (уверенность 0.9)
- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`
- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет реквизиты из `REQUIRED_REQUISITES`

## Маппинг полей

### Запрос create_request (request_method `sbp`)

`POST /payouts application/json CreatePayoutRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма в копейках |
| currency | константа `'RUB'` | да | - |
| external_id | `operation.id` | да | ID операции на стороне мерчанта |
| recipient.type | константа `'sbp'` (ветка request_method) | да | enum: sbp, card |
| recipient.phone | `operation.payout_requisite['sbp']['phone']` | да | pattern `^7\d{10}$`; Телефон получателя (11 цифр, начинается с 7) |
| recipient.bank_code | `operation.payout_requisite['sbp']['bank_code']` | при recipient.type = sbp | БИК банка (обязателен для type=sbp) |
| recipient.bank_name | `operation.payout_requisite['sbp']['bank_name']` | нет | - |

### Запрос create_request (request_method `card`)

`POST /payouts application/json CreatePayoutRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма в копейках |
| currency | константа `'RUB'` | да | - |
| external_id | `operation.id` | да | ID операции на стороне мерчанта |
| recipient.type | константа `'card'` (ветка request_method) | да | enum: sbp, card |
| recipient.phone | `operation.payout_requisite['card']['phone']` | да | pattern `^7\d{10}$`; Телефон получателя (11 цифр, начинается с 7) |
| recipient.bank_name | `operation.payout_requisite['card']['bank_name']` | нет | - |
| recipient.card_number | `operation.payout_requisite['card']['card_number']` | при recipient.type = card | Номер карты (обязателен для type=card) |

### Ответ create_request (201/409) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| id | provider_operation_id | string | сохраняется как provider_operation_id |
| external_id | external_id | string | - |
| status | status | string | см. «Маппинг статусов» |
| amount | amount | integer | - |
| currency | currency | string | - |
| recipient | requisite | object | - |
| recipient.type | requisite.type | string | enum: sbp, card |
| recipient.phone | requisite.phone | string | Телефон получателя (11 цифр, начинается с 7) |
| recipient.bank_code | requisite.bank_code | string | БИК банка (обязателен для type=sbp) |
| recipient.bank_name | requisite.bank_name | string | - |
| recipient.card_number | requisite.card_number | string | Номер карты (обязателен для type=card) |
| error | error | object | - |
| error.code | error.code | string | enum: validation_error, insufficient_balance, recipient_not_found, bank_unavailable, amount_limit_exceeded, rate_limit_exceeded, internal_error |
| error.message | error.message | string | - |
| created_at | created_at | string | - |
| completed_at | completed_at | string | - |

### Ответ fetch_status (200) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| id | provider_operation_id | string | сохраняется как provider_operation_id |
| external_id | external_id | string | - |
| status | status | string | см. «Маппинг статусов» |
| amount | amount | integer | - |
| currency | currency | string | - |
| recipient | requisite | object | - |
| recipient.type | requisite.type | string | enum: sbp, card |
| recipient.phone | requisite.phone | string | Телефон получателя (11 цифр, начинается с 7) |
| recipient.bank_code | requisite.bank_code | string | БИК банка (обязателен для type=sbp) |
| recipient.bank_name | requisite.bank_name | string | - |
| recipient.card_number | requisite.card_number | string | Номер карты (обязателен для type=card) |
| error | error | object | - |
| error.code | error.code | string | enum: validation_error, insufficient_balance, recipient_not_found, bank_unavailable, amount_limit_exceeded, rate_limit_exceeded, internal_error |
| error.message | error.message | string | - |
| created_at | created_at | string | - |
| completed_at | completed_at | string | - |

## Маппинг статусов

| Provider | Space Payments | Основание |
|---|---|---|
| pending | in_progress | statuses.yml: pending -> in_progress (уверенность 0.95) |
| processing | in_progress | statuses.yml: processing -> in_progress (уверенность 0.95) |
| completed | approved | statuses.yml: completed -> approved (уверенность 0.95) |
| failed | rejected | statuses.yml: failed -> rejected (уверенность 0.95) |
| cancelled | rejected | statuses.yml: cancelled -> rejected (уверенность 0.95) |

Неизвестный статус -> `in_progress` до следующего уведомления (`map_status`).

## Обработка ошибок

| HTTP | Provider code | Канон | Действие | Примечание |
|---|---|---|---|---|
| 400 | validation_error | validation_error | reject | - |
| 401 | unauthorized | invalid_credentials | alert ops, block provider | - |
| 402 | insufficient_balance | insufficient_balance | retry later | - |
| 404 | not_found | not_found | check status, do not retry blindly | - |
| 409 | invalid_status | conflict | reject, check status | - |
| 422 | validation_error | validation_error | reject | - |
| 429 | rate_limit_exceeded | rate_limit | retry with backoff | Retry-After из заголовка |
| 500 | internal_error | internal_error | retry, alert ops | - |

- 409 на `POST /payouts` - идемпотентный дубль: провайдер возвращает исходную выплату, сервис считает это успехом.
- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).
- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными аргументами (docs/ASSUMPTIONS.md).

## ProviderGateway config

```json
{ "external_method": "sbp_payout", "gateway": "RUB_SBP_WITHDRAW" }
```

- Направление: withdraw, валюта: RUB, способ: sbp (уверенность 0.9)
- Evidence: currency: RUB (enum constant); request method: sbp (default of recipient.type); direction: withdraw (token 'payout' in operationId createPayout)

## Webhook signature

HMAC-SHA256(body, callback_secret) -> hex -> X-NovaPay-Signature (header)

- Endpoint провайдера: `POST /webhooks/payout` (payoutWebhook); найден: path_heuristic (уверенность 0.92)
- Evidence подписи: parameter X-NovaPay-Signature (header): HMAC-SHA256 подпись тела запроса; operation description: Подпись передаётся в заголовке X-NovaPay-Signature (HMAC-SHA256)
- Кодировка и канонизация **не указаны в спеке (W301)**: приняты дефолты канона
- Сравнение подписи в постоянное время (`secure_compare`); секрет - `credentials[:callback_secret]`

- Payload для `process_callback`: разобранный JSON уведомления либо конверт `{ 'body' => <JSON>, 'headers' => { '<Signature-Header>' => ... }, 'raw_body' => '<сырое тело>' }`
- Без `raw_body` подпись проверяется по `JSON.generate(body)` - ненадёжно при иной сериализации у провайдера
- Поля payload: событие `event`, статус `status`, id операции `payout_id`, код ошибки `error.code`

| Событие | Статус Space Payments | Действие сервиса |
|---|---|---|
| payout.completed | approved | `approve_operation` |
| payout.failed | rejected | `reject_operation` с кодом ошибки |
| payout.processing | in_progress | `success(status: 'in_progress')` |
| payout.cancelled | rejected | `reject_operation` с кодом ошибки |

- Ответ провайдеру: HTTP 200 `{"received":true}` (формирует платформа после `process_callback`)

## Тесты

`novapay_service_spec.rb` - RSpec поверх `fixtures.json` через WebMock (сеть не нужна), 20 примеров:

- `create_request` (10): запрос (URL, заголовки, тело), успех 201, дубль 409, ошибки 400, 401, 402, 422, 429, 500, неизвестный request_method
- `fetch_status` (3): запрос с авторизацией, статус из response_200, ошибки 401, 404
- `process_callback` (3): callback -> approved, callback_failed -> rejected, подделанная подпись
- `check_conditions` (4): валидная операция, `MIN_AMOUNT`, `REQUIRED_REQUISITES`, `REQUEST_METHODS`

- Запуск из каталога с файлами: `rspec novapay_service_spec.rb` (гемы `rspec`, `webmock`); то же делает `bin/integrate --run-spec` сразу после генерации
- `base_contract.rb` (`Provider::BaseService`, `Provider::HttpClient` на Net::HTTP) - заглушки для автономного прогона (docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие `BaseService` и `client`
- Подпись webhook в тестах считается тем же выражением, что в `verify_signature!` (HMAC-SHA256, hex); секрет - `credentials[:callback_secret]`

## Требует подтверждения

Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: `overrides.yml` (ключи operations, amount_unit, required_if, signature, status_map, error_actions).

| Код | Уровень | Вывод | Основание | Где в коде |
|---|---|---|---|---|
| W301 | warning | HMAC canonicalization for X-NovaPay-Signature is not specified (encoding unknown, message raw_body); the generator assumes hex digest over raw_body | см. вывод | verify_signature! |
| W402 | warning | Conditional requirement inferred from description: recipient.bank_code is required when recipient.type equals sbp (createPayout) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: recipient.card_number is required when recipient.type equals card (createPayout) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I201 | info | Status mapping recorded (5 statuses): pending -> in_progress, processing -> in_progress, completed -> approved, failed -> rejected, cancelled -> rejected | см. вывод | STATUS_MAP |
| I301 | info | Signature convention recorded: X-NovaPay-Signature (header), algorithm hmac-sha256, encoding unknown, message raw_body, secret callback_secret | см. вывод | verify_signature! |
| I401 | info | Amount field amount in createPayout uses minor units (multiplier 100, score 8); signals: description: копейках, error example (422): kopecks, minimum: 100000 | description: копейках; error example (422): kopecks; minimum: 100000 | build_*_payload, MIN_AMOUNT |
| I403 | info | Gateway config recorded: external_method sbp_payout, gateway RUB_SBP_WITHDRAW (confidence 0.9); evidence: currency: RUB (enum constant), request method: sbp (default of recipient.type), direction: withdraw (token 'payout' in operationId createPayout) | currency: RUB (enum constant); request method: sbp (default of recipient.type); direction: withdraw (token 'payout' in operationId createPayout) | ProviderGateway config |

## Допущения

Реальный `Provider::BaseService` не предоставлен; сервис написан под контракт, реконструированный по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):

- `operation.amount` в основных единицах валюты; реквизиты - `operation.payout_requisite` одним хешем с ключом по способу выплаты
- `success(**details)` / `failure(<символ>, <i18n-код>, **details)`; символы: :unprocessable_entity, :unauthorized, :provider_error, :too_many_requests
- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не бросает исключений сам; Provider::RateLimitError и Provider::UnauthorizedError перехватываются на случай, если бросает
- `approve_operation(id)` / `reject_operation(id, error_code)` завершают операцию на платформе
- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех
