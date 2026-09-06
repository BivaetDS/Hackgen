Задача 1. Генератор интеграций с платёжными провайдерами 

## Полное описание

Space Payments подключает новых платёжных провайдеров регулярно. Каждая интеграция - Ruby-сервис с единым контрактом:

| class Provider::ExampleService < Provider::BaseService   def check_conditions(operation, request_method)   # предпроверки   def create_request(operation, ...)                # создание выплаты/депозита   def process_callback(payload)                     # обработка webhook   def fetch_status(operation)                       # статус-запрос end |
| --- |

Сейчас разработчик вручную читает документацию провайдера и пишет сервис с нуля. Это занимает 2–5 дней на интеграцию.

Задача: создать инструмент, который принимает открытую документацию API провайдера и генерирует интеграцию провайдера.

### Вводные данные

| **Файл** | **Описание** |
| --- | --- |
| provider_api.yaml | Пример текстового файла с инструкцией, как программе обращаться к платежному провайдеру: куда отправлять запросы, какие данные передавать и какие ответы ожидать. |

### Ожидаемый результат работы решения

Система должна получать provider_api.yaml на входе и отдавать несколько файлов для интеграции на выходе:

#### 1. Сгенерированный сервис, соответствующий контракту Provider::BaseService:

# app/services/provider/novapay_service.rb

class Provider

  class NovapayService < BaseService

    BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')

    def create_request(operation, request_method = 'create')

      payload = build_payout_payload(operation)

      response = client.post("#{BASE_URL}/payouts", json: payload, headers: auth_headers)

      parse_create_response(operation, response)

    rescue Provider::RateLimitError

      failure(:too_many_requests, 'provider.rate_limit')

    rescue Provider::UnauthorizedError

      failure(:unauthorized, 'provider.invalid_credentials')

    end

    def fetch_status(operation)

      response = client.get("#{BASE_URL}/payouts/#{operation.provider_operation_id}")

      map_status(response.body['status'])

    end

    def process_callback(payload)

      verify_signature!(payload) # HMAC-SHA256 из X-NovaPay-Signature

      case payload['event']

      when 'payout.completed' then approve_operation(payload['payout_id'])

      when 'payout.failed'    then reject_operation(payload['payout_id'], payload.dig('error', 'code'))

      else failure(:unprocessable_entity, 'unknown_event')

      end

    end

    def check_conditions(operation, request_method)

      base_result = super

      return base_result if base_result.failed?

      return failure(:unprocessable_entity, 'amount_too_low') if operation.amount < 1000

      success

    end

    private

    def build_payout_payload(operation)

      {

        amount: (operation.amount * 100).to_i,

        currency: 'RUB',

        external_id: operation.id,

        recipient: {

          type: 'sbp',

          phone: operation.payout_requisite.dig('sbp', 'phone'),

          bank_code: operation.payout_requisite.dig('sbp', 'bank_code'),

          bank_name: operation.payout_requisite.dig('sbp', 'bank_name')

        }

      }

    end

    STATUS_MAP = {

      'pending'    => 'in_progress',

      'processing' => 'in_progress',

      'completed'  => 'approved',

      'failed'     => 'rejected',

      'cancelled'  => 'rejected'

    }.freeze

    ERROR_MAP = {

      400 => 'validation_error',

      401 => 'invalid_credentials',

      402 => 'insufficient_balance',

      422 => 'validation_error',

      429 => 'rate_limit',

      500 => 'internal_error'

    }.freeze

  end

end

#### 2. Документация интеграции (INTEGRATION.md)

**# NovaPay Integration Guide**

**## Авторизация**

- Тип: API Key

- Header: `X-API-Key: <credentials.api_key>`

- Хранение: `providers.credentials` (encrypted)

**## Методы**

| Метод | Endpoint | Назначение | Idempotency |

|-------|----------|------------|-------------|

| create_payout | POST /payouts | Создание выплаты | Idempotency-Key header |

| get_status | GET /payouts/{id} | Статус | - |

