# Reporting Integration Verification

## Status

Phase 0 discovery is complete and its gate is satisfied. The upstream changes listed below were implemented in their
owning repositories and are tested there; [database-integration.md](database-integration.md) describes the resulting
contract.

- `../database`: the read-only open mode is committed upstream as "Open an existing database read-only for
  reporting"; all 237 database tests pass, including the read-only, shared-lock, and writer-exclusion cases.
- `../ada_quality`: `Ada_Quality.Reporting`, the shared private codec `Ada_Quality.Persistence`, schema version 3
  (run timestamps and lossless result and finding payloads), `Ada_Quality.Indicators.Measurement_Unit`, and nine
  reporting AUnit cases; the existing suite still passes.

Verified repositories:

- `../database`, crate version 0.14.0.
- `../ada_quality`, schema version 2 with eight logical tables.
- GNAT toolchain requirement: `gnat_native = "=15.2.1"`.

## Database Open, Locking, and Snapshot Semantics

`Database.Storage.File_IO.Open` opens the carrier with a nonblocking exclusive POSIX `flock`. `Database.Open` then
performs WAL replay before loading catalog state. `Database.Close` saves catalog, full-text, and extension state,
flushes the carrier, and deletes the WAL. Consequently, the existing open/close pair is not read-only.

Within one handle, `Database.Transactions.Begin_Read` holds a stable MVCC snapshot and a shared in-process lock until
commit, rollback, or finalization. This is sufficient for a coherent report only if every required scan occurs in one
transaction. Existing `Ada_Quality.Storage` query functions each create and close their own transaction, so composing
them does not guarantee one snapshot.

Required engine addition:

1. Open an existing carrier with `O_RDONLY` and a nonblocking shared process lock.
2. Never create a carrier or sidecar.
3. Reject any existing WAL as recovery-required; read-only open must not replay or delete it.
4. Load catalog and full-text state without persisting a rebuilt cache.
5. Reject write transactions on the handle.
6. Close without saving, flushing, checkpointing, or deleting artifacts.
7. Permit concurrent read-only processes; reject a writer while readers hold shared locks.

The prepared patch covers these requirements for unencrypted persistent databases. It adds `Open_Read_Only`, shared
nonblocking `flock`, `O_RDONLY` carrier access, a typed `Recovery_Required` status, write-transaction rejection, and a
non-persisting close path. Its tests also verify byte-identical carrier/full-text contents with unchanged sizes and
timestamps, WAL preservation, two-process reader coexistence, and writer exclusion. Encrypted read-only opening
remains outside this first patch and must be resolved before claiming the engine contract supports every persistent
backend.

Returning a typed busy/recovery failure is acceptable. Bypassing the process lock is not.

## Storage and Encoding Map

| Report field | Persisted source | Verification |
| --- | --- | --- |
| Project ID/path/enabled/removed | `projects` entity | Complete and deterministically sorted. |
| Run ID/project/lifecycle | `assessment_runs` entity | Complete; status is stored as text. |
| Source/policy/toolchain identity | assessment payload fields | Complete in schema 2. |
| Execution/compliance | result `state` as `execution/compliance` | Decodable with domain enums. |
| Indicator ID | result and measurement `kind` | Decodable through `Ada_Quality.Indicators.Parse`. |
| Summary/evidence | result payload separated by LF | Present, but encoding needs strict validation. |
| Measurement kind/value | measurement `state` and payload | Kind and exact value are present; units are not. |
| Finding fingerprint/severity | finding `kind` and `state` | Present. |
| Finding rule/message | finding payload separated by LF | Present. |
| Finding indicator/path/line | not stored as fields | Lossy; cannot be reconstructed reliably. |
| Assessment timestamps | no run or event timestamp | Absent; calendar filtering is unsupported. |

`Publish` writes one result and one measurement per indicator and validates 33 distinct results through
`Ada_Quality.Types.Is_Publishable`. The reporting decoder must still reject missing rows, duplicates, invalid enum
images, invalid typed measurements, ownership mismatches, and inconsistent applicability.

## History Contracts

`Ada_Quality.History.Compatible` requires completed runs from one project, nonempty source identities, and equal policy
and toolchain fingerprints. `Baseline_Id` selects the newest earlier compatible run. `Compare` owns the established
regression classifications, and `Metric_Trend` supplies run-ID-ordered numeric values. Reporting must adapt these APIs,
not reproduce their algorithms.

Two integration constraints require upstream attention:

- `Metric_Trend` uses the last history element as its reference. A newer running or interrupted run can therefore
  suppress an otherwise valid completed series.
- Measurement units are neither represented by `Measurement_Value` nor persisted, so the requested unit-preserving
  trend model is not currently implementable.

## Required Ada Quality Changes

1. Add a private reporting session backed by the database read-only handle and one long-lived read transaction.
2. Move or share entity schema and payload codecs inside `ada_quality`; the summary crate must not know table layouts.
3. Decode projects, run metadata, results, measurements, and findings into domain types inside that transaction.
4. Add actual UTC run timestamps through an explicit schema migration. Legacy timestamps remain absent.
5. Introduce lossless finding persistence for indicator, relative path, and line. Do not infer legacy line numbers.
6. Define and persist measurement units, or explicitly mark a measurement kind as unitless.
7. Expose the snapshot/commit identity used by a reporting session.
8. Add tests proving read-only open and every report leave all database artifacts byte-identical.

Normal `Storage.Open` migration and publication behavior must remain unchanged. Reporting open must require the exact
supported schema and must never invoke migration or recovery.

## Checked Public Interface Mapping

The proposed `Ada_Quality.Reporting` declarations map as follows:

- `Session`: new database read-only handle plus one active read transaction; cannot wrap `Storage.Store` unchanged.
- `Projects`: direct typed scan of `projects` in ascending ID order.
- `Runs`: direct typed scan of `assessment_runs` in ascending ID order, with optional persisted timestamps added.
- `Read_Assessment`: joined, validated decoding of result, measurement, and finding rows for one completed run.
- `Supported_Schema_Version`: exact metadata read within the session snapshot.
- `Busy_Error`: process-lock conflict.
- `Schema_Error`: missing tables, recovery-required data, or unsupported metadata version.
- `Integrity_Error`: corrupt, incomplete, duplicate, incompatible, or lossy evidence.
- `Reporting_Error`: other open, read, decode, or cleanup failures.

## Phase 0 Gate

Satisfied. Resolution of each required change:

1. Private read-only session with one read transaction: `Ada_Quality.Reporting.Session`.
2. Entity schema and payload codecs shared inside `ada_quality`: `Ada_Quality.Persistence`.
3. Typed decoding inside the transaction: `Ada_Quality.Reporting.Open` and `Read_Assessment`.
4. UTC run timestamps through an explicit schema migration: schema 3 `started_at` and `finished_at`; legacy runs stay
   absent.
5. Lossless finding indicator, path, and line: schema 3 `evidence_format=3` payloads. Legacy line numbers are never
   inferred; the legacy indicator is taken from the fingerprint prefix that `Ada_Quality.History` already relies on.
6. Measurement units: defined per indicator in the registry (`Measurement_Unit`); every numeric indicator records one
   fixed unit, and Boolean indicators are explicitly `none`.
7. Snapshot identity: `Snapshot_Identity`, a digest of every loaded row. Commit versions of the engine are not stable
   across processes and are not exposed.
8. Byte-identical artifacts after read-only open and every report: tested in both repositories.

The `Metric_Trend` reference constraint is handled in `Ada_Quality_Summary.Trends`, which passes only completed runs.
Encrypted databases remain unsupported by the read-only open mode.
