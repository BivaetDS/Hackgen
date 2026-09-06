# RublePay Integration Guide

Сгенерировано provider-integrator 0.1.0 из «RublePay Deposit API» 2.4.1 (OpenAPI 3.0.3). Сервис: `Provider::RublepayService` (`rublepay_service.rb`), контракт `Provider::BaseService`.

## Авторизация

- Тип: api_key (`MerchantKey`)
- Query-параметр: `api_key=<credentials.api_key>` (добавляется `with_api_key`)
- Хранение: `providers.credentials` (encrypted), ключи: `api_key`, `callback_secret`, `merchant_id`
- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется подписью (см. «Webhook signature»)
- Evidence: securitySchemes.MerchantKey: apiKey in query api_key; security: MerchantKey used by 5 of 6 operations

## Настройка

| Параметр | Откуда | Значение по умолчанию / назначение |
|---|---|---|
| `RUBLEPAY_BASE_URL` | ENV | `https://api.sandbox.rublepay.example/v2` (sandbox) |
| servers (production) | спека | `https://api.rublepay.example/v2` |
| `RUBLEPAY_REDIRECT_URL` | ENV | отправляется в теле запроса как redirect_url |
| `RUBLEPAY_CALLBACK_URL` | ENV | отправляется в теле запроса как callback_url |
| `credentials[:api_key]` | providers.credentials | авторизация запросов (MerchantKey) |
| `credentials[:callback_secret]` | providers.credentials | секрет подписи webhook |
| `credentials[:merchant_id]` | providers.credentials | идентификатор мерчанта в теле запроса |

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|---|---|---|---|
| create_request | POST /deposits | Создать депозит | X-Request-Id header |
| fetch_status | GET /deposits/{deposit_id} | Проверить состояние депозита | - |
| process_callback | POST /notifications/deposit | Уведомление о смене состояния депозита | X-RublePay-Sign |
| check_conditions | - | предпроверки: `super`, реквизиты способа выплаты (`REQUIRED_REQUISITES`) | - |

## Методы вне контракта

| Метод | Endpoint | Назначение | Kind | Уверенность |
|---|---|---|---|---|
| refund_request | POST /deposits/{deposit_id}/refunds | Оформить возврат по депозиту | refund | 0.92 |
| calculate_deposit_fee | POST /fees/quote | Рассчитать комиссию по будущему депозиту | unknown | 0.0 |
| list_requests | GET /directories/sbp-banks | Список банков — участников СБП | list | 0.9 |

Публичные методы сервиса вне `Provider::BaseService`; платформа вызывает их по своему усмотрению.

## Способы выплаты (request_method)

- Значения: `card` (по умолчанию), `sbp`, `account` - из discriminator поля `payment_details.source_type` (уверенность 0.95)
- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`
- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет реквизиты из `REQUIRED_REQUISITES`

## Маппинг полей

### Запрос create_request (request_method `card`)

`POST /deposits application/json CreateDepositRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchant_order_id | `operation.id` | да | Идентификатор заказа в системе мерчанта, уникален в пределах магазина. |
| merchant_id | `credentials[:merchant_id]` | нет | Идентификатор магазина RublePay; обязателен, если ключ выдан на несколько магазинов. |
| amount | `operation.amount` as a decimal string with 2 places | да | pattern `^\d+\.\d{2}$`; Сумма депозита в рублях: строка с двумя знаками после десятичной точки. Минимум 10.00, максимум 300000.00 за один депозит. |
| currency | константа `'RUB'` | да | Валюта депозита. Поддерживается только российский рубль. |
| description | не отправляется: нет источника на платформе | нет | Назначение платежа; показывается плательщику и попадает в чек. |
| payment_details.source_type | константа `'card'` (ветка request_method) | да | Способ оплаты. |
| payment_details.pan | `operation.payout_requisite['card']['card_number']` | при payment_details.source_type = card | pattern `^\d{16,19}$`; Номер карты плательщика без пробелов и дефисов. |
| payment_details.expiry_month | `operation.payout_requisite['card']['expiry_month']` | при payment_details.source_type = card | pattern `^(0[1-9]|1[0-2])$`; Месяц окончания срока действия карты, две цифры. |
| payment_details.expiry_year | `operation.payout_requisite['card']['expiry_year']` | при payment_details.source_type = card | pattern `^\d{2}$`; Год окончания срока действия карты, две последние цифры. |
| payment_details.cvc | `operation.payout_requisite['card']['cvc']` | при payment_details.source_type = card | pattern `^\d{3,4}$`; Код проверки подлинности карты; RublePay его не сохраняет. |
| payment_details.cardholder_name | `operation.payout_requisite['card']['name']` | ветка card | Имя держателя карты латиницей, как напечатано на карте. |
| payer.email | не отправляется: нет источника на платформе | нет | Электронная почта плательщика. |
| payer.phone | не отправляется: нет источника на платформе | нет | pattern `^7\d{10}$`; Телефон плательщика в формате 7XXXXXXXXXX. |
| payer.ip_address | не отправляется: нет источника на платформе | нет | IP-адрес, с которого плательщик оформляет заказ. |
| payer.full_name | не отправляется: нет источника на платформе | нет | ФИО плательщика. |
| return_url | ENV `RUBLEPAY_REDIRECT_URL` | нет | Адрес, на который RublePay вернёт плательщика после оплаты или отказа. |
| notify_url | ENV `RUBLEPAY_CALLBACK_URL` | нет | Адрес для уведомлений; если не задан, берётся адрес из личного кабинета. |
| fiscalization | не отправляется: нет источника на платформе | нет | Формировать кассовый чек по 54-ФЗ на стороне RublePay. |
| receipt_email | не отправляется: нет источника на платформе | при fiscalization = true | Адрес для отправки чека плательщику. Обязателен, если fiscalization = true; в остальных случаях игнорируется. |
| ttl_minutes | не отправляется: нет источника на платформе | нет | Время жизни ссылки на оплату в минутах; по истечении депозит переходит в expired. |

