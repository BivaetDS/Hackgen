# Kassira Integration Guide

Сгенерировано provider-integrator 0.1.0 из «Kassira Merchant API» 2.4 (OpenAPI 3.0.3). Сервис: `Provider::KassiraService` (`kassira_service.rb`), контракт `Provider::BaseService`.

## Авторизация

- Тип: api_key (`MerchantToken`)
- Header: `X-Merchant-Token: <credentials.api_key>`
- Хранение: `providers.credentials` (encrypted), ключи: `api_key`, `callback_secret`, `merchant_id`
- Все запросы к провайдеру уходят через `auth_headers`; входящий webhook аутентифицируется подписью (см. «Webhook signature»)
- Evidence: securitySchemes.MerchantToken: apiKey in header X-Merchant-Token; security: MerchantToken used by 6 of 7 operations

## Настройка

| Параметр | Откуда | Значение по умолчанию / назначение |
|---|---|---|
| `KASSIRA_BASE_URL` | ENV | `https://api.kassira.example/merchant/v2` (unknown) |
| `KASSIRA_CALLBACK_URL` | ENV | отправляется в теле запроса как callback_url |
| `credentials[:api_key]` | providers.credentials | авторизация запросов (MerchantToken) |
| `credentials[:callback_secret]` | providers.credentials | секрет подписи webhook |
| `credentials[:merchant_id]` | providers.credentials | идентификатор мерчанта в теле запроса |

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|---|---|---|---|
| create_request | POST /payment/create | Создание платёжного поручения | X-Request-Id header |
| fetch_status | GET /payment/status/{payment_id} | Состояние платёжного поручения | - |
| process_callback | POST /callback/payment | Уведомление о смене состояния поручения | X-Sign |
| check_conditions | - | предпроверки: `super`, сумма >= 100, реквизиты способа выплаты (`REQUIRED_REQUISITES`) | - |

## Методы вне контракта

| Метод | Endpoint | Назначение | Kind | Уверенность |
|---|---|---|---|---|
| cancel_request | POST /payment/cancel/{payment_id} | Отмена платёжного поручения | cancel | 0.8 |
| post_requisites_check | POST /requisites/check | Проверка реквизитов получателя | unknown | 0.0 |
| fetch_balance | GET /merchant/balance | Баланс договора | balance | 0.8 |
| list_requests | GET /dictionary/banks | Справочник банков получателей | list | 0.5 |

Публичные методы сервиса вне `Provider::BaseService`; платформа вызывает их по своему усмотрению.

## Способы выплаты (request_method)

- Значения: `card` (по умолчанию), `account`, `phone` - из enum поля `payment_type` (уверенность 0.9)
- `create_request` ветвится `case request_method`; для каждого способа свой `build_<method>_payload`
- `check_conditions` отклоняет неизвестный способ (`unsupported_request_method`) и проверяет реквизиты из `REQUIRED_REQUISITES`

## Маппинг полей

### Запрос create_request (request_method `card`)

`POST /payment/create application/x-www-form-urlencoded`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchant_id | `credentials[:merchant_id]` | да | Идентификатор мерчанта в системе Kassira. |
| contract_num | TODO: нет источника на платформе | да | Номер договора, по которому проводится поручение. Выдаётся при подключении; у мерчанта может быть несколько договоров с разными лимитами. |
| order_id | `operation.id` | да | Номер операции в системе мерчанта, уникальный в рамках договора. |
| sum | `operation.amount` x 100 (minor units) | да | Сумма списания в копейках, целое число без разделителей. |
| cur | константа `'RUB'` | да | Валюта поручения. В редакции 2.4 поддерживается только RUB. |
| payment_type | константа `'card'` (ветка request_method) | да | enum: card, account, phone; Способ зачисления средств получателю. |
| pan | `operation.payout_requisite['card']['card_number']` | при payment_type = card | pattern `^\d{16,19}$`; Номер карты получателя без пробелов. Обязателен, если payment_type = card; для остальных способов зачисления игнорируется. |
| payee_name | `operation.payout_requisite['card']['name']` | нет | ФИО получателя полностью. Проверяется банком при зачислении на счёт. |
| purpose | не отправляется: нет источника на платформе | нет | Назначение платежа, печатается в выписке банка получателя. |
| callback_url | ENV `KASSIRA_CALLBACK_URL` | нет | Адрес для уведомлений о смене состояния. Если не передан, используется адрес, указанный в настройках договора. |
| ttl_min | не отправляется: нет источника на платформе | нет | Время жизни поручения в минутах, по умолчанию 1440. По истечении поручение переводится в состояние EXPIRED и средства не списываются. |

