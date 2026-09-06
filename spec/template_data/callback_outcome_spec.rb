# frozen_string_literal: true

# One answer for "what does process_callback report for this payload", shared by fixtures.json
# and the generated spec; it must follow the service's dispatch, not a looser reading.
RSpec.describe ProviderIntegrator::TemplateData::CallbackOutcome do
  let(:spec) { GenerationHelpers.novapay_spec }

  it "dispatches on the event when any event maps to a status, ignoring the status field" do
    aggregate_failures do
      expect(described_class.status(spec, { "event" => "payout.completed" })).to eq("approved")
      expect(described_class.status(spec, { "event" => "payout.failed", "status" => "completed" })).to eq("rejected")
      expect(described_class.status(spec, { "event" => "payout.unknown", "status" => "completed" })).to be_nil
      expect(described_class).not_to be_acknowledged(spec)
    end
  end

  it "falls back to the status field through STATUS_MAP with the default for unknown values" do
    by_status = spec.with(webhook: spec.webhook.with(events: [], event_field: nil))

    aggregate_failures do
      expect(described_class.status(by_status, { "status" => "completed" })).to eq("approved")
      expect(described_class.status(by_status, { "status" => "weird" })).to eq("in_progress")
      expect(described_class).not_to be_acknowledged(by_status)
    end
  end

  it "reports an acknowledged-only webhook when neither events nor a status field exist" do
    bare = spec.with(webhook: spec.webhook.with(events: [], event_field: nil, status_field: nil))

    aggregate_failures do
      expect(described_class.status(bare, { "anything" => 1 })).to be_nil
      expect(described_class).to be_acknowledged(bare)
    end
  end
end
