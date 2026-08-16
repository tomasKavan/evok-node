# evok-node — how to work here

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a
load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; we exist to fix
them. The interface is inherited; the design is not.

This file says how to work here, and **carries no status of its own** — where we are lives in
[`docs/plan/STATUS.md`](docs/plan/STATUS.md), where we are going in
[`docs/plan/roadmap.md`](docs/plan/roadmap.md). It holds no rules either: every rule lives in exactly
one place, listed below, and is cited by number.

## Working with docs, citing, before you write code

These 3 sections are **crucial before any decision or update is done to code or docu files**. Read them in[`docs/README.md`](docs/README.md).

## Workflow

Issue → branch `<type>/<issue>-<slug>` → PR → green CI → Tomas approves → squash merge. Details in
[git rules](docs/rules/git.md).

Tomas does not write code and reviews every PR, so optimise for **reviewability**: small PRs, one
concern, and a body that says what changed and how it was verified (RG-5, RG-6). `STATUS.md` is
updated in the same PR as the work (RPL-1).

## Layout

The directory listing as it stands. The package shape is **not yet a committed architecture** — it
came from the suspended ADRs, and `docs/dev/` is what commits it.

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
docs/           see docs/README.md, Layout section.
```

Later: `driver-onewire`, `driver-system` (filesystem and process-exec) and `driver-store` (SQLite).
All drivers.

The layering DAG is stated once, as a table in `.dependency-cruiser.cjs`, and every rule is
generated from it. A new edge is a design change, not a config tweak — say so in the PR body.
