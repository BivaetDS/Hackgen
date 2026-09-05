---
name: ruby-cli-conventions
description: Conventions for writing, reviewing and testing plain-Ruby (non-Rails) CLI tools and code generators in this repo — Thor CLI, Zeitwerk layout, Result objects, ERB templating with presentation models, deterministic output, RSpec golden tests, RuboCop. Use whenever creating or editing Ruby files, ERB templates, specs, Gemfile or Rakefile in provider-integrator.
---

# Ruby CLI / code-generator conventions

This project is **plain Ruby**, not Rails. Do not introduce ActiveSupport, ActiveRecord, concerns, controllers or Rails-isms. If a Rails skill is loaded, ignore its model/controller/job advice.

## 1. Project layout (Zeitwerk)

```
lib/provider_integrator.rb            # loader = Zeitwerk::Loader.for_gem; loader.setup
lib/provider_integrator/<module>/<class>.rb   # file name == constant name, snake_case
bin/integrate                         # #!/usr/bin/env ruby; require "provider_integrator"; ProviderIntegrator::CLI.start
```

- One class per file. Namespaces mirror directories: `lib/provider_integrator/normalizer/status_mapper.rb` → `ProviderIntegrator::Normalizer::StatusMapper`.
- Dictionaries in `lib/provider_integrator/dictionaries/*.yml`, loaded once via `Psych.safe_load_file(path, permitted_classes: [Symbol])` and frozen.

## 2. Objects and boundaries

- Models: `Data.define(...)` (Ruby 3.2+) or `Struct.new(..., keyword_init: true)`; always immutable, always `to_h` for JSON.
- Every module boundary returns a `Result`:
  ```ruby
  Result = Data.define(:value, :events) do
    def success? = events.none?(&:error?)
    def errors   = events.select(&:error?)
    def warnings = events.select(&:warning?)
  end
  Event = Data.define(:code, :level, :message, :location)  # level: :error | :warning | :info
  ```
- Service objects expose `self.call(**kwargs)` and are otherwise private. No global state, no class-level mutable memoization except frozen dictionaries.
- Exceptions only for unrecoverable input (`SpecError`) or template bugs (`GenerationError`); rescue them in `Pipeline`, never in analyzers.

## 3. Deterministic generation

- Never call `Time.now`, `Date.today`, `rand`, `SecureRandom`, `object_id`, `Hash#inspect`, `Set#to_a` (unordered) in anything that reaches output.
- Sort hash keys before serialising (`JSON.pretty_generate(deep_sort(h))`), keep operation order from the spec, keep field order from `properties`.
- Run `rubocop -A` on generated Ruby before writing it, so style is stable across runs.
- Golden tests compare bytes; if a legitimate change alters output, run `rake golden:update` and commit the diff with an explanation.

## 4. ERB templates

- Templates live in `lib/provider_integrator/templates/*.erb`; render with `ERB.new(src, trim_mode: "-")`.
- No logic in templates beyond `each`/`if`. Build a `TemplateData` object first (`template_data/*.rb`) that exposes plain strings/arrays already formatted (Ruby literals via `.inspect` for strings, `ruby_hash_literal(h)` helper for hashes).
- Every identifier derived from the spec passes through `Inflector`:
  - `snake_case`, `camel_case`, `constant_case`; strip non `[A-Za-z0-9_]`; prefix `_` if it starts with a digit; append `_field` if it is a Ruby reserved word (`class end def do if module self nil true false begin rescue yield`…).
  - Provider slug → `NovapayService`, `NOVAPAY_BASE_URL`, `novapay_service.rb`.
- After rendering, assert no `<%`/`%>` remain and `Prism.parse(src).success?`.

## 5. CLI (Thor)

- `class CLI < Thor; def self.exit_on_failure? = true; end`.
- Output through a `Reporter` object (pastel for colour; respects `--no-color` and non-TTY). Default output mirrors the reference transcript in `docs/TZ.md`; details under `--verbose`.
- Exit codes: 0 ok, 1 internal, 2 args, 3 spec error, 4 ambiguity in `--strict`, 5 generation, 6 write. Map exceptions to codes in one place.
- Never print a backtrace unless `--verbose`.

## 6. Security of untrusted specs

- `Psych.safe_load(yaml, permitted_classes: [], aliases: true)`; reject files > 5 MB and nesting > 64 levels.
- Treat `$ref` strings, `operationId`, property names, enum values, descriptions as data. They may end up in comments/strings/identifiers — always escape via `Inflector` or `.inspect`.
- Never `eval`, `instance_eval`, `send(user_string)`, `const_get(user_string)`, `system`/backticks with spec-derived content.

## 7. RSpec conventions

- `spec/<layer>/<class>_spec.rb` mirrors `lib/`. `describe ".call"` for service objects.
- Fixtures: full specs in `spec/fixtures/specs/*.yaml`, expected IR in `spec/fixtures/normalized_*.json`, golden outputs in `spec/golden/<spec>/`.
- Use `aggregate_failures` for IR assertions; use `match_golden("novapay")` custom matcher for outputs.
- WebMock enabled globally (`WebMock.disable_net_connect!`). Generated service specs run in a subprocess with `base_contract.rb` loaded first.
- Every analyzer spec has at least: happy path on NovaPay, one alternative spec, one ambiguous case asserting the right `W…` event.

## 8. RuboCop

- `.rubocop.yml`: `TargetRubyVersion: 3.3`, `Style/Documentation: Enabled` for `lib/`, `Metrics/MethodLength: 20`, `Metrics/ClassLength: 200`, `Layout/LineLength: 120`.
- Generated code is checked with the same config plus `Style/Documentation: false` and `Naming/VariableNumber: false`.

## 9. Review checklist (run before finishing any task)

1. `bundle exec rspec` green, `bundle exec rubocop` clean.
2. `grep -ri novapay lib/` returns nothing.
3. Two consecutive `bin/integrate` runs on `docs/provider_api.yaml` produce identical SHA-256 for every file.
4. New warnings/errors have a code in `docs/PLAN.md §3.3` and a spec asserting them.
5. Nothing at runtime calls an LLM, an external API, or a non-Ruby executable.
