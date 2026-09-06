# Tranzo Integration Guide

Сгенерировано provider-integrator 0.1.0 из «Tranzo Disbursement API» 2.4.1 (OpenAPI 3.0.3). Сервис: `Provider::TranzoService` (`tranzo_service.rb`), контракт `Provider::BaseService`.

## Авторизация

- Тип: oauth2_client_credentials (`MerchantOAuth2`)
- Header: `Authorization: Bearer <access_token>`; токен по client credentials с `TOKEN_URL` (https://auth.tranzo.example/oauth2/token, scopes: disbursements:write disbursements:read merchant:read)
- Хранение: `providers.credentials` (encrypted), ключи: `client_id`, `client_secret`, `callback_secret`
- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется подписью (см. «Webhook signature»)
- Evidence: securitySchemes.MerchantOAuth2: oauth2 in header Authorization (clientCredentials https://auth.tranzo.example/oauth2/token); security: MerchantOAuth2 used by 6 of 6 operations

## Настройка

| Параметр | Откуда | Значение по умолчанию / назначение |
|---|---|---|
| `TRANZO_BASE_URL` | ENV | `https://api.sandbox.tranzo.example/disbursement/v2` (sandbox) |
| servers (production) | спека | `https://api.tranzo.example/disbursement/v2` |
| `TRANZO_TOKEN_URL` | ENV | `https://auth.tranzo.example/oauth2/token` |
| `TRANZO_CALLBACK_URL` | ENV | отправляется в теле запроса как callback_url |
| `credentials[:client_id]` | providers.credentials | авторизация запросов (MerchantOAuth2) |
| `credentials[:client_secret]` | providers.credentials | авторизация запросов (MerchantOAuth2) |
| `credentials[:callback_secret]` | providers.credentials | секрет подписи webhook |

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|---|---|---|---|
| create_request | POST /disbursements | Зарегистрировать выплату | X-Request-Id header |
| fetch_status | GET /disbursements/{operationId} | Получить текущее состояние выплаты | - |
| process_callback | POST {$request.body#/callbackUrl} | Уведомление о смене состояния выплаты | sign |
| check_conditions | - | предпроверки: `super`, сумма >= 500, сумма <= 3000000, реквизиты способа выплаты (`REQUIRED_REQUISITES`) | - |

## Методы вне контракта

| Метод | Endpoint | Назначение | Kind | Уверенность |
|---|---|---|---|---|
| list_requests | GET /disbursements | Реестр выплат за период | list | 0.9 |
| cancel_request | POST /disbursements/{operationId}/revoke | Отозвать выплату | cancel | 0.89 |
| quote_disbursement_fee | POST /fees/quote | Предварительный расчёт комиссии | unknown | 0.0 |
| fetch_balance | GET /merchant/balance | Баланс мерчанта | balance | 0.9 |

Публичные методы сервиса вне `Provider::BaseService`; платформа вызывает их по своему усмотрению.

## Способы выплаты (request_method)

- Значения: `phone` (по умолчанию), `card`, `account` - из enum поля `destination.kind` (уверенность 0.9)
- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`
- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет реквизиты из `REQUIRED_REQUISITES`

## Маппинг полей

### Запрос create_request (request_method `phone`)

`POST /disbursements application/json DisbursementRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchantReference | `operation.id` | да | pattern `^[A-Za-z0-9._-]{4,48}$`; Идентификатор выплаты в учётной системе мерчанта, уникален 24 часа |
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках (для KZT — в тийинах), без комиссии |
| currency | `operation.currency` | да | enum: RUB, KZT; Валюта выплаты, ISO 4217 |
| destination.kind | константа `'phone'` (ветка request_method) | да | enum: phone, card, account; Способ зачисления средств |
| destination.phone | `operation.payout_requisite['phone']['phone']` | при destination.kind = phone | pattern `^\+7\d{10}$`; Телефон получателя в формате E.164. Обязательно, если kind = phone |
| destination.holderName | `operation.payout_requisite['phone']['name']` | нет | ФИО получателя, как в документах банка |
| callbackUrl | ENV `TRANZO_CALLBACK_URL` | да | HTTPS-адрес мерчанта для уведомлений о смене состояния |
| comment | не отправляется: нет источника на платформе | нет | Назначение выплаты, попадает в выписку получателя |

### Запрос create_request (request_method `card`)

`POST /disbursements application/json DisbursementRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchantReference | `operation.id` | да | pattern `^[A-Za-z0-9._-]{4,48}$`; Идентификатор выплаты в учётной системе мерчанта, уникален 24 часа |
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках (для KZT — в тийинах), без комиссии |
| currency | `operation.currency` | да | enum: RUB, KZT; Валюта выплаты, ISO 4217 |
| destination.kind | константа `'card'` (ветка request_method) | да | enum: phone, card, account; Способ зачисления средств |
| destination.cardNumber | `operation.payout_requisite['card']['card_number']` | при destination.kind = card | pattern `^\d{16,19}$`; Номер карты получателя, 16-19 цифр. Обязательно, если kind = card |
| destination.holderName | `operation.payout_requisite['card']['name']` | нет | ФИО получателя, как в документах банка |
| callbackUrl | ENV `TRANZO_CALLBACK_URL` | да | HTTPS-адрес мерчанта для уведомлений о смене состояния |
| comment | не отправляется: нет источника на платформе | нет | Назначение выплаты, попадает в выписку получателя |

### Запрос create_request (request_method `account`)

`POST /disbursements application/json DisbursementRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchantReference | `operation.id` | да | pattern `^[A-Za-z0-9._-]{4,48}$`; Идентификатор выплаты в учётной системе мерчанта, уникален 24 часа |
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках (для KZT — в тийинах), без комиссии |
| currency | `operation.currency` | да | enum: RUB, KZT; Валюта выплаты, ISO 4217 |
| destination.kind | константа `'account'` (ветка request_method) | да | enum: phone, card, account; Способ зачисления средств |
| destination.accountNumber | `operation.payout_requisite['account']['account_number']` | при destination.kind = account | pattern `^\d{20}$`; Номер расчётного счёта, 20 цифр. Обязательно, если kind = account |
| destination.bic | `operation.payout_requisite['account']['bank_code']` | при destination.kind = account | pattern `^\d{9}$`; БИК банка получателя. Обязательно, если kind = account |
| destination.holderName | `operation.payout_requisite['account']['name']` | нет | ФИО получателя, как в документах банка |
| callbackUrl | ENV `TRANZO_CALLBACK_URL` | да | HTTPS-адрес мерчанта для уведомлений о смене состояния |
| comment | не отправляется: нет источника на платформе | нет | Назначение выплаты, попадает в выписку получателя |

### Ответ create_request (202) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| operationId | provider_operation_id | string | сохраняется как provider_operation_id |
| merchantReference | external_id | string | Идентификатор выплаты в учётной системе мерчанта |
| state | status | integer | см. «Маппинг статусов» |
| amount | amount | integer | Сумма выплаты в копейках |
| currency | currency | string | - |
| fee | fee | integer | Комиссия Tranzo в копейках, списывается сверх суммы выплаты |
| destination | requisite | object | Реквизиты получателя. Набор полей зависит от значения kind. |
| destination.kind | requisite.type | string | enum: phone, card, account |
| destination.phone | requisite.phone | string | Телефон получателя в формате E.164. Обязательно, если kind = phone |
| destination.cardNumber | requisite.card_number | string | Номер карты получателя, 16-19 цифр. Обязательно, если kind = card |
| destination.accountNumber | requisite.account_number | string | Номер расчётного счёта, 20 цифр. Обязательно, если kind = account |
| destination.bic | requisite.bank_code | string | БИК банка получателя. Обязательно, если kind = account |
| destination.holderName | requisite.name | string | ФИО получателя, как в документах банка |
| declineReason | - | string | Причина отказа простым текстом, заполняется для состояний 2 и 4 |
| createdAt | created_at | string | - |
| updatedAt | updated_at | string | - |

### Ответ fetch_status (200) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| operationId | provider_operation_id | string | сохраняется как provider_operation_id |
| merchantReference | external_id | string | Идентификатор выплаты в учётной системе мерчанта |
| state | status | integer | см. «Маппинг статусов» |
| amount | amount | integer | Сумма выплаты в копейках |
| currency | currency | string | - |
| fee | fee | integer | Комиссия Tranzo в копейках, списывается сверх суммы выплаты |
| destination | requisite | object | Реквизиты получателя. Набор полей зависит от значения kind. |
| destination.kind | requisite.type | string | enum: phone, card, account |
| destination.phone | requisite.phone | string | Телефон получателя в формате E.164. Обязательно, если kind = phone |
| destination.cardNumber | requisite.card_number | string | Номер карты получателя, 16-19 цифр. Обязательно, если kind = card |
| destination.accountNumber | requisite.account_number | string | Номер расчётного счёта, 20 цифр. Обязательно, если kind = account |
| destination.bic | requisite.bank_code | string | БИК банка получателя. Обязательно, если kind = account |
| destination.holderName | requisite.name | string | ФИО получателя, как в документах банка |
| declineReason | - | string | Причина отказа простым текстом, заполняется для состояний 2 и 4 |
| createdAt | created_at | string | - |
| updatedAt | updated_at | string | - |

### Запрос quote_disbursement_fee

`POST /fees/quote`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках |
| currency | `operation.currency` | да | enum: RUB, KZT |
| method | `request_method` | да | enum: phone, card, account; Способ зачисления, как в поле destination.kind |

## Маппинг статусов

| Provider | Space Payments | Основание |
|---|---|---|
| 0 | in_progress | description: 0 — в обработке (уверенность 0.7) |
| 1 | approved | description: 1 — успешно исполнена (уверенность 0.7) |
| 2 | rejected | description: 2 — отклонена банком получателя (уверенность 0.7) |
| 3 | rejected | description: 3 — отменена мерчантом (уверенность 0.7) |
| 4 | rejected | description: 4 — просрочена (уверенность 0.7) |
| -1 | rejected | statuses.yml numeric: -1 -> rejected (уверенность 0.5) |

Неизвестный статус -> `in_progress` до следующего уведомления (`map_status`).

## Обработка ошибок

| HTTP | Provider code | Канон | Действие | Примечание |
|---|---|---|---|---|
| 400 | REQ_MALFORMED_BODY | validation_error | reject | - |
| 401 | SEC_TOKEN_EXPIRED | invalid_credentials | alert ops, block provider | - |
| 402 | BAL_NOT_ENOUGH_FUNDS | insufficient_balance | retry later | - |
| 403 | SEC_INSUFFICIENT_SCOPE | invalid_credentials | alert ops, block provider | - |
| 404 | OPR_NOT_FOUND | not_found | check status, do not retry blindly | - |
| 409 | REQ_DUPLICATE_REFERENCE | conflict | reject, check status | - |
| 422 | VAL_AMOUNT_OVER_LIMIT | validation_error | reject | возможен суточный/разовый лимит провайдера — проверить договор (PLAN §4, допущение 7) |
| 429 | RATE_TOO_MANY_REQUESTS | rate_limit | retry with backoff | Retry-After из тела ответа |
| 500 | SYS_INTERNAL_FAILURE | internal_error | retry, alert ops | - |
| 503 | SYS_MAINTENANCE | internal_error | retry later | - |

- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).
- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными аргументами (docs/ASSUMPTIONS.md).

## ProviderGateway config

```json
{ "external_method": "phone_payout", "gateway": "RUB_PHONE_WITHDRAW" }
```

- Направление: withdraw, валюта: RUB, способ: phone (уверенность 0.6)
- Evidence: currency: RUB (example); request method: phone (default of destination.kind); direction: withdraw (token 'disbursement' in operationId registerDisbursement)

## Webhook signature

HMAC-SHA512(sorted_values(payload), callback_secret) -> hex -> sign (body)

- Endpoint провайдера: `POST {$request.body#/callbackUrl}` (disbursementStateCallback); найден: callbacks (уверенность 1.0)
- Evidence подписи: field sign: Подпись уведомления: HMAC-SHA512 в нижнем регистре hex от concatenation; operation description: sign = HMAC-SHA512 в нижнем регистре hex от concatenation значений
- Кодировка и канонизация из спеки
- Сравнение подписи в постоянное время (`secure_compare`); секрет - `credentials[:callback_secret]`

- Payload для `process_callback`: разобранный JSON уведомления либо конверт `{ 'body' => <JSON>, 'headers' => { '<Signature-Header>' => ... }, 'raw_body' => '<сырое тело>' }`
- Без `raw_body` подпись проверяется по `JSON.generate(body)` - ненадёжно при иной сериализации у провайдера
- Поля payload: событие `event`, статус `state`, id операции `operationId`, код ошибки `errorCode`

| Событие | Статус Space Payments | Действие сервиса |
|---|---|---|
| disbursement.executed | approved | `approve_operation` |
| disbursement.declined | rejected | `reject_operation` с кодом ошибки |
| disbursement.revoked | - | `unknown_event` (W203) |
| disbursement.expired | rejected | `reject_operation` с кодом ошибки |
| disbursement.failed | rejected | `reject_operation` с кодом ошибки |

- Ответ провайдеру: HTTP 200 `{"result":"ok"}` (формирует платформа после `process_callback`)

## Тесты

`tranzo_service_spec.rb` - RSpec поверх `fixtures.json` через WebMock (сеть не нужна), 23 примеров:

- `create_request` (11): запрос (URL, заголовки, тело), успех 202, ошибки 400, 401, 402, 409, 422, 429, 500, 503, неизвестный request_method
- `fetch_status` (4): запрос с авторизацией, статус из response_200, ошибки 401, 404, 429
- `process_callback` (3): callback -> approved, callback_failed -> rejected, подделанная подпись
- `check_conditions` (5): валидная операция, `MIN_AMOUNT`, `MAX_AMOUNT`, `REQUIRED_REQUISITES`, `REQUEST_METHODS`

- Запуск из каталога с файлами: `rspec tranzo_service_spec.rb` (гемы `rspec`, `webmock`); то же делает `bin/integrate --run-spec` сразу после генерации
- `base_contract.rb` (`Provider::BaseService`, `Provider::HttpClient` на Net::HTTP) - заглушки для автономного прогона (docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие `BaseService` и `client`
- Подпись webhook в тестах считается тем же выражением, что в `verify_signature!` (HMAC-SHA512, hex); секрет - `credentials[:callback_secret]`

## Требует подтверждения

Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: `overrides.yml` (ключи operations, amount_unit, required_if, signature, status_map, error_actions).

| Код | Уровень | Вывод | Основание | Где в коде |
|---|---|---|---|---|
| W101 | warning | Operation quoteDisbursementFee (POST /fees/quote) classified as unknown with low confidence 0.0 | см. вывод | operation methods (name and role) |
| W202 | warning | Provider error code OPR_STATE_LOCKED (HTTP 409) has no canonical analog; defaulting to conflict | см. вывод | ERROR_MAP |
| W203 | warning | Webhook event disbursement.revoked has no canonical status; the service treats it as unknown_event | см. вывод | process_callback (unknown_event) |
| W204 | warning | Numeric status -1 mapped by convention to rejected; confirm with the provider | см. вывод | STATUS_MAP |
| W402 | warning | Conditional requirement inferred from description: destination.accountNumber is required when destination.kind equals account (registerDisbursement) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: destination.bic is required when destination.kind equals account (registerDisbursement) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: destination.cardNumber is required when destination.kind equals card (registerDisbursement) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: destination.phone is required when destination.kind equals phone (registerDisbursement) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W403 | warning | Required request field sign in disbursementStateCallback is not mapped to any canonical field | см. вывод | build_*_payload (TODO) |
| I201 | info | Status mapping recorded (6 statuses): 0 -> in_progress, 1 -> approved, 2 -> rejected, 3 -> rejected, 4 -> rejected, -1 -> rejected | см. вывод | STATUS_MAP |
| I301 | info | Signature convention recorded: sign (body), algorithm hmac-sha512, encoding hex, message concatenated_fields, secret callback_secret | см. вывод | verify_signature! |
| I401 | info | Amount field amount in registerDisbursement uses minor units (multiplier 100, score 8); signals: description: копейках, error example (422): копеек, minimum: 50000 | description: копейках; error example (422): копеек; minimum: 50000 | build_*_payload, MIN_AMOUNT |
| I403 | info | Gateway config recorded: external_method phone_payout, gateway RUB_PHONE_WITHDRAW (confidence 0.6); evidence: currency: RUB (example), request method: phone (default of destination.kind), direction: withdraw (token 'disbursement' in operationId registerDisbursement) | currency: RUB (example); request method: phone (default of destination.kind); direction: withdraw (token 'disbursement' in operationId registerDisbursement) | ProviderGateway config |

## Допущения

Реальный `Provider::BaseService` не предоставлен; сервис написан под контракт, реконструированный по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):

- `operation.amount` в основных единицах валюты; реквизиты - `operation.payout_requisite` одним хешем с ключом по способу выплаты
- `success(**details)` / `failure(<символ>, <i18n-код>, **details)`; символы: :unprocessable_entity, :unauthorized, :provider_error, :too_many_requests
- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не бросает исключений сам; Provider::RateLimitError и Provider::UnauthorizedError перехватываются на случай, если бросает
- `approve_operation(id)` / `reject_operation(id, error_code)` завершают операцию на платформе
- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех
