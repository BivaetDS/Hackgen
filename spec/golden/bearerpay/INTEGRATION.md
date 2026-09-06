# BearerPay Integration Guide

Сгенерировано provider-integrator 0.1.0 из «BearerPay Transfers API» 2.4.0 (OpenAPI 3.0.3). Сервис: `Provider::BearerpayService` (`bearerpay_service.rb`), контракт `Provider::BaseService`.

## Авторизация

- Тип: http_bearer (`BearerAuth`)
- Header: `Authorization: Bearer <credentials.token>`
- Хранение: `providers.credentials` (encrypted), ключи: `token`
- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется подписью (см. «Webhook signature»)
- Evidence: securitySchemes.BearerAuth: http bearer in header Authorization; security: BearerAuth used by 6 of 6 operations

## Настройка

| Параметр | Откуда | Значение по умолчанию / назначение |
|---|---|---|
| `BEARERPAY_BASE_URL` | ENV | `https://sandbox.bearerpay.example/v2` (sandbox) |
| servers (production) | спека | `https://api.bearerpay.example/v2` |
| `credentials[:token]` | providers.credentials | авторизация запросов (BearerAuth) |

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|---|---|---|---|
| create_request | POST /transfers | Создать перевод | X-Request-Id header |
| fetch_status | GET /transfers/{transfer_id} | Статус перевода | - |
| process_callback | - | заглушка: webhook не найден (W304) | - |
| check_conditions | - | предпроверки: `super`, сумма >= 100, сумма <= 50000, реквизиты способа выплаты (`REQUIRED_REQUISITES`) | - |

## Методы вне контракта

| Метод | Endpoint | Назначение | Kind | Уверенность |
|---|---|---|---|---|
| list_requests | GET /transfers | История переводов | list | 0.9 |
| quote_transfer_fee | POST /transfers/quote | Рассчитать комиссию перевода | unknown | 0.0 |
| cancel_request | POST /transfers/{transfer_id}/cancel | Отменить перевод | cancel | 0.9 |
| download_transfer_receipt | GET /transfers/{transfer_id}/receipt | Квитанция по переводу | status | 0.8 |

Публичные методы сервиса вне `Provider::BaseService`; платформа вызывает их по своему усмотрению.

## Способы выплаты (request_method)

- Значения: `ach` (по умолчанию), `wire`, `card` - из enum поля `destination_type` (уверенность 0.9)
- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`
- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет реквизиты из `REQUIRED_REQUISITES`

## Маппинг полей

### Запрос create_request (request_method `ach`)

`POST /transfers application/json CreateTransferRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма перевода в минимальных единицах валюты — в центах (250000 = 2500.00 USD) |
| currency | константа `'USD'` | да | Валюта перевода; на текущий момент поддерживается только USD |
| reference | `operation.id` | да | Идентификатор операции на стороне мерчанта, уникальный в рамках аккаунта |
| destination_type | константа `'ach'` (ветка request_method) | да | enum: ach, wire, card; Канал зачисления средств получателю: ach — расчётный счёт (1-2 банковских дня), wire — Fedwire/SWIFT (в день отправки), card — push-перевод на карту (мгновенно). |
| holder_name | `operation.payout_requisite['ach']['name']` | да | Имя владельца счёта или карты получателя, как оно записано в банке |
| account_number | `operation.payout_requisite['ach']['account_number']` | при destination_type = ach | pattern `^[0-9]{4,17}$`; Номер счёта получателя. Обязателен, если destination_type = ach |
| routing_number | `operation.payout_requisite['ach']['bank_code']` | при destination_type = ach | pattern `^[0-9]{9}$`; ABA routing number банка получателя. Обязателен, если destination_type = ach |
| purpose_code | TODO: нет источника на платформе | да | Код назначения платежа по классификатору NACHA (приложение B к договору): SALA — заработная плата, SUPP — оплата поставщику, OTHR — прочее. |
| note | не отправляется: нет источника на платформе | нет | Произвольное назначение платежа, попадает в выписку получателя |

### Запрос create_request (request_method `wire`)

