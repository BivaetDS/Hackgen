# Чек-поинт: что показывать и что говорить

Шпаргалка для восьмиминутного чек-поинта и для финала. Всё, что здесь написано, проверено на текущем коде.
Команды запускать из корня репозитория (`E:\Hackgenesis\Generator`), shell — Git Bash.

Перед выходом на связь один раз прогнать проверку и не закрывать терминал:

```bash
bundle exec rake check
```

Ожидаемо: `772 examples, 0 failures`, `218 files inspected, no offenses detected`, пять словарей `ok`.

---

## 1. Демонстрация — три команды

### Команда 1. Живой разбор эталонной спеки ТЗ

```bash
ruby bin/integrate --spec docs/provider_api.yaml --provider novapay --run-spec
```

```
Parsing spec... OpenAPI 3.0.3, NovaPay Payout API 1.0.0
Found 5 endpoints: POST /payouts, GET /payouts/{payout_id},
                   POST /payouts/{payout_id}/cancel, POST /webhooks/payout,
                   GET /balance
  create_request   -> POST /payouts (confidence 0.9)
  fetch_status     -> GET /payouts/{payout_id} (confidence 0.9)
  process_callback -> POST /webhooks/payout (confidence 0.92)
  extra            -> cancel, balance (outside the BaseService contract)
Auth: ApiKeyAuth (header: X-API-Key)
Webhook signature: X-NovaPay-Signature (HMAC-SHA256) on POST /webhooks/payout
Generating service...
Generating integration guide...
Generating test fixtures...
Generating service spec...
Generating contract stub and report...
Validating output... Ruby syntax OK, RuboCop 0 offenses, 4/4 contract methods, fixtures valid,
                     INTEGRATION.md 13 sections
Running generated spec... RSpec 20 examples, 0 failures
Completed with 3 warnings:
  W301 HMAC canonicalization for X-NovaPay-Signature is not specified ...
  W402 Conditional requirement inferred from description: recipient.bank_code
       is required when recipient.type equals sbp (createPayout)
  W402 ... recipient.card_number is required when recipient.type equals card
Requires confirmation: 7 items (W301, W402 x2, I201, I301, I401, I403) - see INTEGRATION.md
                       «Требует подтверждения» and generation_report.json
Output:
  ./output/novapay/novapay_service.rb
  ./output/novapay/INTEGRATION.md
  ./output/novapay/fixtures.json
  ./output/novapay/novapay_service_spec.rb
  ./output/novapay/base_contract.rb
  ./output/novapay/generation_report.json
```

**На что показать пальцем:**

| Строка вывода | Что это доказывает |
|---|---|
| `Found 5 endpoints` | распознаны все методы API |
| `create_request / fetch_status / process_callback` | три из четырёх методов контракта `Provider::BaseService` найдены сами |
| `extra -> cancel, balance` | операции вне контракта не потеряны и не мешают |
| `Auth: ApiKeyAuth (header: X-API-Key)` | авторизация выведена из `securitySchemes` |
| `Webhook signature: ... (HMAC-SHA256)` | вебхук и подпись распознаны |
| `W402 ... bank_code required when type=sbp` | условная обязательность выведена **из русского текста описания** |
| `W301` | кодировка подписи в спеке не указана — и мы это честно говорим, а не угадываем молча |
| `Validating output... Ruby syntax OK, ... 4/4 contract methods` | результат проверен до записи: Prism, RuboCop, JSON-схемы, секции документации |
| `Requires confirmation: 7 items` | критичные выводы (единицы, подпись, статусы, конфиг шлюза) не молчат даже при высокой уверенности |
| `Running generated spec... 0 failures` | записанный сервис реально выполняется через Net::HTTP + WebMock, без сети |
| `Output: ./output/novapay/...` | три файла ТЗ плюс RSpec, заглушка контракта и отчёт — за один прогон |

### Команда 2. Чужая спека, другой формат — код не менялся

