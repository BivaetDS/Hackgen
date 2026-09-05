# frozen_string_literal: true

# docs/PLAN.md section 3.3 is the human-readable registry; lib/provider_integrator/events.rb is the
# executable one. Parsing the table here keeps them from drifting apart in either direction.
RSpec.describe "event registry documentation" do
  # { code => [documented levels] } from every table row of section 3.3; "E001–E009" rows expand.
  def documented_codes
    row = /\A\|\s*([EWI]\d{3})(?:[–-]([EWI]\d{3}))?\s*\|\s*(error|warning|info)\s*\|/
    registry_section.each_line.with_object({}) do |line, codes|
      match = row.match(line.strip) or next
      first, last, level = match.captures
      range_codes(first, last || first).each { |code| (codes[code] ||= []) << level }
    end
  end

  def registry_section
    ProviderIntegrator::Files.read(repo_path("docs", "PLAN.md")).split("### 3.3").fetch(1).split("\n## ").first
  end

  def range_codes(first, last)
    (first[1..].to_i..last[1..].to_i).map do |number|
      format("%{prefix}%{number}", prefix: first[0], number: format("%03d", number))
    end
  end

  it "documents exactly the codes the registry defines" do
    expect(documented_codes.keys.sort).to eq(ProviderIntegrator::Events.codes)
  end

  it "agrees with the registry on the level of every code" do
    documented_codes.each do |code, levels|
      expect(levels.uniq).to eq([ProviderIntegrator::Events.level(code)]), "#{code}: docs say #{levels.uniq}"
    end
  end

  it "documents each E001-E009 code individually" do
    individual = documented_codes.select { |code, levels| code.start_with?("E00") && levels.size >= 2 }
    expect(individual.keys).to match_array(%w[E001 E002 E003 E004 E005 E006 E007 E008 E009])
  end
end