`POST /transfers application/json CreateTransferRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма перевода в минимальных единицах валюты — в центах (250000 = 2500.00 USD) |
| currency | константа `'USD'` | да | Валюта перевода; на текущий момент поддерживается только USD |
| reference | `operation.id` | да | Идентификатор операции на стороне мерчанта, уникальный в рамках аккаунта |
| destination_type | константа `'wire'` (ветка request_method) | да | enum: ach, wire, card; Канал зачисления средств получателю: ach — расчётный счёт (1-2 банковских дня), wire — Fedwire/SWIFT (в день отправки), card — push-перевод на карту (мгновенно). |
| holder_name | `operation.payout_requisite['wire']['name']` | да | Имя владельца счёта или карты получателя, как оно записано в банке |
| swift_bic | не отправляется: нет источника на платформе | при destination_type = wire | SWIFT/BIC банка получателя. Required for destination_type = wire |
| purpose_code | TODO: нет источника на платформе | да | Код назначения платежа по классификатору NACHA (приложение B к договору): SALA — заработная плата, SUPP — оплата поставщику, OTHR — прочее. |
| note | не отправляется: нет источника на платформе | нет | Произвольное назначение платежа, попадает в выписку получателя |

### Запрос create_request (request_method `card`)

`POST /transfers application/json CreateTransferRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма перевода в минимальных единицах валюты — в центах (250000 = 2500.00 USD) |
| currency | константа `'USD'` | да | Валюта перевода; на текущий момент поддерживается только USD |
| reference | `operation.id` | да | Идентификатор операции на стороне мерчанта, уникальный в рамках аккаунта |
| destination_type | константа `'card'` (ветка request_method) | да | enum: ach, wire, card; Канал зачисления средств получателю: ach — расчётный счёт (1-2 банковских дня), wire — Fedwire/SWIFT (в день отправки), card — push-перевод на карту (мгновенно). |
| holder_name | `operation.payout_requisite['card']['name']` | да | Имя владельца счёта или карты получателя, как оно записано в банке |
| card_number | `operation.payout_requisite['card']['card_number']` | при destination_type = card | pattern `^[0-9]{13,19}$`; Номер карты получателя. Required for destination_type = card |
| purpose_code | TODO: нет источника на платформе | да | Код назначения платежа по классификатору NACHA (приложение B к договору): SALA — заработная плата, SUPP — оплата поставщику, OTHR — прочее. |
| note | не отправляется: нет источника на платформе | нет | Произвольное назначение платежа, попадает в выписку получателя |

### Ответ create_request (201) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| transfer_id | provider_operation_id | string | сохраняется как provider_operation_id |
| reference | external_id | string | Идентификатор операции на стороне мерчанта |
| status | status | string | см. «Маппинг статусов» |
| amount | amount | integer | Сумма перевода в центах |
| currency | currency | string | - |
| fee | fee | integer | Комиссия BearerPay в центах, списывается сверх суммы перевода |
| destination_type | requisite.type | string | enum: ach, wire, card |
| account_number_last4 | - | string | Последние четыре знака счёта или карты получателя |
| holder_name | requisite.name | string | - |
| error_code | error.code | string | Код причины отказа, заполняется только для status = DECLINED |
| error_message | error.message | string | Текст причины отказа от платёжной сети |
| created_at | created_at | string | - |
| updated_at | updated_at | string | - |
| settled_at | completed_at | string | Момент зачисления средств получателю, только для status = DONE |

### Ответ fetch_status (200) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| transfer_id | provider_operation_id | string | сохраняется как provider_operation_id |
| reference | external_id | string | Идентификатор операции на стороне мерчанта |
| status | status | string | см. «Маппинг статусов» |
| amount | amount | integer | Сумма перевода в центах |
| currency | currency | string | - |
| fee | fee | integer | Комиссия BearerPay в центах, списывается сверх суммы перевода |
| destination_type | requisite.type | string | enum: ach, wire, card |
| account_number_last4 | - | string | Последние четыре знака счёта или карты получателя |
| holder_name | requisite.name | string | - |
| error_code | error.code | string | Код причины отказа, заполняется только для status = DECLINED |
| error_message | error.message | string | Текст причины отказа от платёжной сети |
| created_at | created_at | string | - |
| updated_at | updated_at | string | - |
| settled_at | completed_at | string | Момент зачисления средств получателю, только для status = DONE |

### Запрос quote_transfer_fee

