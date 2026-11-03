# Command line

```text
ada-quality-summary [OPTIONS] [COMMAND]
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
| `regressions` | Regressions against compatible baselines | — |
| `trends` | Daily last-known states and numeric metric series | — |
| `history PROJECT` | All runs of one project | required |
| `help [COMMAND]` | Usage | optional |

`PROJECT` resolves first as an exact positive project ID, then as an exact, case-sensitive directory basename. No
substring or fuzzy matching is performed. An ambiguous basename fails with the matching project IDs. Indicator IDs
are exact and case-sensitive.

## Options

| Option | Applies to | Meaning |
| ------ | ---------- | ------- |
| `--database PATH` | reports | Database path. |
| `--format terminal\|json` | reports | Output format; default `terminal`. |
| `--color auto\|always\|never` | terminal | Color selection; ignored for JSON. |
| `--no-color` | terminal | Alias for `--color never`. |
| `--layout compact\|normal\|detailed` | terminal | Layout; rejected with JSON. |
| `--width N` | terminal | Display width, 20–500; rejected with JSON. |
| `--include-removed` | reports | Include tombstoned projects. |
| `--enabled-only` | reports | Include only enabled projects. |
| `--project PROJECT` | collection commands | Restrict to one project. |
| `--status STATUS` | collection commands | `passing`, `violations`, `incomplete`, or `unassessed`. |
| `--sort KEY` | command-specific | See below. |
| `--reverse` | reports | Reverse the selected ordering. |
| `--limit N` | reports | Maximum rows; `0` or omitted means no limit. |
| `--since DATE` | `trends`, `history` | Earliest UTC date, inclusive, `YYYY-MM-DD`. |
| `--until DATE` | `trends`, `history` | Latest UTC date, inclusive. |
| `--pretty` | JSON | Indent JSON. |
| `--help` | all | Help for the selected command. |
| `--version` | alone | Print the version; any other argument is an argument error. |

Collection commands are `summary`, `projects`, `indicators`, `indicator`, `problems`, `regressions`, and `trends`.

Unknown options, duplicate scalar options (including `--color` with `--no-color`), missing values, unsupported sort
keys, invalid dates, `--since` later than `--until`, and options used outside their scope are argument errors.

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
| `regressions` | project, indicator, kind | `project`, `indicator`, `kind` |
| `trends` | run, project | `run`, `project` |
| `history` | run descending | `run` |

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
| 2 | Invalid command, option, filter, project, or indicator |
| 3 | Reporting, serialization, resource-limit, or output-stream failure |
| 4 | Database missing, locked beyond the busy deadline, unsupported schema, recovery pending, or corrupt evidence |

Diagnostics go to standard error; report data goes to standard output.
