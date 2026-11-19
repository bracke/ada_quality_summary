# Command line

```text
ada-quality-summary [OPTIONS] [COMMAND [ARGUMENTS]]
```

Exactly one command is accepted; `summary` is the default. Options may appear before or after the command and accept
both `--name value` and `--name=value`. The program never prompts and never uses cursor control or alternate screens.

## Commands

| Command | Report | Positional argument |
| ------- | ------ | ------------------- |
| `summary` | Portfolio overview | — |
| `projects` | Project status table | — |
| `project PROJECT` | One project's current assessment, findings, and regressions | required |
| `indicators` | Indicator matrix across projects | — |
| `indicator ID` | One indicator across projects | required, e.g. `TST-03` |
| `problems` | Outstanding findings | — |
| `waivers` | Review waivers recorded in current assessments | — |
| `regressions` | Regressions against the baseline Ada Quality selects | — |
| `compare BASELINE CURRENT` | Regressions between two chosen assessments of one project | both required |
| `trends` | Daily last-known states and numeric metric series | — |
| `history PROJECT` | All runs of one project | required |
| `help [COMMAND]` | Usage | optional |
| `completion SHELL` | Shell completion script | required: `bash`, `zsh`, or `fish` |

`PROJECT` resolves first as an exact positive project ID, then as an exact, case-sensitive directory basename. No
substring or fuzzy matching is performed. An ambiguous basename fails with the matching project IDs. Indicator IDs
are exact and case-sensitive.

`BASELINE` and `CURRENT` are run IDs or assessment aliases, resolved by `Ada_Quality.Reporting.Resolve_Assessment`.
Both must belong to one project and `BASELINE` must be the older run. `compare` compares exactly that pair through
`Ada_Quality.Reporting.Compare_Assessments`, without substituting another baseline: an incompatible pair is reported
with its reason and no regressions, and a pair whose runs did not both complete reports why it cannot be compared.

`waivers` lists the valid structured `AQ-WAIVER` comments Ada Quality accepted in each selected project's current
assessment. Ada Quality records each one as a low-severity finding with rule `review-waiver` whose message is
`INDICATOR target=TARGET justification=TEXT`; the report shows the target and justification as separate columns. The
same findings remain in `problems`.

## Options