```bash
ruby bin/integrate --spec spec/fixtures/specs/legacy_swagger2.yaml
```

Первая строка: `OpenAPI 3.0.3 (converted from Swagger 2.0), Kassira Merchant API 2.4`.

Что здесь сильного: это **Swagger 2.0**, он конвертируется в 3.0 на лету; в спеке вообще **нет
`operationId`** — операции классифицируются по путям и форме запроса; тела — `form-urlencoded`;
статусы свои (`REGISTERED / IN_WORK / PAID / RETURNED / REFUSED`). Ни строчки кода под неё не писалось.

Если есть лишние 20 секунд — показать ещё одну, с принципиально другой авторизацией:

```bash
ruby bin/integrate --spec spec/fixtures/specs/numstatus.yaml   # OAuth2, вебхук через callbacks, статусы числами
ruby bin/integrate --spec spec/fixtures/specs/bearerpay.yaml   # Bearer, вообще без вебхука
```

Матрица регрессии волны 2 (собрана из канонического IR `--analyze-only`; повторы warning сохранены):

| Спека | Операции распознаны | Auth | Статусы | Warnings |
|---|---|---|---|---|
| `novapay` | 5: create, status, cancel, webhook, balance | API key, header | 5 строковых | 3: W301, W402×2 |
| `bearerpay` | 6: create, status×2, cancel, list, unknown | Bearer | NEW/SENT/DONE/DECLINED | 9: W101, W105, W202, W304, W402×4, W403 |
| `rublepay` | 6: create, status, refund, webhook, list, unknown | API key, query | 7 строковых | 6: W101, W202×2, W402, W403×2 |
| `numstatus` (`tranzo`) | 6: create, status, cancel, balance, list, unknown; webhook из callbacks | OAuth2 client credentials | 0/1/2/3/4/−1 | 9: W101, W202, W203, W204, W402×4, W403 |
| `cardpay` | 7: create×2, status, cancel, balance, list, webhook | API key, header | 5 строковых | 6: W105, W201, W202, W203, W402×2 |
| `legacy_swagger2` (`kassira`) | 7: create, status, cancel, balance, list, unknown, webhook | API key, header | 6 строковых | 9: W101×2, W201, W203, W402×4, W403 |

### Команда 3. Битая спека — понятное сообщение, не стек-трейс

```bash
ruby bin/integrate --spec spec/fixtures/specs/invalid_bad_ref.yaml; echo "exit=$?"
```

```
The spec cannot be used:
  E005 Unresolvable $ref #/components/schemas/PayeeAccount
exit=3
```

Спека — недоверенный ввод: лимиты размера и глубины, `Psych.safe_load` без алиасов, собственный
резолвер `$ref`. Любая проблема — код `E…`, одна понятная строка в stderr и свой exit-код: 2 аргументы,
3 спека, 4 предупреждения под `--strict`, 5 сгенерированное не прошло валидацию (ничего не записано) либо
сгенерированный RSpec упал (шесть файлов сохранены для диагностики), 6 не удалось записать. Стек-трейс — только
с `--verbose`.

### Команда 4. Сгенерированные файлы

```bash
ls output/novapay && diff -r output/novapay spec/golden/novapay && echo identical
```

Вторая команда доказывает детерминизм: файлы из живого прогона байт в байт равны golden-копии в репозитории.
Открыть `output/novapay/novapay_service.rb` рядом с эталоном из `docs/TZ.md`: та же структура
(`BASE_URL`, четыре метода, `STATUS_MAP`, `ERROR_MAP`), но единицы суммы в хелпере, порог из `minimum`,
409 как успех, `Retry-After` из заголовка, `case request_method` по способам выплаты, `TODO(confidence 0.6)`
там, где спека молчит. `INTEGRATION.md` — секции эталона плюс «Требует подтверждения»; `fixtures.json` —
структура эталона, синтетика помечена `_synthetic`. Всё проверено `OutputValidator` (Prism, RuboCop,
json_schemer) и сгенерированным тестом, который гоняет `Provider::HttpClient` через WebMock без сети.

