# frozen_string_literal: true

require "tmpdir"

RSpec.describe ProviderIntegrator::Files do
  let(:dir) { Dir.mktmpdir("provider-integrator-files") }

  after { FileUtils.rm_rf(dir) }

  it "writes and reads bytes without newline translation, creating parent directories" do
    path = File.join(dir, "nested", "deeper", "out.txt")
    content = "line one\nline two\n\u0421\u0431\u0435\u0440\u0431\u0430\u043d\u043a\n"

    described_class.write(path, content)

    expect(File.binread(path)).to eq(content.b)
    expect(described_class.read(path)).to eq(content)
    expect(described_class.read(path).encoding).to eq(Encoding::UTF_8)
  end

  it "reads CRLF files verbatim" do
    path = File.join(dir, "crlf.txt")
    File.binwrite(path, "a\r\nb\r\n")

    expect(described_class.read(path)).to eq("a\r\nb\r\n")
  end
end
