# ADR-0008 — Drivers, APIs and main: two layers, N to M

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/12-modularisation.md · docs/GOALS.md G-1, G-2, G-3, G-6 · ADR-0001

## Context

The original design had one `core` package and one `server` package, with 1.0 defined as the compat
surface built first. Two problems followed. The compat surface was scheduled to exist before the
model it projects, which is how a projection quietly becomes the model — the exact failure G-3 and
RC-24 are written to prevent. And `core` bundled four responsibilities (registry, device model,
scheduler, aliases) whose lifecycles have nothing in common, so every later driver or surface would
have had to be threaded through it.

## Decision

**Three kinds of component over one messaging bus, but two layers: drivers act, APIs query.**

- **`main`** parses config, validates resource exclusivity, spawns and supervises drivers and APIs,
  handles reload. It sits on **no request path** (ADR-0011) and statically imports no concrete driver
  or API — both are resolved from config through a manifest.
- **A driver** owns exactly one transport endpoint, polls it, and holds the **only** copy of that
  endpoint's state. A transport endpoint need not be a bus: the filesystem, a process-exec surface
  and a SQLite file all qualify, so system configuration and the user-data store are drivers too.
  There is no third component kind.
- **An API** is a stateless translator between the bus and one public protocol. It holds no state and
  caches no readings.

Consequent rules, all in [`rules/code.md`](../rules/code.md): RC-10 (the partition), RC-26 (deadline
in the envelope), RC-27 (a driver's query path never blocks on I/O), RC-28 (fan-in with per-driver
deadlines and partial results), RC-29 (`effect` mandatory), RC-30 (no driver type in a public
schema), RC-31 (skip loudly), RC-32 (boot-fatal, reload-non-fatal).

**One package per API surface.** `api-compat` cannot leak our groups, labels or ordering into an EVOK
payload if it does not import anything that has them: G-3 becomes a missing edge in the dependency
graph rather than a review rule. For the same reason `protocol` splits — one package holding both the
internal contract and a public surface is the channel through which internal metadata reaches a
compat shape.

**What a surface exposes is that surface's own business.** `drivers:` in config is an administrator
restriction, not a capability negotiation. An API skips a driver type it does not understand. No
driver declares EVOK vocabulary, and no driver declares whether an endpoint is projectable.

**The build order changes; the definition of 1.0 does not.** The compat surface moves from M4 to N9,
last rather than first.

## Consequences

Makes easy: adding a surface or a driver without touching the others; a plugin driver with no API
release (RC-30); testing an API against recorded introspection with no driver running; splitting
into processes later, since the boundary is already messages.

Makes hard: anything wanting shared mutable state across components — there is none by construction.
Cross-driver aggregation becomes explicit fan-in with per-driver deadlines rather than one lookup.
Thirteen packages instead of nine, so the layering DAG is larger, though it is generated from one
table.

Costs accepted deliberately: for a long stretch there is no surface anyone can adopt, and the only
feedback loop is the nextgen API and `ui`. Mitigated by keeping `bug-dispositions.md` as the gate —
22 of the 29 findings do not touch the compat surface, and three of the seven that do are
surface-agnostic mechanisms built correctly at N6.

**Rejected: keeping compat first for adoption.** The protection against compat setting the project's
constraints is architectural, not chronological — a pure derived projection can be built at any point.
Ordering is the second line of defence, taken because compat built last is compat that *cannot* have
leaked.

**Rejected: a driver-declared trust class** to keep admin off the compat surface. It duplicates what
the projection table already says (RD-6) and puts exposure policy on the driver author. G-2 holds
better without it: the table simply has no entry for a `system` driver.

**Rejected: a third component kind** ("providers") for things with no bus. System configuration and
the store are drivers whose transport is not Modbus; a third kind buys a word and costs an
abstraction.

**Now owed:** the `driver-kit` boundary is guessed from one implementation, so N7 revisits it once
`driver-extension` exists to correct it.
