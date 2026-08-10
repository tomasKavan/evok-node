# Goals

**Decided:** 2026-08-10. Amended only by a dated note or a superseding ADR.

This document answers *what are we trying to achieve, and what do we refuse to do*. It governs
[`research/`](research/README.md) (what is true), [`plan/`](plan/README.md) (what next) and
[`adr/`](adr/README.md) (why we decided). Where any of those state a goal, this file wins.

## The goal

EVOK is a load-bearing part of Unipi's FOSS stack. It is also a decade of accumulated fixes with a
long tail of open, known defects and limited maintainer attention. **evok-node is a drop-in
replacement that addresses the known defects.**

We inherit the *interface*, not the *design*.

## How we know we got it

"Reliability" is not measurable and will not be used as an acceptance argument. Two things are:

1. **Every finding in the bug corpus has a disposition.** The 29 findings in
   [research/04](research/04-known-bugs-and-lessons.md) — tiers 1.x through 4.x, with ~90 raw
   findings behind them in the appendix — are tracked in
   [`plan/bug-dispositions.md`](plan/bug-dispositions.md). Each resolves to exactly one of:
   *fixed with a regression test* · *fixed by construction* (the design makes it unrepresentable)
   · *compat-flagged* (fixed, with opt-in bug-compatible behaviour) · *won't fix* (with a reason)
   · *unverifiable without hardware* (with what is missing).
2. **The invariants in [`CLAUDE.md`](../CLAUDE.md) hold.** They are binary and mostly
   CI-enforced. A PR either satisfies them or it does not.

No uptime figures, latency SLOs or jitter budgets are committed here. Numbers invented before
measurement get quietly relaxed; the M6 soak measures real behaviour, and targets may be added
then as a dated amendment.

## What 1.0 is

**Compatibility complete, and every bug disposition closed.** Nothing else.

That is the scope of M0–M6 in [`plan/roadmap.md`](plan/roadmap.md), which exits at
`0.1.0-beta` — feature-complete against this definition. 1.0 is that same scope once it has
survived beta on real hardware; it adds no new capability. Everything in the next section ships
after it.

## Direction after 1.0

Committed direction, not existing features, and deliberately out of 1.0. Listed here because
several of them constrain decisions we must make *now* (see Invariants) — not because they are
scheduled.

- **Web SPA.** Not a port of `evok-web-jq` but a replacement: compact modern status display,
  filtering, sorting and search, control and configuration, and status rendered on PLC layout
  drawings rather than only in tables. This is the `inspector` package in
  [`CLAUDE.md`](../CLAUDE.md), promoted from debug tool to product. Cheap on the compat side —
  [research/07](research/07-client-compatibility.md) found `evok-web-jq` touches very little.
- **Logs and debug tooling over the API**, surfaced in the SPA.
- **PLC introspection**: processes, resource consumption, network status and configuration.
- **Plugins** extending the API, and optionally the SPA, with non-Unipi devices reachable from the
  PLC — DALI lighting control, M-Bus meter readout.
- **Event/trigger engine.** A lightweight rule machine — Node-RED without the visual editor —
  for scope-limited functions such as pump control and lighting timers. Fail-safe semantics on
  restart, reload and bus failure are **deliberately undecided**; they are settled before it is
  built, not now.

## Invariants

These follow from the goals above. They are here because each one is expensive or impossible to
retrofit, so they bind from the first commit even where the feature that motivates them is
post-1.0.

1. **Core↔API is a serialisable message boundary.** Not a function-call interface that happens to
   be crossable. One process for now; splitting core and API into separate processes later must be
   additive. A function-call boundary leaks callbacks, class instances and Buffers and makes the
   split a rewrite. Supersedes the "purely additive later" framing in
   [research/05](research/05-evok-node-design-notes.md) §5 and §7.3.
2. **Administration and introspection never ride on the classic surface.** Compat mode and
   new-API-with-admin are a configuration choice. The compat surface is unauthenticated by
   inheritance; a privileged config-and-control surface cannot share that trust level. Mechanism —
   ports, paths, authentication — is deferred to its own ADR.
3. **The compat surface is permanent, first-class, and never deprecated.** It is the reason the
   project exists. No feature may break it, and **richer internal metadata must never leak into
   its shapes** — compat sees the flat projection of our model, nothing more.
4. **One instance, one PLC.** As EVOK. Circuit ids stay flat. A SPA may point at several
   instances and aggregate client-side.
5. **Three kinds of data, three lifecycles.** Conflating them is where EVOK's alias handling
   failed (finding 3.9).

   | | Contents | Written by | Where |
   |---|---|---|---|
   | Config | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human, by hand | `/etc/evok-node/config.yaml` — **the daemon never writes it** |
   | User data | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users, through the API at runtime | `/var/lib/evok-node/` — durable store |
   | Readings | Current values, health, counters | The scan loop | Memory only, never persisted |

6. **A plugin cannot compromise the core.** It may not starve the scan loop, hold a bus past its
   lease, or take core down with it. A plugin needing bus access gets a leased, time-budgeted
   transaction through core — never a client of its own on a port the scan loop owns.
7. **evok and evok-node never run at the same time.** Not a policy: two processes cannot both own
   `/dev/ttyNS0`. Startup preflight refuses loudly if evok or `unipitcp` is active or the ttys are
   held, rather than racing for the port and failing unexplainably.

## The drop-in guarantee

What a user installing evok-node is promised:

- `Conflicts: evok`. Both cannot be installed at once — and since they cannot both run anyway,
  nothing is lost. We declare the shared OS dependencies ourselves so removing evok cannot
  autoremove them out from under us.
- **A one-shot migration** reads `/etc/evok/config.yaml` and `/var/lib/evok/alias.yaml` and writes
  our own config and store. The daemon has no knowledge of EVOK's config or alias formats; that
  knowledge lives in the migration tool alone, where it is a pure function and fixture-testable.
- `/etc/evok` is left pristine. **Rollback is `apt install evok`.**
- The migration tool warns about anything it cannot represent, at a moment a human is watching.

## Non-goals

Each is a thing a reasonable contributor might otherwise assume we want.

- **EVOK v2 compatibility.** Upstream declares v2→v3 migration unsupported.
- **Bug-for-bug fidelity.** We fix by default. Opt-in `compat` flags exist only for shape
  differences a working client could depend on — never to reproduce a `TypeError`.
- **Axon engineering effort.** Discontinued. Supported because the register maps are there and
  the model matches Neuron; it gets no dedicated work.
  ([research/09](research/09-test-hardware-coverage.md))
- **Any safety certification or SIL claim.** The trigger engine is process control. "Critical"
  in this document means *the user cares*, never *safety-rated*.
- **A visual flow editor.** The rule engine is configuration, not a canvas.
- **Replacing Mervis, or being a general-purpose PLC runtime.**
- **Cloud, multi-site or fleet orchestration.** Follows from invariant 4.
- **Timeseries storage of readings.** A different product. Readings live in memory
  (invariant 5).
- **Numeric performance targets before M6.** See above.

## Open

- Fail-safe semantics for the trigger engine.
- Authentication mechanism for the admin surface (invariant 2).
- Plugin isolation model — in-process with budgets, or out-of-process.
- Whether the post-1.0 surfaces are versioned as 2.x or shipped under a separate API path.
