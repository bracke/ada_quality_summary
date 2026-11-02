# Testing

```sh
alr test                        # build tests/ and run the AUnit suite
tests/bin/aqs_coverage          # instrumented suite and the 90% production line-coverage gate
tests/bin/aqs_release_stage     # stage and build the pin-free release manifest
tests/bin/check_all             # all release checks, incl. GNATdoc, proof, and staged release (repository root)
```

## Fixtures

`tests/src/aqs_fixtures.ads` builds every database through the supported Ada Quality APIs: `Storage.Add_Project`,
`Storage.Publish`, `Start_Assessment`, `Interrupt_Assessment`, `Set_Enabled`, and `Remove_Project`. Synthetic
assessments satisfy the 33-indicator publication invariants. Corruption (`Storage.Testing_Corrupt`) and schema changes
(`Storage.Testing_Set_Schema_Version`) are applied only to disposable copies. Legacy schema-2 evidence is published
with `Storage.Testing_Use_Legacy_Evidence`. Fixtures live under `tests/obj/fixtures` and are disposable. No fixture
databases are committed: `tests/fixtures/` holds only a note, because stored binary databases would drift from the
persistence schema they are meant to exercise.

`tests/bin/aqs_demo DIRECTORY` creates a demonstration database with passing, violating, incomplete, unassessed,
disabled, and removed projects, compatible and incompatible histories, and running and interrupted runs.

## Acceptance catalog

| Test | Case | Test | Case |
| ---- | ---- | ---- | ---- |
| AQS_T001 | Empty registry | AQS_T026 | Width 40 |
| AQS_T002 | Never-assessed project | AQS_T027 | Width 80 |
| AQS_T003 | 33 passes | AQS_T028 | Width 120 |
| AQS_T004 | One violation | AQS_T029 | Unicode paths and names |
| AQS_T005 | One unknown | AQS_T030 | `NO_COLOR` |
| AQS_T006 | Violation and unknown | AQS_T031 | Redirected standard output (separate process) |
| AQS_T007 | Not-applicable denominator | AQS_T032 | Every report validates against its schema |
| AQS_T008 | Interrupted latest run | AQS_T033 | Byte-identical repeated export |
| AQS_T009 | Running latest run | AQS_T034 | JSON and terminal parity |
| AQS_T010 | No completed assessment | AQS_T035 | Missing database not created |
| AQS_T011 | Duplicate result | AQS_T036 | Old schema not migrated |
| AQS_T012 | Missing result | AQS_T037 | Future schema rejected |
| AQS_T013 | Invalid measurement | AQS_T038 | Corrupt finding |
| AQS_T014 | Shared fingerprint across projects | AQS_T039 | Writer holding the lock (separate processes) |
| AQS_T015 | Multiple findings for one indicator | AQS_T040 | Writer publishing during reports (separate processes) |
| AQS_T016 | Equal names sort by ID | AQS_T041 | Output to `/dev/full` exits 3 |
| AQS_T017 | Disabled project | AQS_T042 | Load and JSON size limits |
| AQS_T018 | Removed project | AQS_T043 | Large registered-project collection |
| AQS_T019 | Ambiguous basename | AQS_T044 | All 33 indicators and their categories |
| AQS_T020 | Unknown indicator | AQS_T045 | No assessment tool spawned (PATH traps) |
| AQS_T021 | Incompatible baseline | AQS_T046 | Database unchanged after every report |
| AQS_T022 | Pass to violation | AQS_T047 | Missing timestamps |
| AQS_T023 | Pass to unknown | AQS_T048 | `--limit` keeps totals |
| AQS_T024 | Metric unavailable | AQS_T049 | Unknown option exits 2 |
| AQS_T025 | Exact basis points | AQS_T050 | No directory created for a missing database |

Additional cases cover option parsing, database-path precedence, aggregation properties (reordering projects or
results never changes totals, indicator states sum to the population, filtering cannot introduce a result), display
widths, the message catalog, JSON parse-and-serialize round trips, help topics, concurrent readers, a recovering
writer, readers killed mid-report, layouts, and every sort key.

Concurrency cases use separate operating-system processes: `tests/bin/aqs_writer` holds the writer lock, publishes
assessments, or recovers interrupted runs while `bin/ada-quality-summary` reports. A report is either complete and
internally consistent or a typed busy failure; it is never a mixture of generations.

## Proof

`tests/bin/check_all` runs `alr exec -- gnatprove -P spark_rules.gpr --checks-as-errors=on --warnings=error`, so an
unproved check in `Ada_Quality_Summary.Rules.Counting` fails the release. The proved properties are listed in
`docs/architecture.md`.

## Coverage

`tests/bin/aqs_coverage` builds `tests/coverage.gpr` with gcov instrumentation, runs the full suite with the
instrumented executables substituted for spawned processes (`AQS_BINARY`, `AQS_TOOLS`), measures every unit in
`src/`, and writes `coverage/gcov-summary.txt` in the `gcov-production-lines-v2` format, bound to the source and
toolchain fingerprints Ada Quality's TST-03 checks. It fails below 90 percent. Set `AQS_TIMING` to print per-test
durations.

Ada Quality's own reporting tests live in `../ada_quality/tests/src/ada_quality_reporting_tests.adb` and run with
`alr test` there.
