# Промпты для Claude Code

Как пользоваться: положи содержимое папки `claude_code_kit/` в корень репозитория (CLAUDE.md, `.claude/skills/`, `docs/`). Запусти `claude` в корне. Сначала отправь **Промпт 0** целиком. Дальше — по одному промпту на волну, не переходя к следующему, пока Claude Code не отчитался о выполнении критерия волны и ты не проверил его сам (`bundle exec rspec`, прогон CLI).

Стратегия: один большой промпт «сделай всё» даёт худший результат, чем последовательность волн с проверкой между ними. Claude Code хорошо держит контекст внутри волны и теряет его между большими объёмами; `CLAUDE.md` и `docs/PLAN.md` — его долговременная память.

---

## Промпт 0 — вход в проект (отправить первым)

```
Ты — ведущий Ruby-разработчик команды на финтех-хакатоне. Мы строим provider-integrator: детерминированный генератор интеграций платёжных провайдеров из OpenAPI. Цель — первое место по опубликованной разбалловке.

Сначала прочитай полностью, ничего не пропуская:
1. CLAUDE.md — жёсткие ограничения и инварианты проекта.
2. docs/TZ.md — техническое задание с эталонными файлами (сервис, INTEGRATION.md, fixtures.json, вывод CLI) и полной таблицей баллов экспертов и жюри.
3. docs/PLAN.md — архитектура, контракты модулей, алгоритмы, реестр событий, канонический контракт Space Payments, подтверждённые ответы экспертов, волны работ, матрица баллов.
4. docs/provider_api.yaml — входная спецификация NovaPay.
5. .claude/skills/ruby-cli-conventions/SKILL.md — стиль кода.

После чтения, до написания кода, выдай мне:
- краткий пересказ ограничений хакатона своими словами (чтобы я убедился, что ты понял запрет на нейросети в рантайме и требование «всё на Ruby»);
- список из 5–7 мест, где план, ТЗ или эталон противоречат друг другу или неполны, и какое решение ты предлагаешь для каждого (приоритет: ТЗ → ответы экспертов в PLAN §4 → план);
- список вопросов ко мне, без ответа на которые ты не можешь начать волну 0. Если вопросов нет — так и скажи.

Отдельно — про проектный skill `.claude/skills/ruby-cli-conventions/SKILL.md`. Он написан заранее как черновик и не проверялся на реальном коде. Сделай сам, без моего участия:
- выполни /skills и убедись, что skill загружен как project-skill; если нет — объясни причину (структура папки, фронтматтер) и исправь;
- проверь, достаточно ли точно поле description описывает моменты, когда его нужно подгружать (правка .rb, .erb, Gemfile, Rakefile, spec/*, .rubocop.yml, dictionaries/*.yml). Если считаешь, что оно сработает не всегда, перепиши description — конкретно, с перечислением типов файлов и задач;
- прочитай сам skill критически: отметь утверждения, которые ты считаешь спорными или непроверенными (например, использование Data.define с блоком для всех моделей, конкретные пороги RuboCop), и предложи правки. Не применяй их пока — только список; применишь после волны 1, когда будет реальный код.

Не начинай писать код до моего подтверждения.
```

---

## Промпт 1 — волна 0: контракты и скелет

```
Начинаем волну 0 из docs/PLAN.md §10. Сделай:

1. Скелет репозитория по PLAN §2: Gemfile (зависимости из PLAN §2, с лицензией в комментарии у каждой), .rubocop.yml, Rakefile, bin/integrate, lib/provider_integrator.rb с Zeitwerk, пустые каталоги с .keep, spec/spec_helper.rb с WebMock.disable_net_connect!.
2. Модели из PLAN §3: Event, Result, ProviderSpec, Operation, FieldMapping — как Data/Struct с to_h/from_h и стабильной JSON-сериализацией (сортировка ключей). Юнит-тесты на round-trip JSON.
3. Реестр событий PLAN §3.3 как lib/provider_integrator/events.rb: константы кодов, уровни, шаблоны сообщений. Тест, что каждый код уникален и имеет уровень.
4. dictionaries/canonical_contract.yml по PLAN §4, dictionaries/operations.yml, fields.yml, statuses.yml, errors.yml — начальное наполнение по PLAN §5 (синонимы, веса, действия ошибок). Тест, что словари загружаются через Psych.safe_load_file и валидны по json_schemer-схеме, которую ты тоже напиши.
5. spec/fixtures/normalized_novapay.json — вручную составленный ожидаемый IR для NovaPay ровно по примеру из PLAN §3.2, дополненный до всех 5 операций, полей, статусов, ошибок с действиями, webhook. Это эталон, с которым будет сравниваться парсер.
6. spec/fixtures/specs/novapay.yaml — копия docs/provider_api.yaml.
7. docs/ASSUMPTIONS.md по PLAN §4 (подтверждённое и допущения с дефолтами).
8. Rake-задачи: spec, rubocop, golden:update, check (всё вместе).

Критерий завершения: bundle exec rake check зелёный; JSON round-trip моделей стабилен; normalized_novapay.json валиден по схеме ProviderSpec. Отчитайся списком созданных файлов и результатом rake check. Ничего из волны 1 не начинай.
```

