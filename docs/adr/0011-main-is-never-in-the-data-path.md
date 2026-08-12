# ADR-0011 — `main` orchestrates and is never in the data path

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/12-modularisation.md · ADR-0008, ADR-0009 · finding 2.7

## Context

An orchestrator that spawns drivers and APIs is the obvious place to put anything global, and each
addition is individually defensible: a registry, the alias store, a routing table. The end state is a
component every request passes through — a bottleneck, a coupling point, and the layer ADR-0008 just
removed, rebuilt under a different name.

## Decision

**`main` parses config, validates, spawns, supervises and reloads. Nothing else, and no request ever
passes through it.**

Driver-qualified addressing (ADR-0009) removes most of what would otherwise have landed here: driver
ids are unique because they are YAML map keys; endpoint uniqueness inside a driver is local to that
driver's own address tables (RC-18); the nextgen API routes by parsing; compat's injectivity check
belongs to `api-compat`. There is no global address namespace to assemble, so **startup is
single-phase** — parse, validate, spawn drivers, spawn APIs. No collect-declarations-then-validate
round trip.

What genuinely requires `main` is **resource exclusivity**, because no other component sees enough
config to check it:

- two drivers on the same transport endpoint — the same `/dev/ttyNS0`, or the same TCP host and port.
  This is how ADR-0008's one-driver-per-endpoint rule and G-7 are actually enforced
- two APIs on the same listen port
- an API's `drivers:` list naming a driver absent from the `drivers:` map

All three are config-parse checks needing no handshake, so they fail before anything is spawned or any
port is bound. That is also finding **2.7**'s fix: its evidence is port conflicts causing systemd
restart storms, detected at bind time rather than at parse time. It therefore closes at N2 rather than
in the operability milestone.

`main` also **statically imports no concrete driver or API** — both are resolved from config through a
manifest (RC-10). Without that, `main` has an import edge to everything and the "not a conduit"
property is unenforceable.

The **user-data store is not `main`'s**. It is `driver-store`, a driver whose transport is a SQLite
file (ADR-0005, ADR-0008); otherwise every alias write would pass through `main`.

## Consequences

Makes easy: reasoning about failure — `main` going wrong cannot corrupt a reading, and a wedged driver
cannot wedge `main`. Reload semantics stay local to the affected components.

Makes hard: nothing may assume a global view at runtime. Cross-driver questions are explicit fan-in
with per-driver deadlines (RC-28). Manifest loading costs compile-time knowledge of what is spawned —
accepted, because it also delivers the plugin loading mechanism G-6 needs rather than requiring a
retrofit.

**Now owed:** reload is asymmetric to boot and must be written that way (RC-32). Validation failing at
boot is fatal; failing on reload keeps the current configuration running and reports the rejected one.
The natural implementation shares one code path and silently inherits the wrong behaviour.

**Rejected: `main` serving the address→driver lookup.** It is the smallest possible step into the data
path, and it is unnecessary once addresses are qualified.

**Rejected: two-phase startup** — spawn drivers, collect their declarations, validate globally, then
spawn APIs. Designed before ADR-0009, and made pointless by it.