### Запрос create_request (request_method `account`)

`POST /payment/create application/x-www-form-urlencoded`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchant_id | `credentials[:merchant_id]` | да | Идентификатор мерчанта в системе Kassira. |
| contract_num | TODO: нет источника на платформе | да | Номер договора, по которому проводится поручение. Выдаётся при подключении; у мерчанта может быть несколько договоров с разными лимитами. |
| order_id | `operation.id` | да | Номер операции в системе мерчанта, уникальный в рамках договора. |
| sum | `operation.amount` x 100 (minor units) | да | Сумма списания в копейках, целое число без разделителей. |
| cur | константа `'RUB'` | да | Валюта поручения. В редакции 2.4 поддерживается только RUB. |
| payment_type | константа `'account'` (ветка request_method) | да | enum: card, account, phone; Способ зачисления средств получателю. |
| account_no | `operation.payout_requisite['account']['account_number']` | при payment_type = account | pattern `^\d{20}$`; Расчётный счёт получателя, 20 цифр. Обязателен, если payment_type = account; проверяется вместе с БИК. |
| bik | `operation.payout_requisite['account']['bank_code']` | при payment_type = account | pattern `^\d{9}$`; БИК банка получателя, 9 цифр. Обязателен, если payment_type = account; банк должен присутствовать в справочнике /dictionary/banks. |
| payee_name | `operation.payout_requisite['account']['name']` | нет | ФИО получателя полностью. Проверяется банком при зачислении на счёт. |
| purpose | не отправляется: нет источника на платформе | нет | Назначение платежа, печатается в выписке банка получателя. |
| callback_url | ENV `KASSIRA_CALLBACK_URL` | нет | Адрес для уведомлений о смене состояния. Если не передан, используется адрес, указанный в настройках договора. |
| ttl_min | не отправляется: нет источника на платформе | нет | Время жизни поручения в минутах, по умолчанию 1440. По истечении поручение переводится в состояние EXPIRED и средства не списываются. |

### Запрос create_request (request_method `phone`)

`POST /payment/create application/x-www-form-urlencoded`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| merchant_id | `credentials[:merchant_id]` | да | Идентификатор мерчанта в системе Kassira. |
| contract_num | TODO: нет источника на платформе | да | Номер договора, по которому проводится поручение. Выдаётся при подключении; у мерчанта может быть несколько договоров с разными лимитами. |
| order_id | `operation.id` | да | Номер операции в системе мерчанта, уникальный в рамках договора. |
| sum | `operation.amount` x 100 (minor units) | да | Сумма списания в копейках, целое число без разделителей. |
| cur | константа `'RUB'` | да | Валюта поручения. В редакции 2.4 поддерживается только RUB. |
| payment_type | константа `'phone'` (ветка request_method) | да | enum: card, account, phone; Способ зачисления средств получателю. |
| phone_number | `operation.payout_requisite['phone']['phone']` | при payment_type = phone | pattern `^79\d{9}$`; Телефон получателя в формате 79XXXXXXXXX. Обязателен, если payment_type = phone; номер должен быть привязан к банку из справочника. |
| payee_name | `operation.payout_requisite['phone']['name']` | нет | ФИО получателя полностью. Проверяется банком при зачислении на счёт. |
| purpose | не отправляется: нет источника на платформе | нет | Назначение платежа, печатается в выписке банка получателя. |
| callback_url | ENV `KASSIRA_CALLBACK_URL` | нет | Адрес для уведомлений о смене состояния. Если не передан, используется адрес, указанный в настройках договора. |
| ttl_min | не отправляется: нет источника на платформе | нет | Время жизни поручения в минутах, по умолчанию 1440. По истечении поручение переводится в состояние EXPIRED и средства не списываются. |