| cancel | POST /payouts/{id}/cancel | Отмена | - |

| webhook | POST /webhooks/payout | Callback | X-NovaPay-Signature |

**## Маппинг статусов**

| Provider | Space Payments |

|----------|----------------|

| pending | in_progress |

| processing | in_progress |

| completed | approved |

| failed | rejected |

| cancelled | rejected |

**## Обработка ошибок**

| HTTP | Provider code | Действие |

|------|---------------|----------|

| 400 | validation_error | reject |

| 401 | unauthorized | alert ops, block provider |

| 402 | insufficient_balance | retry later |

| 429 | rate_limit_exceeded | retry with backoff |

| 500 | internal_error | retry, alert ops |

**## ProviderGateway config**

{ "external_method": "sbp_payout", "gateway": "RUB_SBP_WITHDRAW" }

**## Webhook signature**

HMAC-SHA256(body, callback_secret) → hex → X-NovaPay-Signature

#### 3. Тестовые фикстуры (fixtures.json)

{

  "create_request": {

    "request": {

      "amount": 1500000,

      "currency": "RUB",

      "external_id": "op_abc123",

      "recipient": { "type": "sbp", "phone": "79001234567", "bank_code": "044525225" }

    },

    "response_201": { "id": "np_7f3a9b2c", "status": "pending" },

    "response_422": { "error": { "code": "validation_error", "message": "Amount must be at least 100000 kopecks" } }

  },

  "fetch_status": {

    "response_200": { "id": "np_7f3a9b2c", "status": "completed" }

  },

  "callback": {

    "payload": { "event": "payout.completed", "payout_id": "np_7f3a9b2c", "status": "completed" },

    "expected_operation_status": "approved"

  },

  "callback_failed": {

    "payload": { "event": "payout.failed", "payout_id": "np_7f3a9b2c", "status": "failed", "error": { "code": "recipient_not_found" } },

    "expected_operation_status": "rejected"

  }

}

#### 4. CLI

$ ./integrate --spec provider_api.yaml --provider novapay --lang ruby

Parsing spec...

Found 5 endpoints: POST /payouts, GET /payouts/{id}, POST /payouts/{id}/cancel,

                  POST /webhooks/payout, GET /balance

Auth: ApiKeyAuth (header: X-API-Key)

Webhook signature: X-NovaPay-Signature (HMAC-SHA256)

Generating service...

Generating integration guide...

Generating test fixtures...

Output:

  ./output/novapay_service.rb

  ./output/INTEGRATION.md

  ./output/fixtures.json

## Процесс разработки и оценки

После начала хакатона команды получат вводные данные кейса (см раздел “Вводные данные”) и критерии оценки (см раздел “Критерии”) 

В течении хакатона у команды будет 3 чекпоинта (встречи с экспертами), по итогу всех трех чекпоинтов эксперты выставляют оценки и так формируется топ 5 команд, которые будут допущены до защит (максимум 100 баллов)

На защитах команд их будут оценивать жюри по своим критериям (см раздел “Критерии”), суммарная оценка команды за хакатон складывается как баллы технического жюри + баллы отраслевого жюри (максимум 120 баллов)

По итогам выставленных баллов формируется лидерборд и отбираются топ3 команды призеры

## Ограничения

- На кейсе нельзя использовать проприетарные технологии и решения с закрытым исходным кодом. 

- Большинство кода внутри репозитория должно быть написано на ruby

- Запрещено использование нейросетей внутри проекта

За нарушения правил предусматривается дисквалификация

## Критерии

В колонке “Конкретная разбалловка” указано максимальное кол-во баллов, которое можно получить при выполнении условия разбалловки. Если в разбалловке указано, например, 8 баллов, то это значит, что по этому пункту можно получить баллы от 0 до 8.

### Эксперты

