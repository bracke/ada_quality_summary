# Architecture

Ada Quality Summary is a separate, read-only command-line application. Ownership is split across three crates:

| Crate | Owns |
| ----- | ---- |
| `database` | Storage engine, transactions, process locks, and the read-only open mode (`Database.Open_Read_Only`). |
| `ada_quality` | Persisted schema, registry, assessment lifecycle, payload encodings, history compatibility and regression semantics, and the typed read-only reporting API `Ada_Quality.Reporting`. |
| `ada_quality_summary` | Selection, aggregation, filtering, sorting, terminal rendering, and report-specific JSON. |

The summary crate contains no table layout, payload decoder, schema knowledge, indicator definition, or history
algorithm. It consumes typed records from `Ada_Quality.Reporting` and passes opaque history rows to
`Ada_Quality.History` unchanged. Regressions come from `Ada_Quality.Reporting.Compare_Project` for the current
(latest completed) assessment, and skipped predecessors are explained by `Ada_Quality.History.Incompatibility_Of`.
`compare` resolves run IDs and aliases with `Ada_Quality.Reporting.Resolve_Assessment` and compares exactly the chosen
pair with `Ada_Quality.Reporting.Compare_Assessments`. The waiver report reads the `review-waiver` findings Ada Quality
persists for valid `AQ-WAIVER` comments; it does not scan sources.

## Data flow

```text
main ─▶ CLI.Execute
          │ Options.Parse                      strict argument validation (exit 2)
          │ Repository.Load ──▶ Ada_Quality.Reporting.Open
          │                       shared lock, one read transaction, decode, release
          │ Reports.Build                      Filtering, Aggregation, Trends (in memory)
          │ JSON.Render | SARIF.Render | Terminal.Render (terminal or Markdown mode)
          │                                    complete text built in memory
          ▼
        CLI.Run writes the finished text, then any diagnostic
        (exit 0, 1 when a --fail-on condition holds, or 3 on output failure)
```

A snapshot is loaded once per invocation and never holds a database handle, cursor, or lock after `Load` returns.
`Repository.Facts` derives each completed assessment's per-indicator states, totals, measurement kinds, and finding
counts on first use and memoizes them in the snapshot, so overviews, trends, histories, and daily snapshots decode
each assessment at most once.
Report data is computed completely before rendering, and rendering completes before the first byte is written, so a
computation error never leaves partial JSON on standard output.

## Packages

| Package | Responsibility |
| ------- | -------------- |
| `Ada_Quality_Summary` | Version constants and the three typed error categories. |
| `.Limits` | Every reporting resource limit except the busy deadline, which belongs to `.Repository`. |
| `.Criteria` | Sort keys and inclusive UTC-day bounds, shared by parsing, selection, history, and rendering. |
| `.Options` | Strict command-line parsing and validation; the option table that help is generated from. |
| `.Text` | User-visible message catalog rendered through `messages`. |
| `.Rules` | Counting types: classification, newer-run and result states, indicator and portfolio totals. |
| `.Rules.Counting` | SPARK-proved classification, tallying, and portfolio-total rules. |
| `.Model` | Report records derived from `.Rules`; the one compliance-to-state mapping; baseline and snapshot records. |
| `.Repository` | Snapshot loading with bounded busy wait; project, run, and assessment indexes; memoized run facts. |
| `.Filtering` | Exact project and indicator resolution, population filters, deterministic sorting, row limits. |
| `.Aggregation` | Project rows, portfolio totals, indicator matrix, finding collection. |
| `.Trends` | Adapter over `Ada_Quality.History`: baselines, regressions, histories, metric series, daily states. |
| `.Reports` | The single typed report that every renderer consumes, and `Build`, which runs the assembly steps. |
| `.Reports.Assembly` | Private: the steps over an explicit context: provenance, project selection, baseline comparisons, the fields of each report kind, and the `--fail-on` counts. |
| `.Terminal` | Width-aware terminal rendering of a report, and the same sections as Markdown. |
| `.Terminal.Environment` | Terminal detection, width, color policy, and locale, through `hostkit`. |
| `.Terminal.Cells` | Display-cell measurement, truncation, and padding. |
| `.Terminal.Output` | Private: the width-bounded output buffer, fields, notes, and tables, or their Markdown forms. |
| `.Terminal.Sections` | Private: labels, roles, project names, and the sections several report layouts share. |
| `.JSON` | Versioned JSON envelope and report-specific data objects; the shared size-checked serializer. |
| `.SARIF` | SARIF 2.1.0 log of the problems report. |
| `.Completion` | Shell completion scripts generated from the command and option tables. |
| `.CLI` | Orchestration, database-path precedence, help, the `--fail-on` gate, exit codes. |