### Запрос create_request (request_method `sbp`)

`POST /deposits application/json CreateDepositRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchant_order_id | `operation.id` | да | Идентификатор заказа в системе мерчанта, уникален в пределах магазина. |
| merchant_id | `credentials[:merchant_id]` | нет | Идентификатор магазина RublePay; обязателен, если ключ выдан на несколько магазинов. |
| amount | `operation.amount` as a decimal string with 2 places | да | pattern `^\d+\.\d{2}$`; Сумма депозита в рублях: строка с двумя знаками после десятичной точки. Минимум 10.00, максимум 300000.00 за один депозит. |
| currency | константа `'RUB'` | да | Валюта депозита. Поддерживается только российский рубль. |
| description | не отправляется: нет источника на платформе | нет | Назначение платежа; показывается плательщику и попадает в чек. |
| payment_details.source_type | константа `'sbp'` (ветка request_method) | да | Способ оплаты. |
| payment_details.bank_member_id | `operation.payout_requisite['sbp']['bank_code']` | при payment_details.source_type = sbp | pattern `^\d{12}$`; Идентификатор банка плательщика в СБП (memberId) из справочника /directories/sbp-banks. |
| payment_details.payer_phone | `operation.payout_requisite['sbp']['payer_phone']` | ветка sbp | pattern `^7\d{10}$`; Телефон плательщика в формате 7XXXXXXXXXX; ускоряет подтверждение в приложении банка. |
| payment_details.qr_type | `operation.payout_requisite['sbp']['qr_type']` | ветка sbp | enum: dynamic, static; Тип QR-кода СБП. |
| payer.email | не отправляется: нет источника на платформе | нет | Электронная почта плательщика. |
| payer.phone | не отправляется: нет источника на платформе | нет | pattern `^7\d{10}$`; Телефон плательщика в формате 7XXXXXXXXXX. |
| payer.ip_address | не отправляется: нет источника на платформе | нет | IP-адрес, с которого плательщик оформляет заказ. |
| payer.full_name | не отправляется: нет источника на платформе | нет | ФИО плательщика. |
| return_url | ENV `RUBLEPAY_REDIRECT_URL` | нет | Адрес, на который RublePay вернёт плательщика после оплаты или отказа. |
| notify_url | ENV `RUBLEPAY_CALLBACK_URL` | нет | Адрес для уведомлений; если не задан, берётся адрес из личного кабинета. |
| fiscalization | не отправляется: нет источника на платформе | нет | Формировать кассовый чек по 54-ФЗ на стороне RublePay. |
| receipt_email | не отправляется: нет источника на платформе | при fiscalization = true | Адрес для отправки чека плательщику. Обязателен, если fiscalization = true; в остальных случаях игнорируется. |
| ttl_minutes | не отправляется: нет источника на платформе | нет | Время жизни ссылки на оплату в минутах; по истечении депозит переходит в expired. |

### Запрос create_request (request_method `account`)

`POST /deposits application/json CreateDepositRequest`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchant_order_id | `operation.id` | да | Идентификатор заказа в системе мерчанта, уникален в пределах магазина. |
| merchant_id | `credentials[:merchant_id]` | нет | Идентификатор магазина RublePay; обязателен, если ключ выдан на несколько магазинов. |
| amount | `operation.amount` as a decimal string with 2 places | да | pattern `^\d+\.\d{2}$`; Сумма депозита в рублях: строка с двумя знаками после десятичной точки. Минимум 10.00, максимум 300000.00 за один депозит. |
| currency | константа `'RUB'` | да | Валюта депозита. Поддерживается только российский рубль. |
| description | не отправляется: нет источника на платформе | нет | Назначение платежа; показывается плательщику и попадает в чек. |
| payment_details.source_type | константа `'account'` (ветка request_method) | да | Способ оплаты. |
| payment_details.account_number | `operation.payout_requisite['account']['account_number']` | при payment_details.source_type = account | pattern `^\d{20}$`; Расчётный счёт плательщика, 20 цифр. |
| payment_details.bank_bik | `operation.payout_requisite['account']['bank_code']` | при payment_details.source_type = account | pattern `^\d{9}$`; БИК банка плательщика, 9 цифр. |
| payment_details.inn | `operation.payout_requisite['account']['inn']` | при payment_details.source_type = account | pattern `^\d{10}(\d{2})?$`; ИНН плательщика, 10 или 12 цифр. |
| payment_details.payer_name | `operation.payout_requisite['account']['payer_name']` | ветка account | Наименование организации-плательщика, как в банковских реквизитах. |
| payer.email | не отправляется: нет источника на платформе | нет | Электронная почта плательщика. |
| payer.phone | не отправляется: нет источника на платформе | нет | pattern `^7\d{10}$`; Телефон плательщика в формате 7XXXXXXXXXX. |
| payer.ip_address | не отправляется: нет источника на платформе | нет | IP-адрес, с которого плательщик оформляет заказ. |
| payer.full_name | не отправляется: нет источника на платформе | нет | ФИО плательщика. |
| return_url | ENV `RUBLEPAY_REDIRECT_URL` | нет | Адрес, на который RublePay вернёт плательщика после оплаты или отказа. |
| notify_url | ENV `RUBLEPAY_CALLBACK_URL` | нет | Адрес для уведомлений; если не задан, берётся адрес из личного кабинета. |
| fiscalization | не отправляется: нет источника на платформе | нет | Формировать кассовый чек по 54-ФЗ на стороне RublePay. |
| receipt_email | не отправляется: нет источника на платформе | при fiscalization = true | Адрес для отправки чека плательщику. Обязателен, если fiscalization = true; в остальных случаях игнорируется. |
| ttl_minutes | не отправляется: нет источника на платформе | нет | Время жизни ссылки на оплату в минутах; по истечении депозит переходит в expired. |

### Ответ create_request (201) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| deposit_id | provider_operation_id | string | сохраняется как provider_operation_id |
| merchant_order_id | external_id | string | Идентификатор заказа в системе мерчанта, переданный при создании. |
| state | status | string | см. «Маппинг статусов» |
| amount | amount | string | Заявленная сумма депозита в рублях. |
| paid_amount | - | string | Фактически поступившая сумма в рублях; для partially_paid меньше amount. |
| currency | currency | string | enum: RUB |
| payment_url | - | string | Ссылка на платёжную страницу RublePay; действует до expires_at. |
| error_code | error.code | string | Причина отказа, если депозит завершился неуспешно. |
| error_message | error.message | string | Человекочитаемое пояснение к error_code. |
| created_at | created_at | string | Момент создания депозита, UTC. |
| updated_at | updated_at | string | Момент последнего изменения состояния, UTC. |
| expires_at | - | string | Момент, после которого депозит переходит в expired. |

### Ответ fetch_status (200) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| deposit_id | provider_operation_id | string | сохраняется как provider_operation_id |
| merchant_order_id | external_id | string | Идентификатор заказа в системе мерчанта, переданный при создании. |
| state | status | string | см. «Маппинг статусов» |
| amount | amount | string | Заявленная сумма депозита в рублях. |
| paid_amount | - | string | Фактически поступившая сумма в рублях; для partially_paid меньше amount. |
| currency | currency | string | enum: RUB |
| payment_url | - | string | Ссылка на платёжную страницу RublePay; действует до expires_at. |
| error_code | error.code | string | Причина отказа, если депозит завершился неуспешно. |
| error_message | error.message | string | Человекочитаемое пояснение к error_code. |
| created_at | created_at | string | Момент создания депозита, UTC. |
| updated_at | updated_at | string | Момент последнего изменения состояния, UTC. |
| expires_at | - | string | Момент, после которого депозит переходит в expired. |

### Запрос refund_request

`POST /deposits/{deposit_id}/refunds`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` as a decimal string with 2 places | да | pattern `^\d+\.\d{2}$`; Сумма возврата в рублях, не больше оплаченной суммы депозита. |
| reason | не отправляется: нет источника на платформе | нет | Причина возврата для отчётности мерчанта. |
| merchant_refund_id | не отправляется: нет источника на платформе | нет | Идентификатор возврата в системе мерчанта. |

