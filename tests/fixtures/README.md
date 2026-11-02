# Test fixtures

No fixture databases are committed. Every database the suite reads is created at run time by
`tests/src/aqs_fixtures.ads` through the supported Ada Quality publication APIs, so fixtures always match the current
persistence schema and cannot drift from it. Generated databases are written to `tests/obj/fixtures` and are
disposable; corruption is applied only to copies there. See `docs/testing.md`.