### Ответ create_request (200/409) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| payment_id | provider_operation_id | string | сохраняется как provider_operation_id |
| order_id | external_id | string | Номер операции в системе мерчанта, как он был передан при регистрации. |
| state | status | string | см. «Маппинг статусов» |
| sum | amount | integer | Сумма поручения в копейках. |
| cur | currency | string | Валюта поручения. |
| payment_type | requisite.type | string | enum: card, account, phone |
| masked_account | - | string | Реквизит получателя в маскированном виде, пригоден для показа оператору. |
| fault_code | error.code | string | Код причины отказа. Заполняется только для состояний REFUSED и RETURNED. |
| fault_message | error.message | string | Текстовое описание причины отказа. |
| created | created_at | string | Момент регистрации поручения. |
| updated | updated_at | string | Момент последней смены состояния. |

### Ответ fetch_status (200) -> платформа

| Поле провайдера | Канон Space Payments | Тип | Примечание |
|---|---|---|---|
| payment_id | provider_operation_id | string | сохраняется как provider_operation_id |
| order_id | external_id | string | Номер операции в системе мерчанта, как он был передан при регистрации. |
| state | status | string | см. «Маппинг статусов» |
| sum | amount | integer | Сумма поручения в копейках. |
| cur | currency | string | Валюта поручения. |
| payment_type | requisite.type | string | enum: card, account, phone |
| masked_account | - | string | Реквизит получателя в маскированном виде, пригоден для показа оператору. |
| fault_code | error.code | string | Код причины отказа. Заполняется только для состояний REFUSED и RETURNED. |
| fault_message | error.message | string | Текстовое описание причины отказа. |
| created | created_at | string | Момент регистрации поручения. |
| updated | updated_at | string | Момент последней смены состояния. |

### Запрос cancel_request

`POST /payment/cancel/{payment_id}`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| reason | не отправляется: нет источника на платформе | нет | Комментарий оператора мерчанта, сохраняется в журнале договора. |

### Запрос post_requisites_check

`POST /requisites/check`

| Поле провайдера | Источник на платформе | Обязательно | Примечание |
|---|---|---|---|
| payment_type | `request_method` | да | enum: card, account, phone; Проверяемый способ зачисления. |
| pan | `operation.payout_requisite[request_method]['card_number']` | нет | pattern `^\d{16,19}$`; Номер карты получателя. |
| account_no | `operation.payout_requisite[request_method]['account_number']` | нет | pattern `^\d{20}$`; Расчётный счёт получателя. |
| bik | `operation.payout_requisite[request_method]['bank_code']` | нет | pattern `^\d{9}$`; БИК банка получателя. |

## Маппинг статусов

| Provider | Space Payments | Основание |
|---|---|---|
| REGISTERED | in_progress | statuses.yml: registered -> in_progress (уверенность 0.95) |
| IN_WORK | in_progress | default: in_progress (уверенность 0.3) |
| PAID | approved | statuses.yml: paid -> approved (уверенность 0.95) |
| RETURNED | rejected | statuses.yml: returned -> rejected (уверенность 0.95) |
| REFUSED | rejected | statuses.yml: refused -> rejected (уверенность 0.95) |
| EXPIRED | rejected | statuses.yml: expired -> rejected (уверенность 0.95) |

Неизвестный статус -> `in_progress` до следующего уведомления (`map_status`).

## Обработка ошибок

| HTTP | Provider code | Канон | Действие | Примечание |
|---|---|---|---|---|
| 400 | INVALID_PARAM | validation_error | reject | - |
| 401 | SIGN_ERROR | invalid_credentials | alert ops, block provider | - |
| 402 | NOT_ENOUGH_FUNDS | insufficient_balance | retry later | - |
| 404 | DOC_NOT_FOUND | not_found | check status, do not retry blindly | - |
| 409 | DUPLICATE_ORDER | conflict | reject, check status | - |
| 429 | REQUEST_LIMIT | rate_limit | retry with backoff | Retry-After из заголовка |
| 500 | INTERNAL_FAILURE | internal_error | retry, alert ops | - |

- 409 на `POST /payment/create` - идемпотентный дубль: провайдер возвращает исходную выплату, сервис считает это успехом.
- Неизвестный HTTP-код: 4xx -> `validation_error`, 5xx -> `internal_error` (`provider_error`).
- `failure(<символ>, <код>, provider_code:, retry_after:)` - детали передаются именованными аргументами (docs/ASSUMPTIONS.md).

## ProviderGateway config

```json
{ "external_method": "card_payout", "gateway": "RUB_CARD_WITHDRAW" }
```

- Направление: withdraw, валюта: RUB, способ: card (уверенность 0.6)
- Evidence: currency: RUB (enum constant); request method: card (default of payment_type); direction: withdraw (token 'перевод' in description)

## Webhook signature

MD5(sorted_values(payload), callback_secret) -> hex -> X-Sign (header)

- Endpoint провайдера: `POST /callback/payment` (post_callback_payment); найден: path_heuristic (уверенность 0.86)
- Evidence подписи: parameter X-Sign (header): Контрольная подпись уведомления: MD5-хеш от склеенных значений полей payment_id,
- Кодировка и канонизация из спеки
- Сравнение подписи в постоянное время (`secure_compare`); секрет - `credentials[:callback_secret]`

- Payload для `process_callback`: разобранный JSON уведомления либо конверт `{ 'body' => <JSON>, 'headers' => { '<Signature-Header>' => ... }, 'raw_body' => '<сырое тело>' }`
- Без `raw_body` подпись проверяется по `JSON.generate(body)` - ненадёжно при иной сериализации у провайдера
- Поля payload: событие `notification_type`, статус `state`, id операции `payment_id`, код ошибки `fault_code`

| Событие | Статус Space Payments | Действие сервиса |
|---|---|---|
| PAYMENT_REGISTERED | in_progress | `success(status: 'in_progress')` |
| PAYMENT_IN_WORK | - | `unknown_event` (W203) |
| PAYMENT_PAID | approved | `approve_operation` |
| PAYMENT_REFUSED | rejected | `reject_operation` с кодом ошибки |
| PAYMENT_RETURNED | rejected | `reject_operation` с кодом ошибки |
| PAYMENT_EXPIRED | rejected | `reject_operation` с кодом ошибки |

- Ответ провайдеру: HTTP 200 `{"result":"OK"}` (формирует платформа после `process_callback`)

## Тесты

`kassira_service_spec.rb` - RSpec поверх `fixtures.json` через WebMock (сеть не нужна), 23 примеров:

- `create_request` (9): запрос (URL, заголовки, тело), успех 200, дубль 409, ошибки 400, 401, 402, 429, 500, неизвестный request_method
- `fetch_status` (4): запрос с авторизацией, статус из response_200, ошибки 401, 404, 500
- `process_callback` (6): callback_registered -> in_progress, callback -> approved, callback_failed -> rejected, callback_returned -> rejected, callback_expired -> rejected, подделанная подпись
- `check_conditions` (4): валидная операция, `MIN_AMOUNT`, `REQUIRED_REQUISITES`, `REQUEST_METHODS`