---

## Промпт 2 — волна 1: сквозной проход на NovaPay

Разбей на три подпромпта, если Claude Code начинает терять контекст. Порядок: парсер → генератор → CLI.

```
Волна 1, часть A — парсер и анализаторы (PLAN §5, владелец Dev A).

Реализуй lib/provider_integrator/parser/ и normalizer/:
- Loader: Psych.safe_load, лимиты размера/глубины, E001–E009 с указанием секции.
- Validator: json_schemer по OpenAPI 3.0 schema + Openapi3Parser.load(hash).valid?; ошибки → события с путём.
- SpecReader на openapi3_parser: операции, параметры, requestBody, responses с headers, securitySchemes, servers, callbacks. Хэш-фолбэк (op["requestBody"]) там, где объектный API неочевиден.
- OperationExtractor / SchemaExtractor: плоский список полей с путями (recipient.phone), type/format/enum/pattern/min/max/required/description/example; oneOf/anyOf/discriminator как ветки.
- Normalizer: OperationClassifier (взвешенный скоринг, приоритет override → x-space-payments-operation → скоринг → callbacks), Authentication, FieldMapper, MoneyUnits (три сигнала), ConditionalRequired (структурно + regex по описанию), StatusMapper, ErrorClassifier (канонический код + действие + retry_after: header + 409 по структуре ответа), WebhookAnalyzer (path-эвристика и callbacks; подпись: header/algorithm/encoding/canonicalization), Confidence.
- Overrides: чтение overrides.yml по схеме из PLAN §5, применение с пометкой source: override.
- Parser.call(path:, overrides:) → Result(ProviderSpec, events).

Критерий: Parser.call на novapay.yaml даёт IR, равный spec/fixtures/normalized_novapay.json (aggregate_failures, точечные различия — только если ты докажешь, что эталон в фикстуре неверен, и тогда поправь фикстуру с объяснением в коммите). Обязательные события на NovaPay: W301 (канонизация HMAC), W402 (bank_code/card_number из описания), W102 (cancel, balance), info по единицам суммы с тремя сигналами. Unit-тесты на каждый анализатор: NovaPay, альтернатива, неоднозначность.
```

```
Волна 1, часть B — генератор (PLAN §6, владелец Dev B).

Реализуй lib/provider_integrator/generator/, template_data/, templates/:
- ServiceGenerator + service.rb.erb: структура строго как эталон в docs/TZ.md (class Provider; class <Slug>Service < BaseService; BASE_URL = ENV.fetch; create_request(operation, request_method = 'create') с case request_method по способам выплаты из enum реквизитов; fetch_status; process_callback с verify_signature!(payload) по конвенции raw_body/headers из PLAN §4; check_conditions с super, порогом из minimum с учётом единиц и условной обязательностью; private build_*_payload с compact, parse_*_response, auth_headers, STATUS_MAP, ERROR_MAP, ERROR_ACTIONS; методы вне контракта с пометкой). Комментарии evidence у критичных выводов, TODO(confidence …) при средней/низкой.
- BaseContractGenerator + base_contract.rb.erb: заглушки Provider::BaseService, Result, Operation, RateLimitError, UnauthorizedError по canonical_contract.yml, с шапкой «ДОПУЩЕНИЕ».
- DocumentationGenerator + integration.md.erb: все секции из PLAN §6 включая «Требует подтверждения».
- FixturesGenerator + fixtures.json.erb: структура эталона; источники examples → property examples → детерминированные по типу → "_synthetic": true; валидация json_schemer против схем спеки.
- ReportGenerator: generation_report.json (события, уверенности, evidence, overrides, SHA-256).
- OutputValidator по PLAN §8: Prism, JSON.parse, наследование, 4 метода, нет остатков ERB, секции INTEGRATION.md, rubocop -A на сервисе.
- Generator.call(spec:, provider:, output_dir:) → Result(files, events). Генератор читает только ProviderSpec; тест, что он работает от spec/fixtures/normalized_novapay.json без парсера.

Критерий: файлы для NovaPay визуально соответствуют эталону из docs/TZ.md (положи эталон рядом и покажи мне diff с пояснением каждого сознательного отличия), OutputValidator зелёный, golden spec/golden/novapay/* создан, тест детерминизма (два прогона → одинаковые SHA) проходит.
```

```
Волна 1, часть C — CLI и конвейер (PLAN §7, владелец Dev C).

Реализуй Pipeline (Parser → Generator → OutputValidator → запись), CLI на Thor с флагами и exit codes из PLAN §7, Reporter с выводом, текстуально близким к эталонному транскрипту в docs/TZ.md (детали — под --verbose), --analyze-only (печать IR JSON), --strict, --overrides. Стек-трейс — только с --verbose. Интеграционный тест: bin/integrate на novapay.yaml из чистого каталога → 3 обязательных файла + report + base_contract, exit 0, вывод содержит «Found 5 endpoints», «Auth: ApiKeyAuth (header: X-API-Key)», «Webhook signature: X-NovaPay-Signature (HMAC-SHA256)».

Критерий волны 1 целиком: ./bin/integrate --spec docs/provider_api.yaml --provider novapay работает end-to-end, rake check зелёный. Покажи полный вывод команды и дерево output/.

После выполнения критерия — актуализация skill, тоже сам:
1. Прочитай lib/, spec/, templates/ и сравни с .claude/skills/ruby-cli-conventions/SKILL.md. Всё, что в skill написано не так, как реально сложилось в коде (структура моделей, форма Result, способ загрузки словарей, пороги RuboCop, паттерны в спеках), — исправь в skill под фактические конвенции. Skill описывает код, а не наоборот; исключение — правила из CLAUDE.md (детерминизм, безопасность ввода, запрет Rails-измов), они не меняются, и если код им противоречит — правь код.
2. Добавь в skill 3–5 конкретных примеров из нашего же кода (короткие фрагменты с путями к файлам) вместо абстрактных.
3. Убери из skill то, что оказалось не нужно, и добавь то, что ты сам повторял мне несколько раз по ходу волны.
4. Если CLAUDE.md устарел по фактам (имена классов, пути, команды) — обнови и его, но не трогай раздел «Жёсткие ограничения».
5. Покажи diff обоих файлов одним сообщением с пояснением по каждому изменению.
```

---

## Промпт 3 — волна 2: доказательства

```
Волна 2 из PLAN §10. Цель — доказать универсальность и надёжность. Детальный актуальный scope и
критерии этой волны находятся в `docs/PLAN_WAVE2.md` и заменяют сокращённый список ниже.

1. Напиши spec/fixtures/specs/bearerpay.yaml и rublepay.yaml строго по описанию S1 и S2 в PLAN §9 (другие пути, Bearer, без webhook, статусы NEW/SENT/DONE/DECLINED; decimal-строка в рублях, pay-in, oneOf+discriminator в реквизитах). Спеки должны быть валидными OpenAPI 3.0 и реалистичными — как будто их написал другой провайдер.
2. Напиши spec/fixtures/specs/invalid_*.yaml: битый YAML, нет paths, неразрешимый $ref, нет create-операции. Тест: понятное сообщение с кодом E…, exit 3, без стек-трейса.
3. Прогони S1, S2 через весь конвейер. Всё, что падает или генерирует NovaPay-специфику, — исправь в lib/ (не в спеках). Добавь тест анти-хардкода: grep -ri novapay lib/ пуст; шаблоны не содержат провайдерских строк.
4. Golden для S1, S2, invalid; тест детерминизма на всех спеках.
5. RspecGenerator + provider_spec.rb.erb: сгенерированный <slug>_service_spec.rb с WebMock поверх fixtures.json (201, 409 как успех, 422, 429 с Retry-After, fetch_status, callback approve/reject, неверная подпись). Тест, что сгенерированный spec запускается в подпроцессе с base_contract.rb и зелёный для NovaPay и S1/S2.
6. Каждое критичное решение (единицы, required_if, подпись, статусы) видно в generation_report.json и в INTEGRATION.md «Требует подтверждения» даже при высокой уверенности.

Критерий: rake check зелёный на NovaPay + S1 + S2 + invalid_*; сгенерированные RSpec зелёные; анти-хардкод зелёный. Дай таблицу: спека → операции распознаны → auth → статусы → warnings. После этого — заморозка ядра: новые фичи только в следующих волнах, ядро — только багфикс.
```

---

## Промпт 4 — волна 3: полнота и инструкция

```
Волна 3 из PLAN §10.

1. README.md: назначение, ограничения, архитектура (схема конвейера), локальный запуск за 3 команды, CLI с примерами всех флагов, overrides.yml с примером, поддерживаемые и неподдерживаемые элементы OpenAPI (с кодами событий), как добавить новое правило в словари, как добавить спеку в регрессию, troubleshooting. Проверь инструкцию: выполни её сам в чистом каталоге (git clone в /tmp, bundle install, bin/integrate).
2. docs/ASSUMPTIONS.md актуализируй; каждый дефолт ссылается на место в коде/yml, где он меняется.
3. cancel/balance как публичные методы вне контракта в сервисе и отдельная секция в INTEGRATION.md.
4. S3 numstatus.yaml по PLAN §9 (числовые статусы, вебхук через callbacks, подпись в теле, OAuth2 client credentials) + поддержка в анализаторах + golden.
5. Dockerfile (ruby:3.3-slim, не root, bundle install, ENTRYPOINT bin/integrate), compose.yaml с монтированием ./specs и ./output. Проверь docker build и прогон.
6. examples/overrides.example.yml с комментариями.

Критерий: чистая машина запускает проект по README без вопросов; S3 зелёная; rake check зелёный.
```

---

## Промпт 5 — волна 4: сильные доп. идеи

```
Волна 4 из PLAN §10 — доп. идеи для отраслевого жюри. Делай по одной, после каждой rake check.

1. RegenerationDiff и флаг --diff: сравнение существующего output с новым, обнаружение ручных правок (W601), вывод unified diff, без перезаписи.
2. S4 cardpay.yaml (OpenAPI 3.1, type как массив, несколько create-операций) и S5 legacy_swagger2.yaml (Swagger 2.0 → конвертер в 3.0 внутри парсера, W103; нет operationId; нет examples; form-urlencoded). Golden для обеих.
3. S6: возьми реальную публичную OpenAPI-спеку платёжного API (лицензионно чистую, укажи источник в файле), урежь до 5–8 операций, проведи через конвейер, зафиксируй golden и список warnings. Это самый убедительный тест для жюри.

Критерий: S4–S6 в регрессии; --diff показывает ручную правку в сгенерированном файле.
```

---

## Промпт-довесок к каждой волне начиная со второй

Добавляй в конец промпта каждой следующей волны:

```
В конце волны, после выполнения критерия: сверь .claude/skills/ruby-cli-conventions/SKILL.md и CLAUDE.md с фактическим кодом и обнови их по правилам из волны 1 (skill описывает код; ограничения CLAUDE.md неприкосновенны). Если в этой волне появился новый повторяющийся паттерн (например, как пишутся синтетические спеки или как устроен golden-тест) — зафиксируй его в skill с примером из кода. Покажи diff.
```

---

## Как разговаривать с Claude Code по ходу

- Если он предлагает «упростить» контракт `ProviderSpec` или убрать событие из реестра — не соглашайся без причины: контракт общий для троих.
- Если он тянет ActiveSupport или Rails-гем «для удобства» — откажи: проект plain Ruby, см. skill.
- Если тесты падают, а он предлагает `skip`/`pending` — требуй причину и фикс, кроме внешних причин (нет Docker).
- После каждой волны сам запусти `bundle exec rake check` и `./bin/integrate --spec docs/provider_api.yaml --provider novapay` — не верь отчёту без проверки.
- Полезные слэш-команды: `/ruby-cli-conventions` перед большими правками шаблонов; `/skills` — убедиться, что skill загружен.
