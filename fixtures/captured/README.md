# `fixtures/captured/` — read-only

Recorded from real hardware or from stock EVOK 3.0.6: golden request/response transcripts, stock
`hw_definitions` and `autogen.yaml`, stock `config.yaml` and `alias.yaml` for the migration tool.

**Never edit a file here, and never re-record one to make a test pass.** These are measurements, not
code. Once stock EVOK is off the Patrons they cannot be captured again — the loss is permanent.

A file here changes only when reality changed, and the PR must say what changed about reality. This
directory is in [`CODEOWNERS`](../../CODEOWNERS): every change needs Tomas's explicit approval.

See [docs/rules/testing.md](../../docs/rules/testing.md), `CLAUDE.md` rule 14, and the blocked
capture items in [docs/plan/STATUS.md](../../docs/plan/STATUS.md).

Empty until the capture trip.