### Запасной вариант, если демо не запускается

```bash
cd output/novapay && bundle exec rspec novapay_service_spec.rb
```

20 примеров проверяют сам сгенерированный сервис: запросы, ответы, подпись webhook и условия.

---

## 2. Что говорить — 8 минут

**0:00–0:30 — что это.**
Детерминированный компилятор: OpenAPI провайдера → промежуточное представление (JSON) → Ruby-сервис
под контракт `Provider::BaseService` + `INTEGRATION.md` + `fixtures.json`. Сквозной проход готов и
покрыт тестами: одна команда — и шесть файлов на диске, генерация проверена до записи, затем выполняется
сгенерированный RSpec.

**0:30–1:30 — как это работает без нейросети.** *(самое важное — это прямое требование ТЗ)*
Никаких LLM и внешних API в рантайме. Правила, словари и взвешенный скоринг. Пример: операция
классифицируется по четырём независимым сигналам —

| сигнал | вес |
|---|---|
| `operationId` содержит основу `creat`/`созда` | +5 |
| путь или форма запроса (POST с телом без `{id}`) | +3 |
| тег | +2 |
| текст summary/description (только подтверждает) | +1 |

Уверенность = насколько лидер оторвался от второго места: `(best − second) / (best + 1)`.
Для `createPayout` это 9 баллов против 0 → 0.9. Всё воспроизводимо: два прогона дают одинаковый
SHA-256, есть тест на это.

**1:30–3:30 — что уже понимает.** Показать команду 1 и проговорить три вывода:

- **Единицы суммы.** Три независимых сигнала: слово «копейках» в описании (+3), `minimum: 100000`
  (+2), слово `kopecks` в примере ошибки 422 (+3). Восемь баллов против нуля → копейки, множитель 100.
  Если бы сигналов не хватило — множитель 1 и предупреждение, а не тихая догадка.
- **Условная обязательность.** Из строки «БИК банка (обязателен для type=sbp)» регулярным выражением
  выведено правило, и `type` разрешён в соседнее поле `recipient.type`, а не в верхний уровень.
- **Подпись вебхука.** Алгоритм HMAC-SHA256 в описании есть, кодировка и что именно хешируется — нет.
  Ставим `W301` и дефолт из канона, помеченный как требующий подтверждения.

**3:30–4:00 — главный принцип.**
Что не выводится из спеки — не угадывается. Каждый неоднозначный вывод получает код события
(`W301`, `W402`, `W403`…), попадает в отчёт и в раздел «Требует подтверждения». Критичные выводы —
единицы суммы, маппинг статусов, подпись, конфиг шлюза — сообщаются **всегда**, даже при высокой
уверенности, потому что молча ошибиться в них дороже всего.

**4:00–5:30 — универсальность.** Команда 2, при желании ещё одна.
Всё знание о провайдерах живёт в пяти YAML-словарях (`operations.yml`, `fields.yml`, `statuses.yml`,
`errors.yml`, `canonical_contract.yml`). В `lib/` нет ни одного упоминания NovaPay. Новое правило —
строка в словаре, без правки кода. Для случаев, когда спека молчит, есть `overrides.yml` с
фиксированными ключами, одинаковыми для всех провайдеров.

**5:30–6:00 — обработка ошибок.** Команда 3.

**6:00–6:30 — качество.**
`bundle exec rake check` — полный RSpec, линтер, валидация словарей по JSON-схемам. Каждый анализатор
покрыт тройкой «позитив / другой провайдер / неоднозначность». Есть тест, что разбор эталонной спеки
даёт представление, **байт в байт** равное написанному вручную эталону; все шесть сгенерированных RSpec
проходят в отдельных подпроцессах.

**6:30–7:00 — что дальше.**
Wave 3 закрыта: README, Docker/Compose, пример overrides и регрессия S3 готовы. Следующие усиления — `--diff`
для ручных правок и реальная публичная спека S6.

