# ADR-0014 — Library first, service second: `main` is a composition root and nothing imports it

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §7.2, §5 ·
  docs/research/12-modularisation.md §Package layout · ADR-0008, ADR-0011, ADR-0001 · docs/GOALS.md G-1

## Context

[research/05 §7.2](../research/05-evok-node-design-notes.md) decided that the npm package is the
primary artifact and the systemd service a thin wrapper around it. Its mechanism was `core/`
exporting a programmatic `registry.get/set/on`, with every API an omittable adapter over it.
ADR-0008 dissolved `core`, so the decision has to be restated in the new shape or dropped. The
substance survives — nobody should need the daemon to use our code — but the thing it named does
not, and a reader finding the old wording would reintroduce `core` to satisfy it.

## Decision

**Every package is independently consumable, and `main` is a composition root that nothing depends
on.** "Library" now means a driver package, an API package, or one of the shared packages —
`messaging`, `modbus`, `hw-definitions`, `driver-kit`, `client`.

- **No package imports `main`.** The layering table in `.dependency-cruiser.cjs` lists `main` as no
  package's dependency, so "the service is a thin wrapper" is a missing edge rather than a claim.
  The systemd unit runs `main` and adds nothing but process supervision.
- Packages publish as `@evok-node/*` (ADR-0019); `rig` is the one exception and is never published
  (RC-11).
- **Config enters as an object, not a path** — the one bullet from §7.2 that transfers unchanged.
  An embedder needs no `/etc/evok-node`.

**What replaces the `registry.get/set/on` bullet:** an embedder's entry point is the message
boundary, not a function call into a driver's state. A driver holds the only copy of its endpoint's
state (ADR-0008) and answers envelopes (G-1, ADR-0001). So an embedder either hosts drivers itself
and speaks the envelope contract, or runs `api-nextgen` and uses `client`. There is no synchronous
in-process accessor, and adding one is the thing this ADR exists to prevent.

## Consequences

Makes easy: using one piece without the rest — the simulator with no driver, an API against recorded
introspection with no daemon, `modbus` on its own. A plugin driver can ship as its own npm package
with no API release (RC-30). And it keeps `main` genuinely off the request path, since a package that
cannot import it cannot route through it (ADR-0011).

Makes hard: there is no zero-copy fast path for an embedder in the same process. That is G-1's
deliberate cost, and research/05 §5's latency table is why it is affordable — a 50 Hz scan puts you
20 ms from the hardware, which dominates any IPC or call-overhead choice by an order of magnitude.

**Rejected: a façade package re-exporting a synchronous registry** for embedders who want the old
`core` ergonomics. It is `core` under a new name, and ADR-0008's reason for dissolving it applies
unchanged: anything sitting between drivers and APIs recreates the layer that was removed, and
everything it could hold belongs to a driver.

**Rejected: making the `.deb` the primary artifact and the libraries a by-product.** The drop-in
guarantee makes the Debian package the primary *deliverable to operators* (ADR-0002), which is not
the same claim. A daemon-first structure is exactly how an assumption that `main` exists leaks into a
driver, and there is no compiler check that catches it once the edge is allowed.
