# evok-node — how to work here as an agent

Start with [`README.md`](./README.md) and get familiar with the structure by following links in there. No need to go deeper yet.

Based of your role follow one of the sections below. If you are not sure about your role, ask user. If he requires you to work in role not defined here, request user to define the role here.

* **managing the project** - STOP and whine - path to be defined
* **researching** - STOP and whine - path to be defined
* **designing an architecture** - STOP and whine - path to be defined
* **coding** - STOP and whine - path to be defined
* **deploying** - STOP and whine - path to be defined
* **testing** - STOP and whine - path to be defined
* **updating documentation** - STOP and whine - path to be defined

## Rules for agents

* Don't create new documentaion out of structure defined in [`/docs/dev/README.md`](/docs/dev/README.md) and [`/docs/user/README.md`](/docs/user/README.md). If you don't know where to put it, ask user.
* **Brevity is the rule, not a preference.** Long documentation goes stale, and stale documentation is worse than none because it is believed. If you can delete a sentence and lose nothing, delete it.
* Write Markdown as documents, not fixed-width text.



This file says how to work here, and **carries no status of its own** — where we are lives in
[`docs/plan/STATUS.md`](docs/plan/STATUS.md), where we are going in
[`docs/plan/roadmap.md`](docs/plan/roadmap.md). It holds no rules either: every rule lives in exactly
one place, listed below, and is cited by number.

## Layout, citing, precedence

These three sections of [`docs/README.md`](docs/README.md) are **crucial before any decision or update
is made to code or to docs**: what exists and in what order to read it, how to cite a rule, and which
document wins when two disagree.

The part that changes how you write code: **`docs/dev/` is the design and it outranks the code.** Code
that contradicts a dev doc is a defect in the code. Changing the design is a human decision — see RD-8.

## Workflow

Issue → branch `<type>/<issue>-<slug>` → PR → green CI → Tomas approves → squash merge. Details in
[git rules](docs/rules/git.md).

Tomas does not write code and reviews every PR, so optimise for **reviewability**: small PRs, one
concern, and a body that says what changed and how it was verified (RG-5, RG-6). `STATUS.md` is
updated in the same PR as the work (RPL-1).

## Layout

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
