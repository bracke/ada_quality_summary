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
  "source": { "application": "ada_quality", "database_schema_version": 3, "snapshot": "fnv1a64:0123456789abcdef" },
  "selection": { "include_removed": false, "enabled_only": false, "project_id": null, "status": null,
                 "limit": null, "selected_projects": 2 },
  "data": {}
}
```

`schema_version` versions the report family independently of Ada Quality's assessment JSON. `snapshot` identifies the
database snapshot the report was computed from.

## Report data

| `report_type` | `data` members |
| ------------- | -------------- |
| `summary` | `totals`, `projects`, `common_violations`, `regression_summary`, `activity` |
| `projects` | `projects`, `totals` |
| `project` | `project`, `assessment`, `indicators`, `findings`, `regressions`, `baseline` |
| `indicators` | `indicators`, `project_count` |
| `indicator` | `indicator`, `projects`, `totals` |
| `problems` | `findings`, `grouped_by_indicator`, `totals` |
| `regressions` | `regressions`, `projects_affected`, `baseline_exclusions`, `totals` |
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
  `baseline_run_id`, `excluded_runs` with `run_id` and `reason`.
- **run**: `run_id`, `state`, fingerprints, `started_at`, `finished_at` (`null` when not persisted), `quality`
  (`null` unless completed).

Optional identities are `null`, never zero. Totals are computed before `--limit`.

## Validation

The test suite validates every report, in compact, pretty, limited, and tombstone-including variants, against its
schema. `tests/bin/aqs_schema_check SCHEMA_DIR SCHEMA_FILE DOCUMENT` validates a saved report.
