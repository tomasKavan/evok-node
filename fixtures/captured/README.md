# `fixtures/captured/` — read-only

Recorded from real hardware or from stock EVOK 3.0.6: golden request/response transcripts, stock
`hw_definitions` and `autogen.yaml`, stock `config.yaml` and `alias.yaml` for the migration tool.

**Never edit a file here, and never re-record one to make a test pass —
[Testing §3](/docs/dev/design/basics/03-Testing.md#3-fixtures).** Once stock EVOK is off the Patrons these cannot be captured
again; the loss is permanent. A file changes only when reality changed, and the PR must say what
changed about reality. [`CODEOWNERS`](../../CODEOWNERS) requires Tomas's approval.

Blocked capture items: [docs/dev/plan/STATUS.md](/docs/dev/plan/STATUS.md).

Empty until the capture trip.
