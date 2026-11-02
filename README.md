# ada_quality_summary

`ada-quality-summary` reports the persisted quality status of every project registered with
[Ada Quality](https://github.com/bracke/ada_quality): a portfolio overview, project and indicator reports,
outstanding findings, regressions, and historical trends, as terminal tables or versioned JSON.

It is strictly read-only. It reads one coherent snapshot through `Ada_Quality.Reporting`, never runs a measurement,
and never creates, migrates, recovers, or modifies an assessment database.

## Build

```sh
alr exec -- gnatls --version      # GNAT 15.2.1
alr build                         # bin/ada-quality-summary
alr test                          # AUnit acceptance suite
alr build --validation -- -f      # warnings-as-errors validation build
alr exec -- gnatprove -P spark_rules.gpr --checks-as-errors=on   # SPARK proof of the counting rules
```

The `[[pins]]` in `alire.toml` link every dependency to a sibling checkout (`../ada_quality`, `../database`, ...), so
development and CI build exactly the checked-out sources. Alire 2 writes the resulting lockfile to `alire/alire.lock`
inside the ignored `alire/` directory. It records only those links, not versions, so it is not committed.

The pins are for development only and are not part of a release. `tests/bin/aqs_release_stage` stages the release under
`obj/release-stage` with every `[[pins]]` table removed, validates the staged manifest and sources with
`project_tools`, and builds the stage through a temporary overlay that pins the same siblings by absolute path.
`obj/release-stage/alire.toml` is the manifest to publish; `tests/bin/check_all` runs this check.

## Usage

```text
ada-quality-summary [OPTIONS] [COMMAND]

  summary                 Overall quality overview (default)
  projects                Project status table
  project PROJECT         Detailed project assessment
  indicators              Cross-project indicator summary
  indicator ID            Detailed indicator report
  problems                Outstanding quality findings
  regressions             Quality regressions
  trends                  Historical quality trends
  history PROJECT         Individual project history
  help [COMMAND]          Help and usage
```

`PROJECT` is an exact project ID or an exact, case-sensitive directory basename. The database is the `--database`
path, otherwise `ADA_QUALITY_DATABASE`, otherwise `.ada-quality.db` in the working directory. See
[docs/cli.md](docs/cli.md) for every option.

Running without arguments prints the overview:

```text
ADA QUALITY SUMMARY
Database: .ada-quality.db
Projects: 6 registered, 5 enabled

QUALITY STATUS
  Passing          1
  Violations       3
  Incomplete       1
  Unassessed       1

PROJECTS
  Project     Quality     Pass  Fail  Unknown  N/A  Findings
  ----------------------------------------------------------
  editor      INCOMPLETE    27     3        2    1         3
  backup      VIOLATIONS    30     2        0    1         4
  version     VIOLATIONS    30     2        0    1         2
  messages    VIOLATIONS    31     1        0    1         1
  legacy      UNASSESSED     -     -        -    -         0
  httpclient  PASSING       32     0        0    1         0

COMMON VIOLATIONS
  Indicator  Projects  Name
  ---------------------------------------------
  DOC-01            3  Public API documentation
  TST-03            1  Line coverage >=90%
  SRC-01            1  Formatting
  SRC-04            1  Source hygiene
  SEC-01            1  Embedded secrets
  REL-01            1  Release checker

REGRESSIONS
  Projects with regressions: 1
  Regressions: 4

ASSESSMENT ACTIVITY
  Newer running assessments: 1
  Newer interrupted or invalid assessments: 1
```

Every report is also available as JSON (`--format json`, optionally `--pretty`), validated by the schemas in
[`schemas/`](schemas):

```json
{
  "schema_version": 1,
  "report_type": "projects",
  "source": { "application": "ada_quality", "database_schema_version": 3, "snapshot": "fnv1a64:c3dee5528d63e5dd" },
  "selection": { "include_removed": false, "enabled_only": false, "project_id": null, "status": null,
                 "limit": 1, "selected_projects": 6 },
  "data": { "projects": [ { "project_id": 2, "name": "backup", "quality": "violations", "...": "..." } ],
            "totals": { "projects": 6, "passing": 1, "violations": 3, "...": "..." } }
}
```

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Report generated, including reports that contain quality violations |
| 2 | Invalid command, option, filter, project, or indicator |
| 3 | Reporting, serialization, unsupported-data, resource-limit, or output failure |
| 4 | Database, schema, locking, or data-integrity failure |

Code 1 is reserved for a future quality-gate command.

## Documentation

- [Architecture](docs/architecture.md)
- [Command line](docs/cli.md)
- [Reporting semantics](docs/reporting-semantics.md)
- [Database integration](docs/database-integration.md) and the Phase 0 record in
  [reporting-integration.md](docs/reporting-integration.md)
- [JSON contracts](docs/json-contracts.md)
- [Public Ada API](docs/api.md)
- [Testing](docs/testing.md)

## License

MIT; see [LICENSE](LICENSE).