---

## 3. Вероятные вопросы

**«Точно нет нейросетей внутри?»**
Да. Зависимости: `openapi3_parser`, `json_schemer`, `thor`, `pastel`, `rspec` — все open-source, ни
одна не ходит в сеть при генерации. Логика — регулярные выражения, словари и арифметика скоринга,
это видно в `lib/provider_integrator/normalizer/`.

**«А если у провайдера другие статусы?»**
Строка в `statuses.yml`. Плюс есть подбор по токенам: `rejected_by_bank` сам становится `rejected` —
с пониженной уверенностью и пометкой в отчёте. Отрицания (`not_completed`) из этого правила исключены,
чтобы не получить `approved` из слова «completed».

**«Почему не openapi-generator?»**
Он делает клиент под свою модель, а нужен адаптер под конкретный контракт Space Payments: имена
методов, `STATUS_MAP`, действия по ошибкам. Плюс его ядро на Java, а по условиям большинство кода
должно быть на Ruby.

**«Что будет с полем, которого нет в словаре?»**
Не сопоставляется: `canonical: null`, и если поле обязательное — `W403` в отчёте. Явное «не знаю»
лучше тихой ошибки в проде.

**«BaseService вам не давали — как вы проверяете, что сгенерированное подойдёт?»**
Канон реконструирован по эталону из ТЗ и ответам экспертов, лежит в одном файле
`canonical_contract.yml`. Все допущения выписаны в `docs/ASSUMPTIONS.md` с указанием, где меняется
каждый дефолт. Если ответ провайдера разойдётся с допущением — правится один YAML, а не шаблоны.

**«Как убедиться, что результат воспроизводим?»**
Тест детерминизма: два прогона одной спеки дают одинаковый SHA-256. В коде запрещены `Time.now`,
`rand`, `object_id` во всём, что влияет на вывод; ключи JSON сортируются.

**«Сколько это экономит?»**
Ручная интеграция — 2–5 дней. Здесь разбор спеки занимает доли секунды, и на выходе разработчик
получает не пустой файл, а список из полутора десятков явно помеченных мест, которые надо
подтвердить у провайдера.

---

## 4. Честные места — сказать самим, не ждать вопроса

- Файлы пишутся в `./output/<slug>/`, повторный запуск перезаписывает свои же файлы без вопросов;
  обнаружение ручных правок (`--diff`, W601) — волна 4.
- `docs/ASSUMPTIONS.md` — 23 допущения по `BaseService`, потому что реального класса у нас нет.
  Это не пробел, а зафиксированный список вопросов к заказчику.
- Часть предупреждений на синтетических спеках (`W201`, `W202`) — это не баги, а ровно тот случай,
  ради которого предупреждения и сделаны: провайдер использует слово, которого нет в словаре.

---

## 5. Состояние на сейчас

| Волна | Что | Статус |
|---|---|---|
| 0 | Контракты, модели, реестр событий, словари, эталонный IR | готово |
| 1A | Парсер и анализаторы, CLI с разбором | **готово** |
| 1B | Генератор: сервис, `INTEGRATION.md`, `fixtures.json`, `base_contract.rb`, отчёт, валидатор, golden | **готово** |
| 1C | Полный конвейер и запись файлов через `bin/integrate` | **готово** |
| 2 | Golden на 6 спек, генерируемый RSpec, `--run-spec`, invalid/детерминизм/подтверждения | **готово; ядро заморожено** |
| 3 | README, Docker/Compose, overrides example, S3 и дополнительные методы | **готово** |
| 4 | `--diff`, S6 | по плану |
| 5 | Финальная защита | по плану |

Репозиторий: <https://github.com/BivaetDS/Hackgen>

Подробности: план — `docs/PLAN.md`, контракт представления — `docs/IR_CONTRACT.md`,
допущения — `docs/ASSUMPTIONS.md`, ТЗ с разбалловкой — `docs/TZ.md`.
