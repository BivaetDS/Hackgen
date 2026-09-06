# CardPay Integration Guide

Сгенерировано provider-integrator 0.1.0 из «CardPay Disbursement API» 2.4.0 (OpenAPI 3.1.0). Сервис: `Provider::CardpayService` (`cardpay_service.rb`), контракт `Provider::BaseService`.

## Авторизация

- Тип: api_key (`CardPayKey`)
- Header: `X-CardPay-Key: <credentials.api_key>`
- Хранение: `providers.credentials` (encrypted), ключи: `api_key`, `callback_secret`
- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется подписью (см. «Webhook signature»)
- Evidence: securitySchemes.CardPayKey: apiKey in header X-CardPay-Key; security: CardPayKey used by 6 of 7 operations

## Настройка

| Параметр | Откуда | Значение по умолчанию / назначение |
|---|---|---|
| `CARDPAY_BASE_URL` | ENV | `https://api.sandbox.cardpay.example` (sandbox) |
| servers (production) | спека | `https://api.cardpay.example` |
| `CARDPAY_CALLBACK_URL` | ENV | отправляется в теле запроса как callback_url |
| `credentials[:api_key]` | providers.credentials | авторизация запросов (CardPayKey) |
| `credentials[:callback_secret]` | providers.credentials | секрет подписи webhook |

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|---|---|---|---|
| create_request | POST /v2/disbursements/card | Создать выплату на банковскую карту | X-Request-Id header |
| fetch_status | GET /v2/disbursements/{disbursement_id} | Получить текущее состояние выплаты | - |
| process_callback | POST /v2/notifications/disbursement | Уведомление о смене состояния выплаты | X-CardPay-Signature |
| check_conditions | - | предпроверки: `super`, сумма >= 500, сумма <= 600000, реквизиты способа выплаты (`REQUIRED_REQUISITES`) | - |

## Методы вне контракта

| Метод | Endpoint | Назначение | Kind | Уверенность |
|---|---|---|---|---|
| create_sbp_disbursement | POST /v2/disbursements/sbp | Создать выплату по СБП | create | 0.9 |
| cancel_request | POST /v2/disbursements/{disbursement_id}/cancel | Отменить выплату | cancel | 0.9 |
| fetch_balance | GET /v2/merchant/balance | Баланс мерчанта | balance | 0.9 |
| list_requests | GET /v2/dictionaries/sbp-members | Справочник банков — участников СБП | list | 0.89 |

Публичные методы сервиса вне `Provider::BaseService`; платформа вызывает их по своему усмотрению.

## Способы выплаты (request_method)

- Значения: `card` (по умолчанию), `card_token` - из enum поля `destination.type` (уверенность 0.9)
- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`
- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет реквизиты из `REQUIRED_REQUISITES`

## Маппинг полей

### Запрос create_request (request_method `card`)

`POST /v2/disbursements/card application/json CardDisbursementRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках, без учёта комиссии CardPay. |
| currency | константа `'RUB'` | да | Валюта операции. CardPay проводит выплаты только в рублях. |
| merchant_reference | `operation.id` | да | Идентификатор операции в системе мерчанта, уникальный в рамках договора. |
| purpose | не отправляется: нет источника на платформе | нет | Назначение выплаты, попадает в выписку банка получателя. |
| notify_url | ENV `CARDPAY_CALLBACK_URL` | нет | Адрес для уведомлений. Если не передан, берётся адрес из настроек мерчанта. |
| destination.type | константа `'card'` (ветка request_method) | да | enum: card, card_token; Способ адресации карты: `card` — по номеру карты, `card_token` — по токену ранее сохранённой карты. |
| destination.card_number | `operation.payout_requisite['card']['card_number']` | при destination.type = card | pattern `^\d{16,19}$`; Номер карты получателя. Обязателен, если type = card. |
| destination.holder_name | `operation.payout_requisite['card']['name']` | нет | Держатель карты латиницей, как указано на карте. |
| destination.expiry | `operation.payout_requisite['card']['expiry']` | нет | pattern `^(0[1-9]|1[0-2])/\d{2}$`; Срок действия карты в формате MM/YY; требуется отдельными банками-эмитентами. |
| customer.phone | не отправляется: нет источника на платформе | нет | Контактный телефон получателя. |
| customer.email | не отправляется: нет источника на платформе | нет | Электронная почта получателя. |
| customer.ip | не отправляется: нет источника на платформе | нет | IP-адрес, с которого получатель подтвердил заявку. |

### Запрос create_request (request_method `card_token`)

