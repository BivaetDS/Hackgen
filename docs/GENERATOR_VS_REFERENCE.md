# Сгенерированный NovaPay и эталон ТЗ: сознательные отличия

Эталон — `docs/TZ.md` («Ожидаемый результат»). Сгенерированные файлы — `spec/golden/novapay/`
(`bundle exec rake "golden:update[novapay]"` пересобирает их из `spec/fixtures/specs/novapay.yaml`).
Всё, что не перечислено ниже, совпадает с эталоном: имена класса и методов, `BASE_URL = ENV.fetch(...)`,
`STATUS_MAP`, `ERROR_MAP`, `private`-хелперы `build_*_payload` / `parse_create_response` / `auth_headers`,
одинарные кавычки и табличное выравнивание, константы карт после `private`.

## novapay_service.rb

| Место | Эталон | Сгенерировано | Почему |
|---|---|---|---|
| Шапка | нет | комментарий с версией генератора, спекой и правилами (`Evidence:` / `TODO(confidence …)`), `require 'json'`, `require 'openssl'` | файл должен объяснять сам себя и загружаться автономно |
| `create_request` | `request_method = 'create'`, один `build_payout_payload` с `type: 'sbp'` | `request_method = 'sbp'` (первое значение enum), `case request_method` → `build_sbp_payload` / `build_card_payload`, неизвестный способ → `unsupported_request_method` | ответ экспертов (PLAN §4): `request_method` — способ выплаты, при нескольких значениях enum сервис ветвится |
| `create_request` | `headers: auth_headers` | `headers = auth_headers.merge(idempotency_headers(operation))` | спека объявляет `Idempotency-Key`; эталон его не отправлял |
| `build_*_payload` | `amount: (operation.amount * 100).to_i` | `amount: amount_in_minor_units(operation.amount)` → `(amount * 100).round` + `# Evidence: description: копейках; …` | единицы — вывод анализатора с тремя сигналами; `.round` вместо `.to_i` не обрезает `10.15 * 100 = 1014.99…` |
| `build_*_payload` | без `compact` | `{ … }.compact` на каждом уровне | необязательные реквизиты без значения не уходят провайдеру как `null` |
| `build_*_payload` | `bank_code` без пометки | `# TODO(confidence 0.6): required when recipient.type = sbp (description: …)` | условная обязательность выведена из текста (W402) — средняя уверенность помечается в коде |
| `fetch_status` | `client.get(url)` → `map_status(response.body['status'])` | `client.get(url, headers: auth_headers)` → `parse_status_response` → `success(status: map_status(body['status']), response: body)`, ошибки через `provider_error` | эталон не передавал авторизацию и не обрабатывал 401/404; `map_status` сохранён с тем же именем как хелпер (ASSUMPTIONS 20) |
| `process_callback` | `verify_signature!(payload)` без реализации | `verify_signature!`: подпись из `payload['headers']`, сообщение — `payload['raw_body']` или `JSON.generate(body)`, HMAC-SHA256 hex, `secure_compare`; невалидная → `failure(:unauthorized, 'invalid_signature')` | конвенция payload подтверждена экспертами (PLAN §4); кодировка/канонизация не в спеке → `TODO(confidence 0.6)` + W301 |
| `process_callback` | только `payout.completed` / `payout.failed` | плюс `payout.cancelled` → `reject_operation`, `payout.processing` → `success(status: 'in_progress')` | все четыре события из enum спеки, а не два |
| `parse_create_response` | `success` только на 201 | `when 201, 409` — 409 со схемой `PayoutResponse` считается идемпотентным дублем; остальное → `provider_error` | PLAN §1 п.5: «409 как успех»; ошибки не теряются |
| `provider_error` (новый) | нет | HTTP → канон через `ERROR_MAP`, `failure(<символ>, <i18n>, provider_code:, retry_after:)` | единая обработка ошибок; `Retry-After` читается из заголовка (`retry_after_seconds`) |
| `rescue` | только в `create_request` | во всех методах, ходящих в `client` | клиент платформы может бросать `RateLimitError`/`UnauthorizedError` и из `fetch_status` |
| `check_conditions` | `operation.amount < 1000` | `MIN_AMOUNT = 1000` (`minimum: 100000` копеек ÷ 100) + `# Evidence: …`; проверка `REQUEST_METHODS`; `missing_requisites` по `REQUIRED_REQUISITES` (`sbp: phone, bank_code`; `card: phone, card_number`) | порог выведен из спеки, а не написан руками; обязательность реквизитов проверяется до запроса |
| Константы | `STATUS_MAP`, `ERROR_MAP` | плюс `REQUEST_METHODS`, `MIN_AMOUNT`, `REQUIRED_REQUISITES` сверху и `ERROR_ACTIONS` снизу; `ERROR_MAP` дополнен `404 => 'not_found'`, `409 => 'conflict'` из статус- и cancel-операций | таблица действий нужна платформе так же, как коды |
| Методы вне контракта | нет | `cancel_request(operation)`, `fetch_balance` с пометкой `# Outside the BaseService contract` | ASSUMPTIONS 5; операции спеки не теряются |

## INTEGRATION.md

Заголовки эталона сохранены (`Авторизация`, `Методы`, `Маппинг статусов`, `Обработка ошибок`,
`ProviderGateway config`, `Webhook signature`); таблица методов — та же, плюс строка `check_conditions`.
Добавлены секции `Настройка` (ENV и ключи `credentials`), `Методы вне контракта`, `Способы выплаты`,
`Маппинг полей` (источник каждого поля на платформе, единицы, обязательность), `Требует подтверждения`
(каждое W-событие и критичный вывод с evidence и местом в коде), `Допущения` (контракт `BaseService`).
В таблице ошибок добавлены колонки «Канон» и «Примечание» (Retry-After), в таблице статусов — «Основание».

## fixtures.json

Та же верхняя структура (`create_request` → `request`/`response_<код>`, `fetch_status`, `callback`,
`callback_failed`). Отличия: включены все объявленные ответы (400, 401, 402, 409, 429, 500, 404), ответы без
примера в спеке синтезированы и помечены `"_synthetic": true`; `fetch_status.response_200` получил `status`
(в спеке пример без него) с пометкой `_synthetic_fields`; добавлены `cancel_request` и `fetch_balance`.
Каждый пример проверен `json_schemer` против схемы, восстановленной из IR (`FieldSchema`).

## Дополнительные файлы

`base_contract.rb` — заглушка `Provider::BaseService`, `Result`, `Operation`, `Response`, исключений
(шапка «ДОПУЩЕНИЕ»). `generation_report.json` — события анализа и генерации, уверенности и evidence,
список `TODO(confidence …)` с номерами строк, результаты валидатора, SHA-256 файлов.