`POST /transfers/quote`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` x 100 (minor units) | да | Сумма перевода в центах |
| currency | константа `'USD'` | да | - |
| destination_type | `request_method` | да | enum: ach, wire, card |

## Маппинг статусов

| Provider | Space Payments | Основание |
|---|---|---|
| NEW | in_progress | statuses.yml: new -> in_progress (уверенность 0.95) |
| SENT | in_progress | statuses.yml: sent -> in_progress (уверенность 0.95) |
| DONE | approved | statuses.yml: done -> approved (уверенность 0.95) |
| DECLINED | rejected | statuses.yml: declined -> rejected (уверенность 0.95) |

Неизвестный статус -> `in_progress` до следующего уведомления (`map_status`).

## Обработка ошибок

| HTTP | Provider code | Канон | Действие | Примечание |
|---|---|---|---|---|
| 400 | VALIDATION_FAILED | validation_error | reject | Retry-After из тела ответа |
| 401 | INVALID_TOKEN | invalid_credentials | alert ops, block provider | Retry-After из тела ответа |
| 402 | INSUFFICIENT_FUNDS | insufficient_balance | retry later | Retry-After из тела ответа |
| 403 | ACCOUNT_BLOCKED | invalid_credentials | alert ops, block provider | Retry-After из тела ответа |
| 404 | TRANSFER_NOT_FOUND | not_found | check status, do not retry blindly | Retry-After из тела ответа |
| 409 | DUPLICATE_REFERENCE | conflict | reject, check status | Retry-After из тела ответа |
| 422 | AMOUNT_LIMIT_EXCEEDED | validation_error | reject | Retry-After из тела ответа; возможен суточный/разовый лимит провайдера — проверить договор (PLAN §4, допущение 7) |
| 429 | THROTTLED | rate_limit | retry with backoff | Retry-After из заголовка |
| 500 | INTERNAL_ERROR | internal_error | retry, alert ops | Retry-After из тела ответа |
| 503 | PROVIDER_UNAVAILABLE | internal_error | retry later | Retry-After из тела ответа |

- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).
- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными аргументами (docs/ASSUMPTIONS.md).

## ProviderGateway config

```json
{ "external_method": "ach_payout", "gateway": "USD_ACH_WITHDRAW" }
```

- Направление: withdraw, валюта: USD, способ: ach (уверенность 0.9)
- Evidence: currency: USD (enum constant); request method: ach (default of destination_type); direction: withdraw (token 'transfer' in operationId createTransfer)

## Webhook signature

Спека не описывает webhook (W304): `process_callback` - заглушка, статус получать через `fetch_status`.

## Тесты

`bearerpay_service_spec.rb` - RSpec поверх `fixtures.json` через WebMock (сеть не нужна), 22 примеров:

- `create_request` (12): запрос (URL, заголовки, тело), успех 201, ошибки 400, 401, 402, 403, 409, 422, 429, 500, 503, неизвестный request_method
- `fetch_status` (4): запрос с авторизацией, статус из response_200, ошибки 401, 404, 429
- `process_callback` (1): заглушка (`NotImplementedError`, W304)
- `check_conditions` (5): валидная операция, `MIN_AMOUNT`, `MAX_AMOUNT`, `REQUIRED_REQUISITES`, `REQUEST_METHODS`

- Запуск из каталога с файлами: `rspec bearerpay_service_spec.rb` (гемы `rspec`, `webmock`); то же делает `bin/integrate --run-spec` сразу после генерации
- `base_contract.rb` (`Provider::BaseService`, `Provider::HttpClient` на Net::HTTP) - заглушки для автономного прогона (docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие `BaseService` и `client`

## Требует подтверждения

Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: `overrides.yml` (ключи operations, amount_unit, required_if, signature, status_map, error_actions).

| Код | Уровень | Вывод | Основание | Где в коде |
|---|---|---|---|---|
| W101 | warning | Operation quoteTransferFee (POST /transfers/quote) classified as unknown with low confidence 0.0 | см. вывод | operation methods (name and role) |
| W105 | warning | Several status candidates (getTransferStatus, downloadTransferReceipt); getTransferStatus chosen, others generated as extra methods | см. вывод | extra methods |
| W202 | warning | Provider error code TRANSFER_NOT_CANCELABLE (HTTP 409) has no canonical analog; defaulting to conflict | см. вывод | ERROR_MAP |
| W304 | warning | No webhook endpoint found; process_callback is generated as a stub | см. вывод | process_callback (stub) |
| W402 | warning | Conditional requirement inferred from description: account_number is required when destination_type equals ach (createTransfer) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: card_number is required when destination_type equals card (createTransfer) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: routing_number is required when destination_type equals ach (createTransfer) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: swift_bic is required when destination_type equals wire (createTransfer) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W403 | warning | Required request field purpose_code in createTransfer is not mapped to any canonical field | см. вывод | build_*_payload (TODO) |
| I201 | info | Status mapping recorded (4 statuses): NEW -> in_progress, SENT -> in_progress, DONE -> approved, DECLINED -> rejected | см. вывод | STATUS_MAP |
| I401 | info | Amount field amount in createTransfer uses minor units (multiplier 100, score 8); signals: description: в центах, error example (400): cents, minimum: 10000 | description: в центах; error example (400): cents; minimum: 10000 | build_*_payload, MIN_AMOUNT |
| I403 | info | Gateway config recorded: external_method ach_payout, gateway USD_ACH_WITHDRAW (confidence 0.9); evidence: currency: USD (enum constant), request method: ach (default of destination_type), direction: withdraw (token 'transfer' in operationId createTransfer) | currency: USD (enum constant); request method: ach (default of destination_type); direction: withdraw (token 'transfer' in operationId createTransfer) | ProviderGateway config |

## Допущения

Реальный `Provider::BaseService` не предоставлен; сервис написан под контракт, реконструированный по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):

- `operation.amount` в основных единицах валюты; реквизиты - `operation.payout_requisite` одним хешем с ключом по способу выплаты
- `success(**details)` / `failure(<символ>, <i18n-код>, **details)`; символы: :unprocessable_entity, :unauthorized, :provider_error, :too_many_requests
- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не бросает исключений сам; Provider::RateLimitError и Provider::UnauthorizedError перехватываются на случай, если бросает
- `approve_operation(id)` / `reject_operation(id, error_code)` завершают операцию на платформе
- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех
