# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.3"

# Every dependency is open source (MIT unless noted). Nothing here performs network
# calls at generation time.
gem "diff-lcs", "~> 1.6"         # MIT (dual MIT/Artistic/GPL; used under MIT) - regeneration diff
gem "json_schemer", "~> 2.5"     # MIT - validates dictionaries, overrides, IR and fixtures
gem "openapi3_parser", "~> 0.10" # MIT - structural validation of OpenAPI 3.x documents
gem "pastel", "~> 0.8"           # MIT - CLI colours
gem "rake", "~> 13.4"            # MIT - task runner
gem "thor", "~> 1.5"             # MIT - CLI framework
gem "tty-table", "~> 0.12"       # MIT - CLI tables
gem "zeitwerk", "~> 2.8"         # MIT - code loader
# RuboCop runs in-process (stdin API) to normalize generated Ruby; it never touches the network.
gem "rubocop", "~> 1.90", require: false # MIT - formatter for generated code and repo linter

group :test do
  gem "rspec", "~> 3.13"    # MIT - test framework
  gem "webmock", "~> 3.26"  # MIT - forbids real HTTP in specs
end

group :development do
  gem "rubocop-rake", "~> 0.7", require: false   # MIT - Rakefile cops
  gem "rubocop-rspec", "~> 3.10", require: false # MIT - RSpec cops
end
