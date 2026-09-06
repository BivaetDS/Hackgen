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

- One class per file. Namespaces mirror directories: `lib/provider_integrator/normalizer/status_mapper.rb` → `ProviderIntegrator::Normalizer::StatusMapper`. A directory without a matching `.rb` is an implicit module (`template_data/documentation_sections/` → `TemplateData::DocumentationSections`).
- A `Data.define` needs no block for constants or builders: reopen the class right below (`MethodData = Data.define(...)`; `class MethodData; BODY_LEVEL = 3; def self.build ...`), otherwise `Lint/ConstantDefinitionInBlock` fires.
- Dictionaries in `lib/provider_integrator/dictionaries/*.yml`, loaded once via `Psych.safe_load_file(path, permitted_classes: [Symbol])` and deep-frozen (`Dictionaries.load`).

## 2. Objects and boundaries

- Models: `Data.define(...)` with `include Models::Base` (strict `from_h`, deep `to_h`, canonical JSON); always immutable.
- Every module boundary returns a result object: `Models::ParseResult` (`#spec`), `Models::GenerationResult` (`#files`, `#file(kind)`, `#validation`); both share `Models::ResultPredicates` (`success?` = no error-level events).
- Events only through `Events.build(code, location:, **details)` / `EventLog#add`; codes live in `events.rb` and `docs/PLAN.md §3.3` (a spec keeps them in sync).
- Service objects expose `self.call(**kwargs)` or `new(...).call`; no global state, no class-level mutable memoization except frozen dictionaries and pure caches (`RubyFormatter.cache`).
- Exceptions only for unrecoverable input (`SpecError`) or template bugs (`GenerationError`); rescue them in `Generator.call` / `Pipeline`, never in analyzers or pieces.

## 3. Deterministic generation

- Never call `Time.now`, `Date.today`, `rand`, `SecureRandom`, `object_id`, `Hash#inspect`, `Set#to_a` (unordered) in anything that reaches output.
- JSON artefacts: IR and `generation_report.json` through `JsonCanon.generate` (sorted keys, trailing LF). `fixtures.json` is the one exception: `JSON.pretty_generate` in insertion order, because the reference layout (`create_request`, `fetch_status`, `callback`, ...) carries meaning; the order is fixed by the spec, so it is still deterministic.
- Keep operation order from the spec, field order from `properties`; `ERROR_MAP` merges contract operations first, then extras, first mapping of a status wins.
- Generated Ruby is normalized by RuboCop **in memory** (`Generator::RubyFormatter`: `stdin:` option in, corrected text out; never a file write, so no CRLF on Windows). Config: `templates/rubocop_generated.yml`.
- Golden tests compare bytes (`spec/golden_spec.rb`); regenerate with `rake "golden:update[novapay]"` and commit the diff with an explanation.

## 4. Templates and template data (the generator)

- ERB lives in `lib/provider_integrator/templates/*.erb`, rendered by `Generator::Template.render(name, data)` with `trim_mode: "-"` and a binding that exposes only `data`. Leftover `<%`/`%>` raise `GenerationError`.
- Templates contain `<%= %>`, `<% each %>`, `<% if %>` and nothing else. Everything printed is a ready String: a method is `MethodData#source`, a constant `ConstantData#source`, a section of INTEGRATION.md a list of lines.
- `TemplateData::Service` builds the whole service in dependency order (methods first, then helpers, then constants) from pieces: `CreateMethod`, `StatusMethod`, `CallbackMethod` (+ `SignatureVerifier`), `ConditionsMethod`, `ExtraMethods`, `ServiceHelpers`, `ServiceConstants`. Pieces register what they need on the service (`require`, `need`, `add_env_constants`, `add_amount_helpers`, `payload_docs`).
- Ruby fragments only through `TemplateData::Code` (`str`, `literal`, `key`, `hash_lines`, `access`, `wrap`) and `Inflector`; platform names only through `TemplateData::Canon` (`success`, `failure_for_error`, `accessor`, `requisite_access`, ...). Literal `'X-API-Key'`, `'in_progress'` or `operation.amount` in a piece or a template is a bug (`spec/contract/anti_hardcode_spec.rb`).
- Request payloads: `PayloadBuilder` (per payout method, `Scope`) → `FieldSource` decides the platform expression per field and its wording for the docs. Confidence goes through `Generator::Confidence.todo_if_needed`; an `Evidence:` comment is always emitted, a `TODO(confidence x)` only below 0.75.
- Provider slug → `AcmepayService`, `ACMEPAY_BASE_URL`, `acmepay_service.rb` (`Generator::Context`). Every identifier from the spec passes through `Inflector.identifier`/`class_name`.
- Output is validated before it is returned (`Generator::OutputValidator`): Prism syntax, no ERB leftovers, `< BaseService`, the four contract methods (Prism visitor), RuboCop offences, `fixtures.json` parses and its examples satisfy `TemplateData::FieldSchema` (JSON Schema rebuilt from the IR), INTEGRATION.md required sections. Fatal findings become `E201`; schema mismatches of provider examples are recorded only.

