# JSON contracts

Every report is one UTF-8 JSON document with a trailing line feed. Keys are lowercase snake_case, member order is
fixed, and output is byte-identical for an unchanged database. Terminal options never affect JSON, and the database
filename is never embedded.

The schemas in [`schemas/`](../schemas) are JSON Schema 2020-12 documents: `common.schema.json` holds shared
definitions, and one schema per report type fixes required fields, integer ranges, enumerations, identifier patterns,
nullability, and forbids undocumented members.

## Envelope

```json
{
  "schema_version": 1,
  "report_type": "summary",
  "source": { "application": "ada_quality", "database_schema_version": 4, "snapshot": "fnv1a64:0123456789abcdef" },
  "selection": { "include_removed": false, "enabled_only": false, "project_id": null, "status": null,
                 "limit": null, "selected_projects": 2 },
  "data": {}
}
```

`schema_version` versions the report family independently of Ada Quality's assessment JSON. `snapshot` identifies the
database snapshot the report was computed from.

`database_schema_version` is the persisted Ada Quality schema, currently 4 (assessment aliases). The specification's
envelope examples show 2, the schema before the timestamp migration that the specification itself requires (section
5.6).

## Report data

| `report_type` | `data` members |
| ------------- | -------------- |
| `summary` | `totals`, `projects`, `common_violations`, `findings_by_indicator`, `regression_summary`, `activity` |
| `projects` | `projects`, `totals` |
| `project` | `project`, `assessment`, `indicators`, `findings`, `regressions`, `baseline` |
| `indicators` | `indicators`, `project_count` |
| `indicator` | `indicator`, `projects`, `totals` |
| `problems` | `findings`, `grouped_by_indicator`, `totals` |
| `waivers` | `waivers`, `by_indicator`, `totals` |
| `regressions` | `regressions`, `projects_affected`, `baseline_exclusions`, `totals` |
| `compare` | `project`, `baseline`, `current`, `comparison`, `policy_changed`, `incompatibility`, `regressions`, `totals` |
| `trends` | `series`, `excluded_observations`, `comparison_metadata`, `snapshots` |
| `history` | `project`, `runs`, `completed_count`, `interrupted_count`, `invalid_count`, `running_count`, `undated_excluded` |

## Shared objects

- **project**: `project_id`, `name`, `path`, `enabled`, `removed`, `quality`, `current_run_id`, `latest_run_id`,
  `newer_run`, `indicators` (`null` when unassessed), `finding_count`, `regression_count`.
- **indicator result**: `id`, `name`, `category`, `version`, `execution`, `compliance`, `applicable`, `summary`,
  `evidence`, `measurement`, `findings`. Execution and compliance use Ada Quality's stable spellings.
- **measurement**: exactly one tagged form — `unavailable` with `reason`, `boolean` with `value`, `integer` with
  `value` and `unit`, `decimal` with exact integer `basis_points`, `text` or `enum` with `value`. Basis points are
  never converted to floating point.
- **finding**: `project_id`, `run_id`, `indicator_id`, `rule`, `severity`, `message`, `relative_path`, `line`,
  `fingerprint`; path and line are `null` when unavailable.
- **regression**: `project_id`, `current_run_id`, `baseline_run_id`, `indicator_id`, `kind`, `before`, `after`.
- **baseline**: `project_id`, `status` (`no_current_assessment`, `no_baseline`, `compared`), `current_run_id`,
  `baseline_run_id`, `comparison` (the `Ada_Quality.History.Select_Comparison` decision: `comparison_available`,
  `no_assessments`, `no_baseline`, `current_incomplete`, `no_completed_baseline`, `toolchain_changed`,
  `no_compatible_baseline`), `policy_changed`, and `excluded_runs` with `run_id` and `reason`.
- **waiver**: `project_id`, `run_id`, `indicator_id`, `target`, `justification`, `relative_path`, `line`,
  `fingerprint`; `target` is empty and `justification` is the whole message when a waiver message has no fields.
- **compare**: `baseline` and `current` are runs; `comparison` is the `Ada_Quality.Reporting.Compare_Assessments`
  decision, `incompatibility` (`missing_source_fingerprint`, `policy_changed`, `toolchain_changed`, or `null`) says
  why two completed runs are not comparable, and `regressions` is empty unless `comparison` is
  `comparison_available`.
- **run**: `run_id`, `state`, fingerprints, `started_at`, `finished_at` (`null` when not persisted), `quality`
  (`null` unless completed).

Optional identities are `null`, never zero. Totals are computed before `--limit`.

## Validation

The test suite validates every report, in compact, pretty, limited, and tombstone-including variants, against its
schema. `tests/bin/aqs_schema_check SCHEMA_DIR SCHEMA_FILE DOCUMENT` validates a saved report.

SARIF output (`problems --format sarif`) follows the SARIF 2.1.0 specification instead of these schemas; its mapping
is described in [the command-line documentation](cli.md#output-formats).
