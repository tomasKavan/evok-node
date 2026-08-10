# `fixtures/handwritten/`

Small hand-built cases: a malformed frame, a config file exercising one validation error, a
definition that must be rejected.

Editable, unlike [`generated/`](../generated/README.md) and [`captured/`](../captured/README.md) —
and therefore the place where an agent can quietly weaken a test. So: **every fixture here carries a
comment saying why it exists**, ideally naming the finding or issue it came from. A fixture nobody
can justify is a fixture nobody can safely change.

Prefer generated or captured data whenever either can express the case. Hand-built data asserts what
we believe; the corpus asserts what the maps say.

See [docs/rules/testing.md](../../docs/rules/testing.md).
