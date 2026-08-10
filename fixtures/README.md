# Fixtures

Three directories, three different rules about who may edit them.

| Directory | Origin | Editable |
|---|---|---|
| [`generated/`](generated/README.md) | derived from `docs/modbus-reg-map/` by a committed generator | **no** — change the generator |
| [`captured/`](captured/README.md) | recorded from real hardware or stock EVOK 3.0.6 | **no** — irreplaceable measurements |
| [`handwritten/`](handwritten/README.md) | small hand-built cases | yes, with a comment saying why the case exists |

**`generated/` and `captured/` are read-only.** `CLAUDE.md` rule 14: if a test fails against them,
the code is wrong. The failure mode this guards against is specific to how agents work — an agent
facing a failing assertion edits the expected value and produces a green build over a real bug.

Enforcement is three layers, because prose alone does not hold: CI regenerates `generated/` and
fails on any diff, both directories are in [`CODEOWNERS`](../CODEOWNERS), and both are
[`.prettierignore`](../.prettierignore)d so a format pass cannot rewrite them.

See [docs/rules/testing.md](../docs/rules/testing.md).