### Запрос calculate_deposit_fee

`POST /fees/quote`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| amount | `operation.amount` as a decimal string with 2 places | да | pattern `^\d+\.\d{2}$`; Сумма депозита в рублях, для которой считается комиссия. |
| currency | константа `'RUB'` | нет | - |
| source_type | TODO: нет источника на платформе | да | enum: card, sbp, account; Способ оплаты, по тарифу которого считается комиссия. |

## Маппинг статусов

| Provider | Space Payments | Основание |
|---|---|---|
| created | in_progress | statuses.yml: created -> in_progress (уверенность 0.95) |
| awaiting_payment | in_progress | statuses.yml token: awaiting_payment -> in_progress (уверенность 0.85) |
| succeeded | approved | statuses.yml: succeeded -> approved (уверенность 0.95) |
| partially_paid | in_progress | statuses.yml: partially_paid -> in_progress (уверенность 0.95) |
| refunded | rejected | statuses.yml: refunded -> rejected (уверенность 0.95) |
| expired | rejected | statuses.yml: expired -> rejected (уверенность 0.95) |
| rejected | rejected | statuses.yml: rejected -> rejected (уверенность 0.95) |

Неизвестный статус -> `in_progress` до следующего уведомления (`map_status`).

## Обработка ошибок

| HTTP | Provider code | Канон | Действие | Примечание |
|---|---|---|---|---|
| 400 | malformed_request | validation_error | reject | - |
| 401 | merchant_disabled | invalid_credentials | alert ops, block provider | - |
| 404 | deposit_not_found | not_found | check status, do not retry blindly | - |
| 409 | deposit_already_registered | conflict | reject, check status | - |
| 422 | amount_less_than_min | validation_error | reject | - |
| 429 | too_many_requests | rate_limit | retry with backoff | Retry-After из тела ответа |
| 503 | acquirer_unavailable | internal_error | retry later | - |

- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).
- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными аргументами (docs/ASSUMPTIONS.md).

## ProviderGateway config

```json
{ "external_method": "card_deposit", "gateway": "RUB_CARD_DEPOSIT" }
```

- Направление: deposit, валюта: RUB, способ: card (уверенность 0.9)
- Evidence: currency: RUB (enum constant); request method: card (default of payment_details.source_type); direction: deposit (token 'deposit' in operationId initDeposit)

## Webhook signature

HMAC-SHA512(body, callback_secret) -> hex -> X-RublePay-Sign (header)

- Endpoint провайдера: `POST /notifications/deposit` (depositNotification); найден: path_heuristic (уверенность 0.92)
- Evidence подписи: operation description: Подпись передаётся в заголовке X-RublePay-Sign: HMAC-SHA512 от сырого тела запроса, hex
- Кодировка и канонизация из спеки
- Сравнение подписи в постоянное время (`secure_compare`); секрет - `credentials[:callback_secret]`

- Payload для `process_callback`: разобранный JSON уведомления либо конверт `{ 'body' => <JSON>, 'headers' => { '<Signature-Header>' => ... }, 'raw_body' => '<сырое тело>' }`
- Без `raw_body` подпись проверяется по `JSON.generate(body)` - ненадёжно при иной сериализации у провайдера
- Поля payload: событие `event`, статус `state`, id операции `deposit_id`, код ошибки `error_code`

| Событие | Статус Space Payments | Действие сервиса |
|---|---|---|
| deposit.awaiting_payment | in_progress | `success(status: 'in_progress')` |
| deposit.partially_paid | approved | `approve_operation` |
| deposit.succeeded | approved | `approve_operation` |
| deposit.refunded | rejected | `reject_operation` с кодом ошибки |
| deposit.expired | rejected | `reject_operation` с кодом ошибки |

- Ответ провайдеру: HTTP 200 `{"accepted":true}` (формирует платформа после `process_callback`)

