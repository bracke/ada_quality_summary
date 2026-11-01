# Architecture

Ada Quality Summary is a separate, read-only command-line application. Ownership is split across three crates:

| Crate | Owns |
| ----- | ---- |
| `database` | Storage engine, transactions, process locks, and the read-only open mode (`Database.Open_Read_Only`). |
| `ada_quality` | Persisted schema, registry, assessment lifecycle, payload encodings, history compatibility and regression semantics, and the typed read-only reporting API `Ada_Quality.Reporting`. |
| `ada_quality_summary` | Selection, aggregation, filtering, sorting, terminal rendering, and report-specific JSON. |

The summary crate contains no table layout, payload decoder, schema knowledge, indicator definition, or history
algorithm. It consumes typed records from `Ada_Quality.Reporting` and passes opaque history rows to
`Ada_Quality.History` unchanged.

## Data flow

```text
main ─▶ CLI.Execute
          │ Options.Parse                      strict argument validation (exit 2)
          │ Repository.Load ──▶ Ada_Quality.Reporting.Open
          │                       shared lock, one read transaction, decode, release
          │ Reports.Build                      Filtering, Aggregation, Trends (pure, in memory)
          │ JSON.Render | Terminal.Render       complete text built in memory
          ▼
        CLI.Run writes the finished text in one write (exit 0, or 3 on output failure)
```

A snapshot is loaded once per invocation and never holds a database handle, cursor, or lock after `Load` returns.
Report data is computed completely before rendering, and rendering completes before the first byte is written, so a
computation error never leaves partial JSON on standard output.

## Packages

| Package | Responsibility |
| ------- | -------------- |
| `Ada_Quality_Summary` | Version constants and the three typed error categories. |
| `.Options` | Strict command-line parsing and validation. |
| `.Text` | User-visible message catalog rendered through `messages`. |
| `.Model` | Report records, classification, and indicator counting. |
| `.Repository` | Snapshot loading with bounded busy wait; project, run, and assessment indexes. |
| `.Filtering` | Exact project and indicator resolution, population filters, deterministic sorting, row limits. |
| `.Aggregation` | Project rows, portfolio totals, indicator matrix, finding collection. |
| `.Trends` | Thin adapter over `Ada_Quality.History`: baselines, regressions, histories, metric series, daily states. |
| `.Reports` | Assembly of the single typed report that both renderers consume. |
| `.Terminal` | Width-aware terminal rendering, display-cell measurement, color policy. |
| `.JSON` | Versioned JSON envelope and report-specific data objects. |
| `.CLI` | Orchestration, database-path precedence, help, exit codes. |

## Determinism

Every ordering is a strict total order ending in unique identities, so results never depend on container insertion
order. JSON members are emitted in a fixed order and the snapshot identity is a digest of the loaded rows, so repeated
exports of an unchanged database are byte-identical.

## Resource limits

| Limit | Default | Enforced by |
| ----- | ------- | ----------- |
| Projects loaded | 10,000 | `Ada_Quality.Reporting.Load_Limits` |
| Assessment runs loaded | 1,000,000 | `Ada_Quality.Reporting.Load_Limits` |
| Finding records loaded | 2,000,000 | `Ada_Quality.Reporting.Load_Limits` |
| Terminal width | 500 columns | `Options.Maximum_Width` |
| Displayed text field | 4,096 display cells | `Terminal.Maximum_Field_Width` |
| JSON document | 256 MiB | `JSON.Default_Maximum_Bytes` |
| Busy wait for a writer | 1 second | `Repository.Default_Busy_Deadline` |

Exceeding a load or JSON limit is a typed reporting failure (exit 3); machine-readable output is never truncated.
Terminal text fields longer than the field limit are shortened with an ellipsis.
