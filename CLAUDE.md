# evok-node — how to work here

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a
load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; we exist to fix
them. The interface is inherited; the design is not.

This file says how to work here. It holds no rules of its own — every rule lives in exactly one
place, listed below, and is cited by number.

## Where we are (2026-08-16)

**Between research and development, and there is no plan right now.** Everything done so far except
the repo scaffolding is research. The ADRs moved to
[`docs/research/to_revision/`](docs/research/to_revision/README.md) and are **suspended** — expect
them to be rewritten, merged and dropped, and do not cite one as binding until the set is re-locked.
The roadmap, the bug dispositions and the definition of 1.0 went the same way.

The order from here: **development documentation → new plan → code.** Do not start implementation
work against the old plan; it is gone on purpose.

## Before you write code

1. **[`docs/plan/STATUS.md`](docs/plan/STATUS.md)** — done, in progress, next. Always read first.
2. **[`docs/GOALS.md`](docs/GOALS.md)** — goals, non-goals, invariants. Read before arguing that
   anything is in or out of scope. *What 1.0 is* currently reads TBD.
3. **`docs/rules/`** — binding, and the blocking set in review:
   [code](docs/rules/code.md) · [packages](docs/rules/packages/README.md) ·
   [testing](docs/rules/testing.md) · [docs](docs/rules/docs.md) · [git](docs/rules/git.md).
4. **[`docs/research/`](docs/research/README.md)** — how EVOK and the hardware actually behave, plus
   everything reclassified as research. Read the relevant file before touching that area.

## Citing a rule

Always with its prefix, never as a bare number. Grep the prefix to find the rule — it is written at
the rule itself, not only in this table.

| Prefix | Source | Example |
|---|---|---|
| **G-N** | `docs/GOALS.md` invariants — scope and architecture | G-5 |
| **ADR-NNNN** | **Suspended.** `docs/research/to_revision/` — a decision under revision, not in force. Cite only to discuss it | ADR-0005 |
| **RCD-N** | [code rules](docs/rules/code.md) — how we write TypeScript, nothing project-specific | RCD-2 |
| **RPG-\<SCOPE\>-N** | [package rules](docs/rules/packages/README.md) — binding only inside the packages the file names | RPG-DRV-1 |
| **RT-N** | [testing rules](docs/rules/testing.md) | RT-1 |
| **RD-N** | [docs rules](docs/rules/docs.md) | RD-2 |
| **RG-N** | [git rules](docs/rules/git.md) | RG-7 |
| **RPL-N** | [plan rules](docs/plan/README.md) — how the plan is maintained | RPL-1 |
| **R04-N** | `docs/research/04` design rules — evidence, not policy | R04-23 |

Numbers are stable: append, never renumber. A rule that becomes wrong is superseded in place, with
a note saying by what.

**Renamed 2026-08-16:** `RC-N` → `RCD-N`, and `RP-N` → `RPL-N`. `RC` numbers were also
**regenerated**, not just re-prefixed, so an old `RC-17` is not today's `RCD-17` — it is
`RPG-DRV-1`. Treat any surviving `RC-N` citation as stale and resolve it by reading the rule.

## Precedence

**G wins over everything.** Then the rules files, then research. This file loses to all of them; it
only points. ADRs sit outside this order while they are suspended.

If research and reality disagree, **reality wins** — and you fix the research file in the same PR,
with a dated correction note (RD-7).

A rule stated in two places is a bug. If you need a rule where one already exists, extend that rule
rather than writing a second one, and delete whatever it replaces (RD-6).

## Workflow

Issue → branch `<type>/<issue>-<slug>` → PR → green CI → Tomas approves → squash merge. Details in
[git rules](docs/rules/git.md).

Tomas does not write code and reviews every PR, so optimise for **reviewability**: small PRs, one
concern, and a body that says what changed and how it was verified (RG-5, RG-6). `STATUS.md` is
updated in the same PR as the work (RPL-1).

## Layout

The scaffolding as it stands. **The shape below is research output pending the development-docu pass**
— it came from the ADRs now under revision, so treat it as the current directory listing rather than a
committed architecture.

Two layers — **drivers act, APIs query** — with `main` orchestrating and on no request path. There is
no third component kind: anything that would have been one is a driver whose transport is not Modbus.

```
packages/
  messaging/    the internal contract: envelopes, introspection schemas, codecs, deadlines,
                fan-in. Root of the DAG. Holds no package's *public* wire schema
  hw-definitions/  platform facts: our hardware definitions, model descriptors, generated address
                tables. Ships the definition corpus; reads nothing from /etc/evok
  modbus/       transport: framing, correlation, timing, circuit breakers
  main/         the daemon: config, validation, spawn, supervise, reload. Statically imports
                no concrete driver or api — they are manifest-loaded
  driver-kit/   shared driver runtime: scan loop, reading state, handshake, introspection
  driver-onboard/    the controller's own I/O sections, Modbus TCP to unipitcp
  driver-extension/  Unipi RTU extensions, one instance per RS-485 line
  api-nextgen/  our WS + HTTP surface. Owns its public schema. Serves ui/ at `/`
  api-compat/   the EVOK 3.x surface. Owns the projection table, derived from introspection
  simulator/    Modbus slave simulator, generated from the map corpus. Own framer
  client/       first-party TS client for the nextgen API
  ui/           the web SPA. Public API only; nothing imports it
  rig/          hardware-rig control service. Private, sysfs only, no workspace deps
docs/
  plan/         what we are doing next — being rebuilt
  rules/        how we work — the binding rules, plus per-package rules in rules/packages/
  research/     what is true about EVOK and Unipi hardware, and everything not yet decided:
                to_revision/ holds the suspended ADRs
  modbus-reg-map/  official Unipi register maps — ground truth, read-only, no prose
```

Later: `driver-onewire`, `driver-system` (filesystem and process-exec) and `driver-store` (SQLite).
All drivers.

The layering DAG is stated once, as a table in `.dependency-cruiser.cjs`, and every rule is
generated from it. A new edge is a design change, not a config tweak — say so in the PR body.
