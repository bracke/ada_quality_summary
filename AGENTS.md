# Repository Guidelines

## Project Structure & Module Organization

Keep crate configuration at the root (`alire.toml`, `alire.lock`, and `ada_quality_summary.gpr`). Production units
belong in `src/`, with the executable in `src/main.adb` and child packages named `Ada_Quality_Summary.*`. Put AUnit
tests and database fixtures under `tests/src/` and `tests/fixtures/`. Maintain documentation in `docs/` and versioned
JSON Schemas in `schemas/`. Treat `bin/`, `obj/`, test databases, and generated reports as disposable artifacts.

Assessment semantics are owned by the sibling `ada_quality` crate. This application owns selection,
aggregation, filtering, and rendering; do not duplicate database schemas, indicator definitions, or history logic.
Agents may access and modify `../ada_quality` and `../database` for the shared reporting contract. Preserve unrelated
upstream changes; storage, decoding, schema, and history behavior remain in their owning crates.

## Build, Test, and Development Commands

- `alr exec -- gnatls --version` verifies GNAT 15.2.1.
- `alr build` builds the `ada-quality-summary` executable.
- `alr test` builds and runs the AUnit test action.
- `./bin/ada-quality-summary` runs the default portfolio overview.
- `alr build --validation -- -f` forces a warnings-as-errors validation build.

Invoke GNAT, GPRbuild, GNATdoc, and GNATprove through `alr exec --`; do not rely on a system compiler.

## Coding Style & Naming Conventions

Use Ada 2022, three-space indentation, and lines no longer than 120 characters. Package names use `Title_Case` and
source filenames use lowercase GNAT naming, for example `ada_quality_summary-model.adb`. Document public APIs with
GNATdoc comments. Prefer typed records and Ada containers over raw strings and unchecked conversions. Keep
calculations deterministic and independent of terminal or JSON formatting.

## Testing Guidelines

Use AUnit and add tests with each feature. Name acceptance cases with their specification identifier, such as
`AQS_T005_Incomplete_Assessment`. Fixtures must be created through supported Ada Quality publication APIs; corrupt
only disposable copies. Cover examples, ordering properties, JSON/terminal parity, process-level concurrency,
and proof that reporting leaves databases unchanged. Production line coverage must remain at least 90%.

## Commit & Pull Request Guidelines

The repository has no established commit history yet. Use imperative subjects like `Add portfolio
classification tests`, and keep commits phase-focused. Pull requests should reference AQS task/test IDs, explain
observable behavior and compatibility impact, list commands run, and include terminal or JSON examples when output
changes. Never weaken a gate or omit a failing test to make a change pass.

## Read-Only and Data-Integrity Rules

Reporting must never create, migrate, recover, or modify an assessment database. Use the shared typed reporting API,
preserve persisted provenance, and fail explicitly on unsupported schemas or malformed evidence.