| **Критерий** | **Максимум, баллов** | **Конкретная разбалловка** |
| --- | --- | --- |
| **1. Корректность разбора API-спецификации** | **20** | **8** - определены основные методы API и параметры запросов и ответов; **7** - учтены авторизация, статусы операций и ошибки; **5** - учтены webhook и другие условия взаимодействия, предусмотренные спецификацией |
| **2. Генерация интеграционного сервиса** | **25** | **10** - сервис формирует и отправляет запросы к API; **8** - обрабатывает ответы, статусы операций и ошибки; **7** - поддерживает входящие уведомления и настройку параметров подключения |
| **3. Корректность преобразования данных** | **15** | **8** - корректно сопоставляются поля запросов, ответов и статусы операций; **7** - корректно обрабатываются форматы данных, обязательные и необязательные поля |
| **4. Универсальность решения** | **15** | **7** - решение работает со спецификациями, отличающимися набором методов, полей и параметров; **5** - основная логика не привязана к одному конкретному провайдеру; **3** - предусмотрено добавление новых правил и обработка неподдерживаемых элементов спецификации |
| **5. Понятность использования и демонстрации** | **15** | **6** - решение можно запустить и получить результат через понятный последовательный процесс; **5** - есть необходимая информация по настройке, авторизации и использованию сгенерированной интеграции; **4** - результат работы и возникающие ошибки представлены в понятном виде |
| **6. Качество технической реализации** | **10** | **6** - код имеет понятную структуру и разделение основных компонентов; **4** - предусмотрена обработка ошибок при разборе спецификации и генерации файлов; |
| **ИТОГО** | **100** |  |

### Жюри

#### Технические жюри

| **Критерий** | **Баллы** | **Конкретная разбалловка** |
| --- | --- | --- |
| **1. Разбор API-спецификации** | **20** | **5** - определены доступные методы API; **5** - распознаны параметры запросов и ответов; **4** - распознаны требования к авторизации; **3** - распознаны статусы и ошибки; **3** - распознаны webhook и дополнительные условия взаимодействия. |
| **2. Генерация интеграционного сервиса** | **25** | **5 **- сгенерированный сервис, соответствующий контракту Provider::BaseService **5** - формирование и отправка запросов; **4** - получение и обработка статуса операции; **4** - обработка ответов и ошибок; **4** - обработка входящих уведомлений; **3** - конфигурация адресов и параметров подключения. |
| **3. Корректность преобразования данных** | **15** | **5** - корректное сопоставление статусов; **4** - корректное сопоставление полей запросов и ответов; **3** - корректное преобразование форматов и единиц данных; **3** - корректная обработка обязательных и необязательных полей. |
| **4. Универсальность и адаптируемость** | **10** | **5** - поддерживаются спецификации с разным набором методов и полей; **3** - логика генерации отделена от особенностей конкретного провайдера; **1** - предусмотрено расширение шаблонов и правил генерации; **1** - система сообщает о неподдерживаемых или неоднозначных элементах спецификации. |
| **5. Генерация документации и тестовых материалов** | **13** | **5** - описание настройки и авторизации; **4** - описание методов, статусов и ошибок; **4** - после генерации сервиса есть также примеры запросов, ответов и уведомлений в файле fixtures.json . |
| **6. Удобство использования и демонстрация** | **10** | **4** - понятный способ запуска; **3** - результат создается за один последовательный процесс; **3** - пользователь получает понятные сообщения о результате и ошибках. |
| **7. Качество реализации** | **10** | **4** - понятная архитектура и читаемый код; **3** - предусмотрена обработка ошибок при разборе спецификации и генерации файлов; **3** - инструкция по запуску и настройке. |
| **Итого** | **103** |  |

#### Отраслевые критерии

| **Критерий** | **Максимум, баллов** | **Разбалловка** |
| --- | --- | --- |
| **1. Реализация дополнительных идей** |  | **6** - Свободный выбор |
| **2. Выступление команды (умение презентовать результаты своей работы, строить логичный, понятный и интересный рассказ для презентации результатов своей работы)** |  | **6 **- Хорошее выступление и презентация |
| **3. Полнота проработки решения** |  | **8** - Решение выполнено полностью покрывает поставленную задачу |
| **ИТОГО** | **20** |  |