## Proved rules

`Ada_Quality_Summary.Rules.Counting` holds the classification and counting rules every report depends on, written in
SPARK and proved by `alr exec -- gnatprove -P spark_rules.gpr --checks-as-errors=on`. The proof shows the absence of
run-time errors and these properties:

- a completed assessment is never classified as unassessed, and unknown compliance takes precedence over violation;
- each tally adds exactly one to the field of the counted state and to the counted population;
- portfolio totals always partition the projects into the four classifications and into enabled and disabled
  projects, and projects with newer runs or regressions never outnumber the projects counted.

`Model`, `Aggregation`, and `Trends` derive their count types from `Ada_Quality_Summary.Rules` and update every count
through these operations, so the proved properties hold for the totals that the reports render. Units that read the
database, build containers, or render output stay outside SPARK.

## Determinism

Every ordering is a strict total order ending in unique identities, so results never depend on container insertion
order. JSON members are emitted in a fixed order and the snapshot identity is a digest of the loaded rows, so repeated
exports of an unchanged database are byte-identical.

## Resource limits

Every resource limit is declared in `Ada_Quality_Summary.Limits`, and the units that enforce them refer to it. The
busy wait is a timing parameter of loading and is declared with it in `Repository`.

| Limit | Default | Declared as | Enforced by |
| ----- | ------- | ----------- | ----------- |
| Projects loaded | 10,000 | `Limits.Maximum_Projects` | `Ada_Quality.Reporting.Load_Limits` via `Limits.Default_Load` |
| Assessment runs loaded | 1,000,000 | `Limits.Maximum_Runs` | `Ada_Quality.Reporting.Load_Limits` via `Limits.Default_Load` |
| Finding records loaded | 2,000,000 | `Limits.Maximum_Findings` | `Ada_Quality.Reporting.Load_Limits` via `Limits.Default_Load` |
| Terminal width | 500 columns | `Limits.Maximum_Width` | `Options.Maximum_Width` |
| Displayed text field | 4,096 display cells | `Limits.Maximum_Field_Width` | `Terminal.Maximum_Field_Width` |
| Report in any format | 256 MiB | `Limits.Maximum_Output_Bytes` | `JSON.Default_Maximum_Bytes`, `Text.Bounded` |
| Result, measurement, execution, and event rows | 2,000,000 each | Ada Quality defaults | `Ada_Quality.Reporting.Load_Limits` |
| Rows in all tables | 2,500,000 | Ada Quality default | `Ada_Quality.Reporting.Load_Limits` |
| Persisted text | 256 MiB | Ada Quality default | `Ada_Quality.Reporting.Load_Limits` |
| Busy wait for a writer | 1 second | `Repository.Default_Busy_Deadline` | `Repository.Load` |

Each completed assessment stores 33 results, so the result-row limit admits about 60,000 completed assessments,
fewer than the run limit; whichever limit a database reaches first is reported.

Exceeding a load or output-size limit is a typed reporting failure (exit 3); no report is ever truncated.
The JSON limit is checked on the serialized document, because `jsonlib` serializes a complete document tree; the
output is then written in slices without a further copy.
Terminal text fields longer than the field limit are shortened with an ellipsis.
