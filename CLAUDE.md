# evok-node — how to work here

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a
load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; we exist to fix
them. The interface is inherited; the design is not.

Success is defined, not asserted: every finding in `docs/plan/bug-dispositions.md` has a
disposition, and every rule below holds. See [`docs/GOALS.md`](docs/GOALS.md).

This file says how to work here. It holds no rules of its own — every rule lives in exactly one
place, listed below, and is cited by number.

## Before you write code

1. **[`docs/plan/STATUS.md`](docs/plan/STATUS.md)** — done, in progress, next. Always read first.
2. **[`docs/GOALS.md`](docs/GOALS.md)** — goals, non-goals, invariants, what 1.0 is. Read before
   arguing that anything is in or out of scope.
3. **`docs/rules/`** — binding, and the blocking set in review:
   [code](docs/rules/code.md) · [testing](docs/rules/testing.md) · [docs](docs/rules/docs.md) ·
   [git](docs/rules/git.md).
4. **[`docs/adr/`](docs/adr/README.md)** — settled decisions. Do not relitigate; propose a
   superseding ADR.
5. **[`docs/research/`](docs/research/README.md)** — how EVOK and the hardware actually behave.
   Read the relevant file before touching that area.

## Citing a rule

Always with its prefix, never as a bare number. Grep the prefix to find the rule — it is written at
the rule itself, not only in this table.

| Prefix | Source | Example |
|---|---|---|
| **G-N** | `docs/GOALS.md` invariants — scope and architecture | G-5 |
| **ADR-NNNN** | `docs/adr/` — a settled decision | ADR-0005 |
| **RC-N** | [code rules](docs/rules/code.md) | RC-17 |
| **RT-N** | [testing rules](docs/rules/testing.md) | RT-1 |
| **RD-N** | [docs rules](docs/rules/docs.md) | RD-2 |
| **RG-N** | [git rules](docs/rules/git.md) | RG-7 |
| **RP-N** | [plan rules](docs/plan/README.md) — how the plan is maintained | RP-1 |
| **R04-N** | `docs/research/04` design rules — evidence, not policy | R04-23 |

Numbers are stable: append, never renumber. A rule that becomes wrong is superseded in place, with
a note saying by what.

## Precedence

**G wins over everything.** Then A, then the rules files, then research. This file loses to all of
them; it only points.

If research and reality disagree, **reality wins** — and you fix the research file in the same PR,
with a dated correction note (RD-7).

A rule stated in two places is a bug. If you need a rule where one already exists, extend that rule
rather than writing a second one, and delete whatever it replaces (RD-6).

## Workflow

Issue → branch `<type>/<issue>-<slug>` → PR → green CI → Tomas approves → squash merge. Details in
[git rules](docs/rules/git.md).

Tomas does not write code and reviews every PR, so optimise for **reviewability**: small PRs, one
concern, and a body that says what changed and how it was verified (RG-5, RG-6). `STATUS.md` is
updated in the same PR as the work (RP-1).

## Layout

Two layers — **drivers act, APIs query** — with `main` orchestrating and on no request path
(ADR-0001). There is no third component kind: anything that would have been one is a
driver whose transport is not Modbus.

```
packages/
  messaging/    the internal contract: envelopes, introspection schemas, codecs, deadlines,
                fan-in. Root of the DAG. Holds no package's *public* wire schema (RC-12)
  hw-definitions/  platform facts: model descriptors, overlays, generated address tables
  modbus/       transport: framing, correlation, timing, circuit breakers
  main/         the daemon: config, validation, spawn, supervise, reload. Statically imports
                no concrete driver or api — they are manifest-loaded (RC-10)
  driver-kit/   shared driver runtime: scan loop, reading state, handshake, introspection
  driver-onboard/    the controller's own I/O sections, Modbus TCP to unipitcp
  driver-extension/  Unipi RTU extensions, one instance per RS-485 line
  api-nextgen/  our WS + HTTP surface. Owns its public schema. Serves ui/ at `/`
  api-compat/   the EVOK 3.x surface. Owns the projection table, derived from introspection
  simulator/    Modbus slave simulator, generated from the map corpus. Own framer (ADR-0011)
  client/       first-party TS client for the nextgen API
  ui/           the web SPA. Public API only; nothing imports it
  rig/          hardware-rig control service. Private, sysfs only, no workspace deps (RC-11)
docs/
  plan/         what we are doing next
  rules/        how we work — the binding rules
  adr/          why we decided
  research/     what is true about EVOK and Unipi hardware
  modbus-reg-map/  official Unipi register maps — ground truth, read-only
```

Later, one per milestone: `driver-onewire`, `driver-system` (filesystem and process-exec) and
`driver-store` (SQLite). All drivers.

The layering DAG is stated once, as a table in `.dependency-cruiser.cjs`, and every rule is
generated from it. A new edge needs an ADR.