| Option | Applies to | Meaning |
| ------ | ---------- | ------- |
| `--database PATH` | reports | Database path. |
| `--format terminal\|json\|markdown\|sarif` | reports | Output format; default `terminal`. `sarif` is accepted by `problems` only. |
| `--color auto\|always\|never` | terminal | Color selection; ignored by the other formats. |
| `--no-color` | terminal | Alias for `--color never`. |
| `--layout compact\|normal\|detailed` | terminal, Markdown | Layout; rejected with JSON and SARIF. |
| `--width N` | terminal | Display width, 20–500; rejected with every other format. |
| `--include-removed` | reports | Include tombstoned projects. |
| `--enabled-only` | collection commands | Include only enabled projects. |
| `--project PROJECT` | collection commands | Restrict to one project. |
| `--status STATUS` | collection commands | `passing`, `violations`, `incomplete`, or `unassessed`. |
| `--sort KEY` | command-specific | See below. |
| `--reverse` | reports | Reverse the selected ordering. |
| `--limit N` | reports | Maximum rows; `0` or omitted means no limit. |
| `--since DATE` | `trends`, `history` | Earliest UTC date, inclusive, `YYYY-MM-DD`. |
| `--until DATE` | `trends`, `history` | Latest UTC date, inclusive. |
| `--pretty` | JSON, SARIF | Indent the document. |
| `--fail-on CONDITIONS` | reports | Exit 1 when a listed condition holds; see [Quality gate](#quality-gate). |
| `--help` | all | Help for the selected command. |
| `--version` | alone | Print the version; any other argument is an argument error. |

Collection commands are `summary`, `projects`, `indicators`, `indicator`, `problems`, `waivers`, `regressions`, and
`trends`.

`help`, `completion`, and `--version` accept no report option, and `--enabled-only` is a collection option.
`compare` accepts `--include-removed`, which is required when the compared runs belong to a removed project, as it is
for naming a removed project.

Unknown options, duplicate scalar options (including `--color` with `--no-color`), missing values, unsupported sort
keys, invalid dates, `--since` later than `--until`, and options used outside their scope are argument errors.
`help` checks its options against the command it describes, or against `help` itself without a topic, so
`help --sort name` is an error while `help projects --sort name` shows the projects help. Dates are inclusive UTC
days; `--since` and `--until` may name the same day, and every day up to 2399-12-31 is accepted.

Filters apply before sorting and limiting. Totals are computed before the row limit; the terminal states when rows
were limited.

### Sort keys

| Command | Default order | Keys |
| ------- | ------------- | ---- |
| `summary` | quality priority (incomplete, violations, unassessed, passing), violations descending, name, ID | `quality`, `name`, `id`, `violations` |
| `projects` | name, ID | `name`, `id`, `path`, `quality`, `violations`, `unknown`, `findings` |
| `project` | registry order | `indicator`, `state` |
| `indicators` | registry order | `id`, `name`, `violations`, `unknown`, `affected` |
| `indicator` | state (violation, unknown, missing, pass, N/A), name, ID | `state`, `name`, `id` |
| `problems` | severity descending, indicator, project, fingerprint | `severity`, `indicator`, `project` |
| `waivers` | indicator, project, path | `indicator`, `project` |
| `regressions` | project, indicator, kind | `project`, `indicator`, `kind` |
| `compare` | indicator, kind | `indicator`, `kind` |
| `trends` | run, project | `run`, `project` |
| `history` | run descending | `run` |

## Output formats

| Format | Content |
| ------ | ------- |
| `terminal` | Width-bounded tables and fields, colored when enabled. |
| `markdown` | The terminal report's sections as GitHub-flavored Markdown: a level-one title, level-two section headings, `- **Label:** value` fields, bullet notes, and pipe tables with right-aligned numbers. Nothing is truncated; `--layout compact` keeps only the essential columns, the other layouts show every column. Markdown punctuation in data is escaped. Suitable for pull-request comments and `$GITHUB_STEP_SUMMARY`. |
| `json` | The versioned report documents described in [JSON contracts](json-contracts.md). |
| `sarif` | A SARIF 2.1.0 log of the `problems` report, for code-scanning tools: one rule per indicator with findings, one result per finding with its level (`error` for critical and high, `warning` for medium, `note` for low and info), project-relative location, and the stored fingerprint as `partialFingerprints.adaQualityFinding/v1`. Each project's root is an `originalUriBaseIds` entry named `project-ID`, and a review waiver is a result suppressed in source with its justification. |

## Quality gate

`--fail-on` takes a comma-separated list of conditions. The report is generated and written as usual; when a listed
condition holds, the program then writes `quality gate failed: CONDITION (COUNT), ...` to standard error and exits
with status 1.

| Condition | Holds when |
| --------- | ---------- |
| `regressions` | A selected project's current assessment regressed against the baseline Ada Quality selects; for `compare`, the compared pair regressed. |
| `violations` | A selected project's current assessment violates an indicator; for `compare`, the current assessment does. |
| `incomplete` | A selected project's current assessment has unknown results; for `compare`, the current run has unknown results or did not complete. |
| `unassessed` | A selected project has no completed assessment; never for `compare`, whose runs are chosen. |

The conditions apply to the selected population, after `--project`, `--status`, `--enabled-only`, and
`--include-removed` and before `--limit`, whatever the report shows: `problems --fail-on regressions` compares every
selected project although the problems report lists no regressions. A CI step can therefore publish a Markdown or
SARIF report and fail in the same command:

```sh
ada-quality-summary regressions --format markdown --fail-on regressions >> "$GITHUB_STEP_SUMMARY"
```

## Shell completion and manual page

`completion bash`, `completion zsh`, and `completion fish` print completion scripts generated from the same command
and option tables as the parser, so they always offer the accepted commands, options, and fixed values, and after
`--sort` only the keys of the command being typed:

```sh
ada-quality-summary completion bash > ~/.local/share/bash-completion/completions/ada-quality-summary
ada-quality-summary completion zsh > "${fpath[1]}/_ada-quality-summary"
ada-quality-summary completion fish > ~/.config/fish/completions/ada-quality-summary.fish
```

The manual page [`docs/ada-quality-summary.1`](ada-quality-summary.1) is generated the same way by
`tests/bin/aqs_manpage`; the release checks fail while the committed page differs from the generated one. View it
with `man -l docs/ada-quality-summary.1`.

## Environment

| Variable | Effect |
| -------- | ------ |
| `ADA_QUALITY_DATABASE` | Database path when `--database` is absent. |
| `NO_COLOR` | Disables `--color auto` styling. |
| `COLUMNS` | Width fallback when standard output is not a terminal. |
| `LC_ALL`, `LC_CTYPE`, `LANG` | A UTF-8 locale enables the `…` ellipsis; otherwise `...` is used. |

`ADA_QUALITY_POLICY` is deliberately ignored: reports present each assessment under the policy it was evaluated with.

## Terminal widths

| Width | Behavior |
| ----- | -------- |
| under 40 | One record per project, field per line |
| 40–79 | Essential columns |
| 80–119 | Standard columns with indicator counts |
| 120 and wider | Expanded columns: identities, runs, paths, summaries |

Widths are measured in display cells, so wide East Asian characters, combining characters, and ANSI escapes align
correctly. Text is truncated only at grapheme boundaries; numbers and status labels are never truncated. Without a
terminal and without `COLUMNS`, the width is 80.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Report generated, including reports with quality violations |
| 1 | Report generated, and a condition requested with `--fail-on` holds |
| 2 | Invalid command, option, filter, project, indicator, or assessment reference |
| 3 | Reporting, serialization, resource-limit, or output-stream failure |
| 4 | Database missing, locked beyond the busy deadline, unsupported schema, recovery pending, or corrupt evidence |

Diagnostics go to standard error; report data goes to standard output. A failing quality gate's diagnostic is
written after the report.
