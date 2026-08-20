# Package rules

Binding, and scoped. A rule here applies **only inside the packages its file names** — outside them it
is not a rule at all, and citing it there is a category error.

This directory exists because [`code.md`](../code.md) was carrying rules that named this project's own
entities. Those rules were real, but they were not about writing TypeScript, so they were not general
and did not belong in a general file. Split out 2026-08-16.

## Citing

**`RPG-<SCOPE>-N`**, always with the scope. The scope segment identifies the file, not a single
package, because some rules govern a family.

| Prefix | File | Applies to |
|---|---|---|
| **RPG-DRV-N** | [`drivers.md`](drivers.md) | every driver package, and `driver-kit` |
| **RPG-DMB-N** | [`driver-modbus.md`](driver-modbus.md) | drivers whose transport is Modbus, and `modbus` |

Numbers are per file and stable within it: append, never renumber. A rule that becomes wrong is
superseded in place with a note saying by what.

## Adding a file

One file per scope, added when a second package needs the same rule or when a rule would otherwise be
written in prose in a package README. A rule that turns out to apply everywhere is promoted to
`code.md` and deleted here; a rule that applies to exactly one package and always will is better as a
lint rule or a type than as a document.
