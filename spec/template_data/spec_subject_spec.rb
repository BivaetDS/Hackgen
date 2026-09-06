# frozen_string_literal: true

# The generated spec reverses provider fixture amounts into a platform Operation and then applies
# the same conversion again when it predicts the HTTP request. That round-trip is tested here for
# every supported conversion shape rather than only through generated source strings.
RSpec.describe ProviderIntegrator::TemplateData::SpecSubject do
  def parsed(name)
    ProviderIntegrator::Parser.call!(path: fixture_path("specs", "#{name}.yaml"))
  end

  def data_for(spec)
    context = ProviderIntegrator::Generator::Context.new(spec:, output_dir: "output/#{spec.provider.slug}")
    ProviderIntegrator::TemplateData::ServiceSpec.new(context)
  end

  def amount_source(data)
    operation = data.context.create_operation
    field = operation.request_fields.find { |item| item.canonical == "amount" }
    scope = ProviderIntegrator::TemplateData::Scope.build(branch: data.subject.request_method)
    source = ProviderIntegrator::TemplateData::FieldSource.new(operation, canon: data.canon,
                                                                          context: data.context, scope:)
    [source.for(field), field]
  end

  def with_conversion(spec, type:, value: nil)
    create = spec.operation_for("create_request")
    fields = create.request_fields.map do |field|
      next field unless field.canonical == "amount"

      field.with(conversion: field.conversion.with(type:, value:))
    end
    changed = create.with(request_fields: fields)
    spec.with(operations: spec.operations.map { |operation| operation.equal?(create) ? changed : operation })
  end

  it "builds the full platform operation and reverses a multiply conversion" do
    data = data_for(parsed("novapay"))
    source, = amount_source(data)

    aggregate_failures do
      expect(data.subject.amount).to eq(15_000)
      expect(data.subject.sent_value(source)).to eq(1_500_000)
      expect(data.subject.operation_lines.join("\n"))
        .to include("Provider::Operation.new(", "id: 'op_abc123'", "amount: 15000", "'sbp' => {")
    end
  end

  it "reverses and reapplies a decimal-string conversion" do
    data = data_for(parsed("rublepay"))
    source, = amount_source(data)

    expect([data.subject.amount, data.subject.sent_value(source)]).to eq([1500, "1500.00"])
  end

  it "round-trips an identity conversion without changing the fixture amount" do
    data = data_for(with_conversion(parsed("novapay"), type: "identity"))
    source, = amount_source(data)

    expect([data.subject.amount, data.subject.sent_value(source)]).to eq([1_500_000, 1_500_000])
  end
end
