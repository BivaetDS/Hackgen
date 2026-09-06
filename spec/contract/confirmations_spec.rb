# frozen_string_literal: true

# The report and guide are the two jury-facing views of critical analysis decisions. This table is
# intentionally independent of their shared presenter so omissions cannot make both views agree
# while silently dropping a required warning or inference.
expected_confirmations = {
  "novapay" => %w[W301 W402 W402 I201 I301 I401 I403],
  "bearerpay" => %w[W101 W105 W202 W304 W402 W402 W402 W402 W403 I201 I401 I403],
  "rublepay" => %w[W101 W202 W202 W402 W403 W403 I201 I301 I401 I402 I402 I402 I402 I402 I402 I402 I402 I403],
  "numstatus" => %w[W101 W202 W203 W204 W402 W402 W402 W402 W403 I201 I301 I401 I403],
  "cardpay" => %w[W105 W201 W202 W203 W402 W402 I201 I301 I401 I401 I403],
  "legacy_swagger2" => %w[W101 W101 W201 W203 W402 W402 W402 W402 W403 I201 I301 I401 I403]
}

RSpec.describe "critical inference confirmations" do
  def guide_codes(markdown)
    section = markdown.split(/^## Требует подтверждения\s*$/, 2).fetch(1).split(/^## /, 2).first
    section.scan(/^\| ([IWE]\d{3}) \|/).flatten
  end

  expected_confirmations.each do |name, expected|
    it "keeps the #{name} report, guide and IR event stream in sync" do
      spec = ProviderIntegrator::Parser.call!(path: fixture_path("specs", "#{name}.yaml"))
      result = ProviderIntegrator::Generator.call(spec:, output_dir: "output/#{name}")
      report = JSON.parse(result.file(:report).content)
      report_codes = report.fetch("requires_confirmation").map { |item| item.fetch("code") }
      critical = ProviderIntegrator::TemplateData::Confirmations::CRITICAL_INFOS
      event_codes = spec.events.select { |event| event.warning? || critical.include?(event.code) }.map(&:code)

      aggregate_failures do
        expect(result).to be_success
        expect(report_codes).to eq(expected)
        expect(guide_codes(result.file(:documentation).content)).to eq(expected)
        expect(event_codes).to eq(expected)
      end
    end
  end
end