## Тесты

`rublepay_service_spec.rb` - RSpec поверх `fixtures.json` через WebMock (сеть не нужна), 19 примеров:

- `create_request` (9): запрос (URL, заголовки, тело), успех 201, ошибки 400, 401, 409, 422, 429, 503, неизвестный request_method
- `fetch_status` (4): запрос с авторизацией, статус из response_200, ошибки 401, 404, 429
- `process_callback` (3): callback -> approved, callback_failed -> rejected, подделанная подпись
- `check_conditions` (3): валидная операция, `REQUIRED_REQUISITES`, `REQUEST_METHODS`

- Запуск из каталога с файлами: `rspec rublepay_service_spec.rb` (гемы `rspec`, `webmock`); то же делает `bin/integrate --run-spec` сразу после генерации
- `base_contract.rb` (`Provider::BaseService`, `Provider::HttpClient` на Net::HTTP) - заглушки для автономного прогона (docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие `BaseService` и `client`
- Подпись webhook в тестах считается тем же выражением, что в `verify_signature!` (HMAC-SHA512, hex); секрет - `credentials[:callback_secret]`

## Требует подтверждения

Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: `overrides.yml` (ключи operations, amount_unit, required_if, signature, status_map, error_actions).

| Код | Уровень | Вывод | Основание | Где в коде |
|---|---|---|---|---|
| W101 | warning | Operation calculateDepositFee (POST /fees/quote) classified as unknown with low confidence 0.0 | см. вывод | operation methods (name and role) |
| W202 | warning | Provider error code amount_less_than_min (HTTP 422) has no canonical analog; defaulting to validation_error | см. вывод | ERROR_MAP |
| W202 | warning | Provider error code source_not_enabled (HTTP 422) has no canonical analog; defaulting to validation_error | см. вывод | ERROR_MAP |
| W402 | warning | Conditional requirement inferred from description: receipt_email is required when fiscalization equals true (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W403 | warning | Required request field occurred_at in depositNotification is not mapped to any canonical field | см. вывод | build_*_payload (TODO) |
| W403 | warning | Required request field source_type in calculateDepositFee is not mapped to any canonical field | см. вывод | build_*_payload (TODO) |
| I201 | info | Status mapping recorded (7 statuses): created -> in_progress, awaiting_payment -> in_progress, succeeded -> approved, partially_paid -> in_progress, refunded -> rejected, expired -> rejected, rejected -> rejected | см. вывод | STATUS_MAP |
| I301 | info | Signature convention recorded: X-RublePay-Sign (header), algorithm hmac-sha512, encoding hex, message raw_body, secret callback_secret | см. вывод | verify_signature! |
| I401 | info | Amount field amount in initDeposit uses major units (multiplier 1, score 6); signals: description: рублях, pattern: ^\d+\.\d{2}$, type: string | description: рублях; pattern: ^\d+\.\d{2}$; type: string | build_*_payload, MIN_AMOUNT |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.account_number is required when payment_details.source_type equals account (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.bank_bik is required when payment_details.source_type equals account (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.inn is required when payment_details.source_type equals account (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.cvc is required when payment_details.source_type equals card (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.expiry_month is required when payment_details.source_type equals card (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.expiry_year is required when payment_details.source_type equals card (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.pan is required when payment_details.source_type equals card (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I402 | info | Conditional requirement recorded from discriminator: payment_details.bank_member_id is required when payment_details.source_type equals sbp (initDeposit) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| I403 | info | Gateway config recorded: external_method card_deposit, gateway RUB_CARD_DEPOSIT (confidence 0.9); evidence: currency: RUB (enum constant), request method: card (default of payment_details.source_type), direction: deposit (token 'deposit' in operationId initDeposit) | currency: RUB (enum constant); request method: card (default of payment_details.source_type); direction: deposit (token 'deposit' in operationId initDeposit) | ProviderGateway config |

## Допущения

Реальный `Provider::BaseService` не предоставлен; сервис написан под контракт, реконструированный по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):

- `operation.amount` в основных единицах валюты; реквизиты - `operation.payout_requisite` одним хешем с ключом по способу выплаты
- `success(**details)` / `failure(<символ>, <i18n-код>, **details)`; символы: :unprocessable_entity, :unauthorized, :provider_error, :too_many_requests
- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не бросает исключений сам; Provider::RateLimitError и Provider::UnauthorizedError перехватываются на случай, если бросает
- `approve_operation(id)` / `reject_operation(id, error_code)` завершают операцию на платформе
- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех
