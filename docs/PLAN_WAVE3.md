# Волна 3 — полнота и инструкция

## Статус

Завершена 2026-09-06.

- `README.md` описывает назначение, ограничения, архитектуру, запуск, все CLI-флаги, overrides, расширение
  словарей, добавление регрессионной спеки и troubleshooting.
- `docs/ASSUMPTIONS.md` содержит подтверждённые факты и 23 дефолта со ссылками на точки изменения.
- `cancel_request` и `fetch_balance` генерируются публичными методами вне контракта и документируются отдельной
  секцией `INTEGRATION.md`; поведение закреплено unit- и golden-тестами.
- S3 `numstatus.yaml` проходит полный pipeline: OAuth2 client credentials, callback, подпись в body и числовые
  статусы; golden и исполняемый RSpec находятся в `spec/golden/numstatus`.
- Добавлены non-root `Dockerfile`, `compose.yaml`, `.dockerignore` и комментированный
  `examples/overrides.example.yml`.
- Ненужное направление создания отдельного пользовательского приложения полностью исключено из scope,
  зависимостей и последующих волн.

## Проверка

```bash
bundle exec rake check
bundle exec ruby bin/integrate --spec spec/fixtures/specs/numstatus.yaml --output /tmp/wave3 --run-spec
docker build -t provider-integrator .
```

Проверено на Ruby 4.0.6 локально и на `ruby:3.3-slim` в контейнере:

- `772 examples, 0 failures`; `218 files inspected, no offenses detected`; пять словарей `ok`;
- S3: `23 examples, 0 failures`, exit 0, шесть файлов;
- новый чистый каталог: `bundle install --local` и NovaPay `--run-spec` — `20 examples, 0 failures`;
- Docker image собирается, запускается как `integrator`, Compose config валиден, контейнерный NovaPay RSpec — 20/0.
