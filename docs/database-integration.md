# Database integration

The Phase 0 discovery record is [reporting-integration.md](reporting-integration.md). This document describes the
implemented contract.

## Read-only open (`database`)

`Database.Open_Read_Only` opens an existing carrier with `O_RDONLY` and a nonblocking shared `flock`. It never creates
a carrier or sidecar, rejects an existing write-ahead log as `Recovery_Required` instead of replaying it, loads catalog
and full-text state without persisting them, rejects write transactions, and closes without saving, flushing,
checkpointing, or deleting anything. Readers coexist; a writer's exclusive lock and a reader's shared lock exclude
each other. Encrypted databases are not supported by the read-only mode.

## Reporting API (`Ada_Quality.Reporting`)

`Open` validates the path (nonempty, existing regular file), opens the database read-only, requires exactly the eight
logical tables and schema version 3, reads the projects, runs, results, measurements, and findings tables inside one
read transaction, commits it, and closes the database before returning. All later queries operate on the in-memory
snapshot.

| Failure | Exception | Summary exit |
| ------- | --------- | ------------ |
| Empty, missing, or non-regular path | `Reporting_Error` | 4 |
| Writer holds the lock | `Busy_Error` (after the 1-second bounded wait) | 4 |
| Missing tables, older or newer schema | `Schema_Error` | 4 |
| Pending write-ahead log, unknown states, orphaned rows, duplicate or missing results, invalid measurements, malformed findings | `Integrity_Error` | 4 |
| Load limit exceeded | `Limit_Error` | 3 |

`Read_Assessment` returns exactly 33 results in registry order with typed measurements and findings, after checking
uniqueness, completeness, enumeration spellings, canonical numbers, payload canonicality, and
`Ada_Quality.Types.Is_Valid`. `History_Items`, `Read_History_Evidence`, and `All_Measurements` return opaque rows in
the shapes `Ada_Quality.History` consumes, so the summary never parses payloads.

`Snapshot_Identity` is an FNV-1a digest of every loaded row; it changes whenever any loaded row changes and is stable
otherwise.

## Schema version 3 (`Ada_Quality.Storage`)

Version 3 is an explicit migration from versions 1 and 2. Existing rows stay byte-identical; only the metadata row
changes. New runs record:

- `started_at` when started and `finished_at` when published, interrupted, or recovered (UTC, `YYYY-MM-DDTHH:MM:SSZ`);
- `evidence_format=3`, which marks result and finding payloads as escaped key-value records holding applicability,
  summary, evidence, indicator, rule, message, path, and line.

Runs without the marker are legacy evidence and decode with the schema-2 rules. Reporting accepts only version 3; an
older database is reported as needing `ada-quality` to migrate it, and a newer one as unsupported. Reporting itself
never migrates.

Normal `Storage.Open`, publication atomicity, immutability of terminal assessments, and history fingerprints are
unchanged; the existing Ada Quality suite passes.

## Consistency under concurrency

A report reads one committed state under a shared lock, so it can never combine registry rows from one generation
with results from another. When a writer holds the database, the summary retries for up to one second and then fails
with a typed busy error; it never bypasses the lock. A terminated reader releases its lock with the process and
leaves every artifact unchanged.