- Запуск из каталога с файлами: `rspec kassira_service_spec.rb` (гемы `rspec`, `webmock`); то же делает `bin/integrate --run-spec` сразу после генерации
- `base_contract.rb` (`Provider::BaseService`, `Provider::HttpClient` на Net::HTTP) - заглушки для автономного прогона (docs/ASSUMPTIONS.md, допущения 6 и 23); на платформе сервис получает настоящие `BaseService` и `client`
- Подпись webhook в тестах считается тем же выражением, что в `verify_signature!` (MD5, hex); секрет - `credentials[:callback_secret]`

## Требует подтверждения

Критичные выводы (единицы суммы, условная обязательность, подпись, статусы, конфиг шлюза) попадают сюда всегда, даже при высокой уверенности. Изменить вывод без правки кода: `overrides.yml` (ключи operations, amount_unit, required_if, signature, status_map, error_actions).

| Код | Уровень | Вывод | Основание | Где в коде |
|---|---|---|---|---|
| W101 | warning | Operation get_dictionary_banks (GET /dictionary/banks) classified as list with low confidence 0.5 | см. вывод | operation methods (name and role) |
| W101 | warning | Operation post_requisites_check (POST /requisites/check) classified as unknown with low confidence 0.0 | см. вывод | operation methods (name and role) |
| W201 | warning | Status IN_WORK has no canonical mapping; defaulting to in_progress | см. вывод | STATUS_MAP |
| W203 | warning | Webhook event PAYMENT_IN_WORK has no canonical status; the service treats it as unknown_event | см. вывод | process_callback (unknown_event) |
| W402 | warning | Conditional requirement inferred from description: account_no is required when payment_type equals account (post_payment_create) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: bik is required when payment_type equals account (post_payment_create) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: pan is required when payment_type equals card (post_payment_create) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W402 | warning | Conditional requirement inferred from description: phone_number is required when payment_type equals phone (post_payment_create) | см. вывод | check_conditions, REQUIRED_REQUISITES |
| W403 | warning | Required request field contract_num in post_payment_create is not mapped to any canonical field | см. вывод | build_*_payload (TODO) |
| I201 | info | Status mapping recorded (6 statuses): REGISTERED -> in_progress, IN_WORK -> in_progress, PAID -> approved, RETURNED -> rejected, REFUSED -> rejected, EXPIRED -> rejected | см. вывод | STATUS_MAP |
| I301 | info | Signature convention recorded: X-Sign (header), algorithm md5, encoding hex, message concatenated_fields, secret callback_secret | см. вывод | verify_signature! |
| I401 | info | Amount field sum in post_payment_create uses minor units (multiplier 100, score 5); signals: description: копейках, minimum: 10000 | description: копейках; minimum: 10000 | build_*_payload, MIN_AMOUNT |
| I403 | info | Gateway config recorded: external_method card_payout, gateway RUB_CARD_WITHDRAW (confidence 0.6); evidence: currency: RUB (enum constant), request method: card (default of payment_type), direction: withdraw (token 'перевод' in description) | currency: RUB (enum constant); request method: card (default of payment_type); direction: withdraw (token 'перевод' in description) | ProviderGateway config |

## Допущения

Реальный `Provider::BaseService` не предоставлен; сервис написан под контракт, реконструированный по эталону ТЗ и ответам экспертов (полный список - docs/ASSUMPTIONS.md, заглушка - `base_contract.rb`):

- `operation.amount` в основных единицах валюты; реквизиты - `operation.payout_requisite` одним хешем с ключом по способу выплаты
- `success(**details)` / `failure(<символ>, <i18n-код>, **details)`; символы: :unprocessable_entity, :unauthorized, :provider_error, :too_many_requests
- `client.get/post(url, json:|form:, headers:)` возвращает ответ со `status`, `body`, `headers` и не бросает исключений сам; Provider::RateLimitError и Provider::UnauthorizedError перехватываются на случай, если бросает
- `approve_operation(id)` / `reject_operation(id, error_code)` завершают операцию на платформе
- 409 с успешной схемой ответа на create - идемпотентный дубль, обрабатывается как успех
