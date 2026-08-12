# Fixtures

Three directories, three different rules about who may edit them.

| Directory | Origin | Editable |
|---|---|---|
| [`generated/`](generated/README.md) | derived from `docs/modbus-reg-map/` by a committed generator | **no** — change the generator |
| [`captured/`](captured/README.md) | recorded from real hardware or stock EVOK 3.0.6 | **no** — irreplaceable measurements |
| [`handwritten/`](handwritten/README.md) | small hand-built cases | yes, with a comment saying why the case exists |

**`generated/` and `captured/` are read-only — [RT-1](../docs/rules/testing.md).** If a test fails
against them, the code is wrong. Enforced by CI fixture-drift, [`CODEOWNERS`](../CODEOWNERS) and
[`.prettierignore`](../.prettierignore).