## 5. CLI (Thor)

- `class CLI < Thor; def self.exit_on_failure? = true; end`.
- Output through a `Reporter` object (pastel for colour; respects `--no-color` and non-TTY). Default output mirrors the reference transcript in `docs/TZ.md`; details under `--verbose`.
- Exit codes: 0 ok, 1 internal, 2 args, 3 spec error, 4 ambiguity in `--strict`, 5 generation, 6 write. Map exceptions to codes in one place.
- Never print a backtrace unless `--verbose`.

## 6. Security of untrusted specs

- `Psych.safe_load(yaml, permitted_classes: [], aliases: false)`; reject files over `Loader::MAX_BYTES`
  (5 MB) and nesting deeper than `Loader::MAX_DEPTH` (100 levels). Aliases are refused, not expanded:
  a YAML alias is how a document makes itself exponentially larger than it looks, so it becomes E007
  with a message saying so rather than a parse that quietly succeeds.
- Every guard is an event with a code, never an exception that reaches the user: E001 unreadable or
  not YAML, E002 unsupported version, E007 over a limit, E005/E006/E008 for a `$ref` that is missing,
  cyclic or external. See `Parser::Loader` and `Parser::RefResolver`.
- Recursion over a spec needs a cycle guard keyed by resolved pointer, not only a depth cap: a
  self-referencing component multiplies work at every level (`SchemaExtractor#children`,
  `ExampleComposer#for_schema` both carry a `seen` set of component pointers).
- Treat `$ref` strings, `operationId`, property names, enum values, descriptions as data. They may end up in comments/strings/identifiers — always escape via `Inflector` (`ruby_string`, `identifier`) or `Markdown.cell`.
- Never `eval`, `instance_eval`, `send(user_string)`, `const_get(user_string)`, `system`/backticks with spec-derived content. Generated code is never loaded into the generator's process; specs exercise it in a child process with a fake client (`spec/fixtures/exercise_service.rb`), never over HTTP.

## 7. RSpec conventions

- `spec/<layer>/<class>_spec.rb` mirrors `lib/`. `describe ".call"` for service objects.
- Fixtures: full specs in `spec/fixtures/specs/*.yaml`, expected IR in `spec/fixtures/normalized_*.json`, golden outputs in `spec/golden/<spec>/`. `spec/support/*.rb` is auto-required — scripts meant for child processes go under `spec/fixtures/`.
- `spec/support/generation_helpers.rb` memoizes the NovaPay generation per process (`GenerationHelpers.novapay_generation`, `novapay_file(kind)`, `generate_fixture(name)`): generation is pure and RuboCop is the slow part.
- Use `aggregate_failures` for IR and output assertions; assert generated code by `include` of exact lines, not by regexes over the whole file.
- WebMock enabled globally (`WebMock.disable_net_connect!`).
- Every analyzer spec has at least: happy path on NovaPay, one alternative spec, one ambiguous case asserting the right `W…` event. Every generator piece has: NovaPay, one other fixture spec, one IR variation built with `Data#with` (stub, single method, status-only webhook).

## 8. RuboCop

- `.rubocop.yml`: `TargetRubyVersion: 3.3`, `Style/Documentation: Enabled` for `lib/`, `Metrics/MethodLength: 20`, `Metrics/ClassLength: 200`, `Layout/LineLength: 120`, `Style/FormatStringToken: template` (`%{name}`).
- Generated code: `templates/rubocop_generated.yml` — single quotes, table-aligned rockets, `Metrics` off, `Style/Documentation` off, `Lint/UnusedMethodArgument` off (contract signatures), `Lint/UselessConstantScoping` off (`STATUS_MAP` after `private`, as in the reference), comment lines exempt from `LineLength` (the generator wraps them at 100).
- On Windows `rubocop -A` rewrites files with CRLF: run `bundle exec rake lf` afterwards.

## 9. Review checklist (run before finishing any task)

1. `bundle exec rake check` green (`rspec` + `rubocop` + dictionary schemas).
2. `grep -ri novapay lib/` returns nothing (also a spec).
3. Two consecutive generations of `spec/fixtures/normalized_novapay.json` produce identical SHA-256 for every file (a spec), and `spec/golden/novapay` matches.
4. New warnings/errors have a code in `docs/PLAN.md §3.3` and a spec asserting them.
5. Nothing at runtime calls an LLM, an external API, or a non-Ruby executable.
