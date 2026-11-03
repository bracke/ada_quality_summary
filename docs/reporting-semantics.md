# Reporting semantics

## Execution and compliance

Ada Quality records two independent states per indicator. Execution (`not-run`, `running`, `succeeded`, `blocked`,
`failed`, `errored`, `not-applicable`) says whether evidence was obtained; compliance (`unknown`, `pass`, `violation`,
`not-applicable`) says whether the requirement holds. Reports show both and never derive one from the other.

## Project classification

For each registered project:

1. The current assessment is the completed run with the highest ID. The latest run is the highest run ID in any
   lifecycle state.
2. Without a completed run the project is `unassessed`, even when running, interrupted, or invalid runs exist. Its
   indicator states are absent, not unknown; JSON reports `"indicators": null`.
3. Otherwise any `unknown` result makes it `incomplete`; else any `violation` makes it `violations`; else `passing`.

An `incomplete` project keeps its violation count visible. A newer running, interrupted, or invalid run never
replaces completed evidence; it is reported as `newer_run` and counted under assessment activity.

No weighted quality score exists. For a completed assessment `P + V + U + N = 33` and the applicable count is
`A = P + V + U`; the terminal shows `P/A applicable passing`.

## Indicator matrix

Each indicator receives one state per selected project: pass, violation, unknown, not applicable, or missing.
`missing` means the project has no completed assessment. The five counts always sum to the selected project count. A
completed assessment that lacks an indicator is a data-integrity failure and is never reported as missing.
`affected_projects` counts projects violating the indicator.

## Findings

Findings are persisted occurrences with indicator, rule, severity, message, relative path, line, fingerprint, and
assessment. Repeated fingerprints in different projects remain separate occurrences. Finding counts are never used
as violation counts. Assessments published before schema 3 have no persisted finding location; such findings report
`relative_path` and `line` as `null`, and their indicator comes from the stable fingerprint prefix that Ada Quality
itself uses for regression comparison.

The default overview aggregates findings by indicator: JSON `summary` reports `findings_by_indicator`, the finding
and project counts per indicator in registry order, with the same shape as `grouped_by_indicator` in `problems`. The
terminal overview keeps its total finding count; `problems` lists the groups.

## Regressions

`Ada_Quality.History.Baseline_Id` selects the newest earlier compatible completed run (same project, nonempty source
fingerprints, equal policy and toolchain fingerprints). `Ada_Quality.History.Compare` classifies changes as
`new_violation`, `worsened_metric`, `increased_severity`, `failed_gate`, `lost_evidence`, `introduced_finding`,
`reintroduced_finding`, or `policy_induced_change`. Like the Ada Quality regressions command, the summary passes the
findings of compatible runs older than the baseline, so a finding that returns from older evidence is
`reintroduced_finding` rather than `introduced_finding`. The summary adds the project identity and explains every newer completed run that was
skipped as incompatible (`policy_changed`, `toolchain_changed`, `missing_source_fingerprint`). Without a compatible
baseline the status is `no_baseline` and no regression is reported.

## Trends

Numeric series come from `Ada_Quality.History.Metric_Trend`, called per project with the completed runs only, so the
reference is the current assessment rather than a newer unfinished run. A series never mixes measurement kinds; the
unit comes from `Ada_Quality.Indicators.Measurement_Unit`, and decimal values stay exact basis points. Projects without
comparable numeric evidence are counted as excluded, and completed runs whose measurement was not comparable are
counted as excluded observations.

Daily snapshots classify the population at the end of each UTC day on which a dated completed assessment finished,
using the latest completed assessment finished by then. This is a last-known-state view, not a claim that every
project was reassessed on that day. A legacy assessment without a timestamp was completed before the schema migration
that started recording timestamps, and every snapshot day is the day of a dated run, so a legacy assessment counts as
finished before every snapshot day; it keeps its project assessed without being given a date.

## Timestamps and date filters

Schema 3 persists UTC `started_at` and `finished_at` for every run. Runs created under earlier schemas have no
timestamp; reports show `null` and never infer a date from a run ID. With `--since` or `--until`, undated runs and
observations are excluded and their number is reported as `undated_excluded`. In `trends` this counts undated
completed runs once each, not once per numeric series.

A numeric series always reports its indicator's measurement kind, `decimal` for basis points and `integer` otherwise,
also when no observation falls in the requested range.

## Selection

Tombstoned projects are excluded unless `--include-removed`; disabled projects are included unless `--enabled-only`.
Project IDs, never names or paths, are the join key.