`POST /v2/disbursements/card application/json CardDisbursementRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках, без учёта комиссии CardPay. |
| currency | константа `'RUB'` | да | Валюта операции. CardPay проводит выплаты только в рублях. |
| merchant_reference | `operation.id` | да | Идентификатор операции в системе мерчанта, уникальный в рамках договора. |
| purpose | не отправляется: нет источника на платформе | нет | Назначение выплаты, попадает в выписку банка получателя. |
| notify_url | ENV `CARDPAY_CALLBACK_URL` | нет | Адрес для уведомлений. Если не передан, берётся адрес из настроек мерчанта. |
| destination.type | константа `'card_token'` (ветка request_method) | да | enum: card, card_token; Способ адресации карты: `card` — по номеру карты, `card_token` — по токену ранее сохранённой карты. |
| destination.card_token | `operation.payout_requisite['card_token']['card_token']` | при destination.type = card_token | Токен ранее сохранённой карты. Обязателен, если type = card_token. |
| destination.holder_name | `operation.payout_requisite['card_token']['name']` | нет | Держатель карты латиницей, как указано на карте. |
| destination.expiry | `operation.payout_requisite['card_token']['expiry']` | нет | pattern `^(0[1-9]|1[0-2])/\d{2}$`; Срок действия карты в формате MM/YY; требуется отдельными банками-эмитентами. |
| customer.phone | не отправляется: нет источника на платформе | нет | Контактный телефон получателя. |
| customer.email | не отправляется: нет источника на платформе | нет | Электронная почта получателя. |
| customer.ip | не отправляется: нет источника на платформе | нет | IP-адрес, с которого получатель подтвердил заявку. |

### Ответ create_request (202/409) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| disbursement_id | provider_operation_id | string | сохраняется как provider_operation_id |
| merchant_reference | external_id | string | Идентификатор операции в системе мерчанта, как он был передан в запросе. |
| payout_method | requisite.type | string | enum: card, sbp |
| state | status | string | см. «Маппинг статусов» |
| amount | amount | integer | Сумма выплаты в копейках. |
| currency | currency | string | Валюта операции. CardPay проводит выплаты только в рублях. |
| fee | fee | integer | Комиссия CardPay в копейках; известна после исполнения выплаты. |
| failure | error | object | Причина отказа. Равно null, пока выплата не завершилась ошибкой. |
| failure.code | error.code | string | enum: CP_INVALID_CARD, CP_CARD_EXPIRED, CP_MEMBER_NOT_SUPPORTED, CP_LOW_BALANCE, CP_AMOUNT_LIMIT_EXCEEDED, CP_CHANNEL_UNAVAILABLE, CP_INTERNAL_ERROR |
| failure.message | error.message | string | Описание отказа на английском языке. |
| failure.bank_message | error.bank_message | string | Ответ банка получателя как есть; формат не гарантируется. |
| created_at | created_at | string | Момент создания выплаты в UTC. |
| settled_at | completed_at | string | Момент зачисления средств получателю в UTC. |

### Ответ fetch_status (200) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| disbursement_id | provider_operation_id | string | сохраняется как provider_operation_id |
| merchant_reference | external_id | string | Идентификатор операции в системе мерчанта, как он был передан в запросе. |
| payout_method | requisite.type | string | enum: card, sbp |
| state | status | string | см. «Маппинг статусов» |
| amount | amount | integer | Сумма выплаты в копейках. |
| currency | currency | string | Валюта операции. CardPay проводит выплаты только в рублях. |
| fee | fee | integer | Комиссия CardPay в копейках; известна после исполнения выплаты. |
| failure | error | object | Причина отказа. Равно null, пока выплата не завершилась ошибкой. |
| failure.code | error.code | string | enum: CP_INVALID_CARD, CP_CARD_EXPIRED, CP_MEMBER_NOT_SUPPORTED, CP_LOW_BALANCE, CP_AMOUNT_LIMIT_EXCEEDED, CP_CHANNEL_UNAVAILABLE, CP_INTERNAL_ERROR |
| failure.message | error.message | string | Описание отказа на английском языке. |
| failure.bank_message | error.bank_message | string | Ответ банка получателя как есть; формат не гарантируется. |
| created_at | created_at | string | Момент создания выплаты в UTC. |
| settled_at | completed_at | string | Момент зачисления средств получателю в UTC. |

### Запрос create_sbp_disbursement

`POST /v2/disbursements/sbp`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма выплаты в копейках, без учёта комиссии CardPay. |
| currency | константа `'RUB'` | да | Валюта операции. CardPay проводит выплаты только в рублях. |
| merchant_reference | `operation.id` | да | Идентификатор операции в системе мерчанта, уникальный в рамках договора. |
| purpose | не отправляется: нет источника на платформе | нет | Назначение выплаты, попадает в выписку банка получателя. |
| notify_url | ENV `CARDPAY_CALLBACK_URL` | нет | Адрес для уведомлений. Если не передан, берётся адрес из настроек мерчанта. |
| destination.phone | `operation.payout_requisite[request_method]['phone']` | да | pattern `^7\d{10}$`; Телефон получателя, 11 цифр, начинается с 7. |
| destination.member_id | `operation.payout_requisite[request_method]['bank_code']` | да | Идентификатор банка — участника СБП из справочника /v2/dictionaries/sbp-members. |
| destination.member_name | `operation.payout_requisite[request_method]['member_name']` | нет | Название банка. Поле информационное; при расхождении используется member_id. |

## Маппинг статусов

| Provider | Space Payments | Основание |
|---|---|---|
| queued | in_progress | statuses.yml: queued -> in_progress (уверенность 0.95) |
| in_flight | in_progress | default: in_progress (уверенность 0.3) |
| settled | approved | statuses.yml: settled -> approved (уверенность 0.95) |
| returned | rejected | statuses.yml: returned -> rejected (уверенность 0.95) |
| rejected_by_bank | rejected | statuses.yml token: rejected_by_bank -> rejected (уверенность 0.85) |

Неизвестный статус -> `in_progress` до следующего уведомления (`map_status`).

## Обработка ошибок

| HTTP | Provider code | Канон | Действие | Примечание |
|---|---|---|---|---|
| 400 | CP_MALFORMED_REQUEST | validation_error | reject | Retry-After из тела ответа |
| 401 | CP_KEY_REVOKED | invalid_credentials | alert ops, block provider | Retry-After из тела ответа |
| 402 | CP_LOW_BALANCE | insufficient_balance | retry later | Retry-After из тела ответа |
| 404 | CP_DISBURSEMENT_NOT_FOUND | not_found | check status, do not retry blindly | Retry-After из тела ответа |
| 409 | CP_INVALID_STATE | conflict | reject, check status | Retry-After из тела ответа |
| 422 | CP_AMOUNT_LIMIT_EXCEEDED | validation_error | reject | Retry-After из тела ответа; возможен суточный/разовый лимит провайдера — проверить договор (PLAN §4, допущение 7) |
| 429 | CP_REQUEST_LIMIT | rate_limit | retry with backoff | Retry-After из заголовка |
| 500 | CP_INTERNAL_ERROR | internal_error | retry, alert ops | Retry-After из тела ответа |
| 503 | CP_CHANNEL_UNAVAILABLE | internal_error | retry later | Retry-After из тела ответа |

- 409 на `POST /v2/disbursements/card` - идемпотентный дубль: провайдер возвращает исходную выплату, сервис считает это успехом.
- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).
- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными аргументами (docs/ASSUMPTIONS.md).

## ProviderGateway config

```json
{ "external_method": "card_payout", "gateway": "RUB_CARD_WITHDRAW" }
```

- Направление: withdraw, валюта: RUB, способ: card (уверенность 0.9)
- Evidence: currency: RUB (enum constant); request method: card (default of destination.type); direction: withdraw (token 'disbursement' in operationId createCardDisbursement)

## Webhook signature

HMAC-SHA512(body, callback_secret) -> base64 -> X-CardPay-Signature (header)

- Endpoint провайдера: `POST /v2/notifications/disbursement` (disbursementNotification); найден: path_heuristic (уверенность 0.92)
- Evidence подписи: parameter X-CardPay-Signature (header): HMAC-SHA512 от сырого тела запроса на ключе callback_secret, результат в base64; operation description: Уведомление подписано: заголовок `X-CardPay-Signature` содержит HMAC-SHA512 от сырого тела
- Кодировка и канонизация из спеки
- Сравнение подписи в постоянное время (`secure_compare`); секрет - `credentials[:callback_secret]`

- Payload для `process_callback`: разобранный JSON уведомления либо конверт `{ 'body' => <JSON>, 'headers' => { '<Signature-Header>' => ... }, 'raw_body' => '<сырое тело>' }`
- Без `raw_body` подпись проверяется по `JSON.generate(body)` - ненадёжно при иной сериализации у провайдера
- Поля payload: событие `event_type`, статус `state`, id операции `disbursement_id`, код ошибки `failure.code`

| Событие | Статус Space Payments | Действие сервиса |
|---|---|---|
| disbursement.in_flight | - | `unknown_event` (W203) |
| disbursement.settled | approved | `approve_operation` |
| disbursement.returned | rejected | `reject_operation` с кодом ошибки |
| disbursement.rejected_by_bank | rejected | `reject_operation` с кодом ошибки |

- Ответ провайдеру: HTTP 200 `{"accepted":true}` (формирует платформа после `process_callback`)

## Тесты

`cardpay_service_spec.rb` - RSpec поверх `fixtures.json` через WebMock (сеть не нужна), 23 примеров:

- `create_request` (11): запрос (URL, заголовки, тело), успех 202, дубль 409, ошибки 400, 401, 402, 422, 429, 500, 503, неизвестный request_method
- `fetch_status` (4): запрос с авторизацией, статус из response_200, ошибки 401, 404, 429
- `process_callback` (3): callback -> approved, callback_failed -> rejected, подделанная подпись
- `check_conditions` (5): валидная операция, `MIN_AMOUNT`, `MAX_AMOUNT`, `REQUIRED_REQUISITES`, `REQUEST_METHODS`

- Запуск из каталога с файлами: `rspec cardpay_service_spec.rb` (гемы `rspec`, `webmock`); то же делает `bin/integrate --run-spec` сразу после генерации
- `base_contract.rb` (`Provider::BaseService`, `Provider::HttpClient` на Net::HTTP) - заглушки для автономного прогона (docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие `BaseService` и `client`
- Подпись webhook в тестах считается тем же выражением, что в `verify_signature!` (HMAC-SHA512, base64); секрет - `credentials[:callback_secret]`

## Требует подтверждения

Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: `overrides.yml` (ключи operations, amount_unit, required_if, signature, status_map, error_actions).

| Код | Уровень | Вывод | Основание | Где в коде |
|---|---|---|---|---|
| W105 | warning | Several create candidates (createCardDisbursement, createSbpDisbursement); createCardDisbursement chosen, others generated as extra methods | см. вывод | extra methods |
| W201 | warning | Status in_flight has no canonical mapping; defaulting to in_progress | см. вывод | STATUS_MAP |
| W202 | warning | Provider error code CP_KEY_REVOKED (HTTP 401) has no canonical analog; defaulting to invalid_credentials | см. вывод | ERROR_MAP |
| W203 | warning | Webhook event disbursement.in_flight has no canonical status; the service treats it as unknown_event | см. вывод | process_callback (unknown_event) |
| W402 | warning | Conditional requirement inferred from description: destination.card_number is required when destination.type equals card (createCardDisbursement) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: destination.card_token is required when destination.type equals card_token (createCardDisbursement) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I201 | info | Status mapping recorded (5 statuses): queued -> in_progress, in_flight -> in_progress, settled -> approved, returned -> rejected, rejected_by_bank -> rejected | см. вывод | STATUS_MAP |
| I301 | info | Signature convention recorded: X-CardPay-Signature (header), algorithm hmac-sha512, encoding base64, message raw_body, secret callback_secret | см. вывод | verify_signature! |
| I401 | info | Amount field amount in createCardDisbursement uses minor units (multiplier 100, score 8); signals: description: копейках, error example (422): kopecks, minimum: 50000 | description: копейках; error example (422): kopecks; minimum: 50000 | build_*_payload, MIN_AMOUNT |
| I401 | info | Amount field amount in createSbpDisbursement uses minor units (multiplier 100, score 5); signals: description: копейках, minimum: 50000 | description: копейках; minimum: 50000 | build_*_payload, MIN_AMOUNT |
| I403 | info | Gateway config recorded: external_method card_payout, gateway RUB_CARD_WITHDRAW (confidence 0.9); evidence: currency: RUB (enum constant), request method: card (default of destination.type), direction: withdraw (token 'disbursement' in operationId createCardDisbursement) | currency: RUB (enum constant); request method: card (default of destination.type); direction: withdraw (token 'disbursement' in operationId createCardDisbursement) | ProviderGateway config |

## Допущения

Реальный `Provider::BaseService` не предоставлен; сервис написан под контракт, реконструированный по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):

- `operation.amount` в основных единицах валюты; реквизиты - `operation.payout_requisite` одним хешем с ключом по способу выплаты
- `success(**details)` / `failure(<символ>, <i18n-код>, **details)`; символы: :unprocessable_entity, :unauthorized, :provider_error, :too_many_requests
- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не бросает исключений сам; Provider::RateLimitError и Provider::UnauthorizedError перехватываются на случай, если бросает
- `approve_operation(id)` / `reject_operation(id, error_code)` завершают операцию на платформе
- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех
