# ADR-0001 — Drivers, APIs and `main`: two layers over a message bus

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/GOALS.md G-1, G-2, G-3, G-6 · docs/research/12-modularisation.md ·
  docs/research/05-evok-node-design-notes.md §1, §5, §7.2, §7.3

## Context

The original design had one `core` package and one `server` package, with compat built first. `core`
bundled four responsibilities — registry, device model, scheduler, aliases — whose lifecycles have
nothing in common, so every later driver or surface had to be threaded through it. And scheduling
compat before the model it projects is how a projection quietly becomes the model (G-3, RC-24).

Separately, a boundary that is merely a TypeScript interface accumulates callbacks, class instances,
`Buffer`s and shared mutable objects, because nothing stops it. Each is invisible in-process and
fatal across a process split.

## Decision

**Serialisable message envelopes, and two layers: drivers act, APIs query.**

**The contract is messages.** Commands and events are data — zod-validated, no host object types,
surviving serialise/deserialise, which a round-trip property test asserts on every envelope type.
Every request envelope carries an explicit `Origin` (`{ api, client? }`) and a deadline (RC-26), so
RC-14 is structural on the message path rather than remembered at each call site. `messaging` holds
this internal contract and **no package's public wire schema** (RC-12). Delivery for 1.0 is
in-process; the transport itself stays deferred (research/05 §7.3).

**A driver** owns exactly one transport endpoint, polls it, and holds the **only** copy of that
endpoint's state. A transport need not be a bus: the filesystem, a process-exec surface and a SQLite
file all qualify, so system configuration (`driver-system`) and the user-data store (`driver-store`,
ADR-0005) are drivers too. **There is no third component kind.**

**An API** is a stateless translator between the bus and one public protocol. One package per
surface, owning its own schema — `api-compat` cannot leak our groups, labels or ordering into an EVOK
payload if it imports nothing that has them, so G-3 becomes a missing edge in the dependency graph
rather than a review rule. What a surface exposes is that surface's own business: `drivers:` in config
is an administrator restriction, not capability negotiation (RC-31).

**`main` parses config, validates, spawns, supervises and reloads. Nothing else, and no request ever
passes through it.** It statically imports no concrete driver or API — both are manifest-resolved from
config (RC-10); without that, `main` has an import edge to everything and the property is
unenforceable. What genuinely requires `main` is **resource exclusivity**, because no other component
sees enough config to check it: two drivers on one transport endpoint (which is how
one-driver-per-endpoint and G-7 are actually enforced), two APIs on one listen port, and an API's
`drivers:` naming an absent driver. All three are config-parse checks needing no handshake, so they
fail before anything is spawned or any port is bound — which is also finding **2.7**'s fix, whose
evidence is port conflicts causing systemd restart storms because they were detected at bind time.
**Startup is single-phase**, because driver-qualified addressing (ADR-0002) leaves no global namespace
to assemble.

**Every package is independently consumable, and nothing imports `main`.** The layering table in
`.dependency-cruiser.cjs` lists `main` as no package's dependency, so "the service is a thin wrapper"
is a missing edge rather than a claim; the systemd unit runs `main` and adds only process supervision.
**Config enters as an object, not a path** — an embedder needs no `/etc/evok-node`, and its entry point
is the message boundary, not a synchronous accessor into a driver's state: either host drivers and
speak envelopes, or run `api-nextgen` and use `client`.

Consequent rules, all in [`rules/code.md`](../../rules/code.md): RC-10, RC-26, RC-27, RC-28, RC-29,
RC-30, RC-31, RC-32.

**The build order changes; the definition of 1.0 does not.** The compat surface moves from M4 to N9,
last rather than first.

## Consequences

Makes easy: adding a surface or a driver without touching the others; a plugin driver with no API
release (RC-30); testing an API against recorded introspection with no driver running; using one
piece without the rest — `modbus` alone, the simulator with no driver; splitting into processes later
as a deployment change, since the boundary is already messages.

Makes hard: nothing may hold shared mutable state, by construction. Cross-driver aggregation is
explicit fan-in (RC-28) rather than one lookup, and an adapter wanting to pass a callback uses
subscription messages with correlation ids. There is no zero-copy fast path for an in-process
embedder — G-1's deliberate cost, affordable because a 50 Hz scan already puts you 20 ms from the
hardware (research/05 §5), which dominates any call-overhead choice. Thirteen packages instead of
nine. And for a long stretch no surface exists that anyone can adopt: the feedback loop is
`api-nextgen` and `ui`, and `bug-dispositions.md` stays the gate — 22 of the 29 findings do not touch
compat.

**Now owed.** Write-arbitration semantics for conflicting commands from several API processes: not
needed for 1.0's single process, but the envelope must already carry enough provenance to add it
without a schema break. Reload asymmetry is RC-32's, and the natural implementation — one code path
shared with boot — silently inherits the wrong behaviour. And `driver-kit`'s boundary is guessed from
one implementation, so N7 revisits it once `driver-extension` exists.

**Rejected:**

- **A TypeScript-interface boundary,** revisited when a process split is needed — the failure is
  silent and surfaces only when it is most expensive to fix.
- **Multi-process for 1.0** — IPC, supervision, state resync and write arbitration before any compat
  feature exists.
- **Compat first, for adoption** — a pure derived projection can be built at any point, so ordering is
  the second line of defence; compat built last is compat that *cannot* have leaked.
- **A driver-declared trust class** to keep administration off the compat surface — it duplicates the
  projection table (RD-6) and puts exposure policy on the driver author (ADR-0009).
- **A third component kind** ("providers") for things with no bus — buys a word, costs an abstraction.
- **`main` serving the address→driver lookup** — the smallest possible step into the data path, and
  unnecessary once addresses are qualified.
- **Two-phase startup** (spawn, collect declarations, validate globally, then spawn APIs) — designed
  before ADR-0002 and made pointless by it.
- **A façade re-exporting a synchronous registry** for embedders wanting `core`'s ergonomics — it is
  `core` under a new name, and everything it could hold belongs to a driver.
- **The `.deb` as the primary artifact.** It is the primary *deliverable to operators* (ADR-0006),
  which is a different claim; a daemon-first structure is how an assumption that `main` exists leaks
  into a driver, and no compiler check catches it once the edge is allowed.
