# frozen_string_literal: true

RSpec.describe ProviderIntegrator::Generator::DocumentationGenerator do
  let(:guide) { GenerationHelpers.novapay_file(:documentation) }
  let(:headings) { guide.scan(/^## (.+)$/).flatten }

  it "carries every section docs/PLAN.md 6 asks for, the required ones by their reference names" do
    aggregate_failures do
      expect(guide).to start_with("# NovaPay Integration Guide\n")
      expect(headings).to include(*ProviderIntegrator::TemplateData::Documentation::REQUIRED_SECTIONS)
      expect(headings).to include("Настройка", "Методы вне контракта", "Маппинг полей", "Допущения")
    end
  end

  it "documents authorization and configuration the way the reference does" do
    aggregate_failures do
      expect(guide).to include("- Тип: api_key (`ApiKeyAuth`)", "- Header: `X-API-Key: <credentials.api_key>`",
                               "- Хранение: `providers.credentials` (encrypted), ключи: `api_key`, `callback_secret`")
      expect(guide).to include("| `NOVAPAY_BASE_URL` | ENV | `https://api.sandbox.novapay.example/v1` (sandbox) |")
      expect(guide).to include("| `credentials[:callback_secret]` | providers.credentials | секрет подписи webhook |")
    end
  end

  it "lists the methods with endpoints, idempotency and the extras" do
    aggregate_failures do
      expect(guide).to include("| create_request | POST /payouts | Создать выплату | Idempotency-Key header |")
      expect(guide).to include("| fetch_status | GET /payouts/{payout_id} | Получить статус выплаты | - |")
      expect(guide).to include("| process_callback | POST /webhooks/payout | Webhook уведомление о смене статуса | " \
                               "X-NovaPay-Signature |")
      expect(guide).to include("| cancel_request | POST /payouts/{payout_id}/cancel | Отменить выплату | cancel " \
                               "| 0.9 |")
      expect(guide).to include("| fetch_balance | GET /balance | Баланс провайдера | balance | 0.9 |")
    end
  end

  it "maps fields with their platform sources, units and conditional requirements" do
    aggregate_failures do
      expect(guide).to include("### Запрос create_request (request_method `sbp`)")
      expect(guide).to include("| amount | `operation.amount` x 100 (minor units) | да | Сумма в копейках |")
      expect(guide).to include("| recipient.bank_code | `operation.payout_requisite['sbp']['bank_code']` | " \
                               "при recipient.type = sbp | БИК банка (обязателен для type=sbp) |")
      expect(guide).to include("| id | provider_operation_id | string | сохраняется как provider_operation_id |")
    end
  end

  it "tabulates statuses and errors with the platform actions from the canon" do
    aggregate_failures do
      expect(guide).to include("| pending | in_progress |", "| completed | approved |", "| cancelled | rejected |")
      expect(guide).to include("| 401 | unauthorized | invalid_credentials | alert ops, block provider | - |")
      expect(guide).to include("| 429 | rate_limit_exceeded | rate_limit | retry with backoff | " \
                               "Retry-After из заголовка |")
      expect(guide).to include("- 409 на `POST /payouts` - идемпотентный дубль")
    end
  end

  it "states the signature formula, the payload convention and the gateway config" do
    aggregate_failures do
      expect(guide).to include("HMAC-SHA256(body, callback_secret) -> hex -> X-NovaPay-Signature (header)")
      expect(guide).to include("**не указаны в спеке (W301)**")
      expect(guide).to include("'raw_body' => '<сырое тело>'")
      expect(guide).to include("| payout.completed | approved | `approve_operation` |")
      expect(guide).to include("{ \"external_method\": \"sbp_payout\", \"gateway\": \"RUB_SBP_WITHDRAW\" }")
    end
  end

  it "lists every warning and critical inference under «Требует подтверждения» with a place in the code" do
    section = guide.split("## Требует подтверждения").last.split("## ").first

    aggregate_failures do
      expect(section.scan(/^\| (W\d{3}|I\d{3}) \|/).flatten).to eq(%w[W301 W402 W402 I201 I301 I401 I403])
      expect(section).to include("| verify_signature! |", "| check_conditions, REQUIRED_REQUISITES |",
                                 "| build_*_payload, MIN_AMOUNT |")
      expect(section).to include("description: копейках; error example (422): kopecks; minimum: 100000")
    end
  end

  it "explains a missing webhook and a Bearer scheme for other providers" do
    bearer = GenerationHelpers.generate_fixture("bearerpay").file(:documentation).content

    aggregate_failures do
      expect(bearer).to include("- Header: `Authorization: Bearer <credentials.token>`")
      expect(bearer).to include("Спека не описывает webhook (W304)")
      expect(bearer).to include("| process_callback | - | заглушка: webhook не найден (W304) | - |")
    end
  end
end
