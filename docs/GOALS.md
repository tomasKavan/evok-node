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
   [`plan/bug-dispositions.md`](plan/bug-dispositions.md). Each resolves to one of: *fixed with a
   regression test* · *fixed by construction* (the design makes it unrepresentable) ·
   *compat-flagged* (fixed, with opt-in bug-compatible behaviour) · *won't fix* (with a reason).
   A fix may additionally be marked *unverifiable* where hardware we do not have would be needed to
   prove it, naming the gap.
2. **The rules in [`docs/rules/`](rules/code.md) hold.** They are binary and mostly CI-enforced. A
   PR either satisfies them or it does not.

Cite an invariant in this file as **G-N** — see the citation table in
[`CLAUDE.md`](../CLAUDE.md).

No uptime figures, latency SLOs or jitter budgets are committed here. Numbers invented before
measurement get quietly relaxed; the M6 soak measures real behaviour, and targets may be added
then as a dated amendment.

## What 1.0 is

**Compatibility complete, and every bug disposition closed.** Nothing else.

That is the scope of N0–N10 in [`plan/roadmap.md`](plan/roadmap.md), which exits at
`0.1.0-beta` — feature-complete against this definition. 1.0 is that same scope once it has
survived beta on real hardware; it adds no new capability. Everything in the next section ships
after it.

**The path changed, the definition did not (2026-08-12).** ADR-0001 re-steered the build order: the
core is built first and the compat surface arrives as the last consumer rather than the first thing
implemented. The reason compat cannot set the project's constraints is architectural — it emits a
derived projection (G-3, RC-24) — and ordering is the secondary safeguard. Only 7 of the 29 findings
depend on the compat surface, so this costs little against the measurable half of this definition.
See [research/12](research/12-modularisation.md).

## Direction after 1.0

Committed direction, not existing features, and deliberately out of 1.0. Listed here because
several of them constrain decisions we must make *now* (see Invariants) — not because they are
scheduled.

- **Web SPA.** Not a port of `evok-web-jq` but a replacement: compact modern status display,
  filtering, sorting and search, control and configuration, and status rendered on PLC layout
  drawings rather than only in tables. This is the `inspector` package in
  [`CLAUDE.md`](../CLAUDE.md), promoted from debug tool to product. `evok-web-jq` is a small dependent
  — research/05 §2.1 found it touches very little, and only requirement 22 in
  [research/07](research/07-client-compatibility.md) is exclusive to it — but replacing it retires
  nothing, because G-3 keeps the compat surface regardless of who uses it.
- **Edge support.** A fast follow-up to 1.0, decided in research/05 §8.3. It is listed here as
  direction, but with one obligation that lands **now**: the overlay hardware-definition format must
  already accommodate per-channel mode sets, per-model mode enums and unit-0 devices, or the first
  minor release breaks the format.
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

1. **G-1 — Driver↔API is a serialisable message boundary.** Not a function-call interface that happens to
   be crossable. One process for now; splitting components into separate processes later must be
   additive. A function-call boundary leaks callbacks, class instances and Buffers and makes the
   split a rewrite. Supersedes the "purely additive later" framing in
   [research/05](research/05-evok-node-design-notes.md) §5 and §7.3.

   **Amended 2026-08-12** (ADR-0001): the boundary is *N drivers ↔ M APIs*, not one core ↔ one API
   layer. ADR-0001's substance stands; what changed is the number of participants, that drivers hold
   the only copy of state while APIs are stateless translators, and that `main` sits on no request
   path at all (ADR-0001). Rationale: [research/12](research/12-modularisation.md).
2. **G-2 — Administration and introspection never ride on the classic surface.** Compat mode and
   new-API-with-admin are a configuration choice. The compat surface is unauthenticated by
   inheritance; a privileged config-and-control surface cannot share that trust level. Mechanism —
   ports, paths, authentication — is deferred to its own ADR.

   **Note, 2026-08-12.** Under ADR-0001 this became structural rather than a policy: `api-compat` can
   only emit what its projection table describes, and that table has no entry for a `system` driver.
   Admin cannot reach the compat surface even if an administrator lists it in `drivers:`. Explicitly
   *not* implemented as a trust label on the driver — what a surface exposes is the surface's own
   business (RC-24, ADR-0001).
3. **G-3 — The compat surface is permanent, first-class, and never deprecated.** It is the reason the
   project exists. No feature may break it, and **no internal metadata leaks into its shapes** —
   compat sees the flat projection of our model, never our groups, ordering, labels or any other
   field EVOK 3.0.6 did not emit. Payload *fixes* are the exception: each is listed in
   `COMPATIBILITY.md` (RD-3) and carries a flag from the closed set settled in
   [research/07 §7](research/07-client-compatibility.md). A new payload fix does not mint a new flag
   without an ADR.
4. **G-4 — One instance, one PLC.** As EVOK. Circuit ids stay flat. A SPA may point at several
   instances and aggregate client-side.
5. **G-5 — Four kinds of data, four lifecycles.** Conflating the first two is where EVOK's alias handling
   failed (finding 3.9).

   | | Contents | Written by | Where |
   |---|---|---|---|
   | Config | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human by hand, or the migration tool at install — **never the daemon** | `/etc/evok-node/config.yaml` |
   | User data | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users, through the API at runtime | `/var/lib/evok-node/` — durable store |
   | Platform facts | What the hardware *is*: `autogen.yaml`, `hw_definitions/*.yaml`, our overlays, our generated autogen equivalent | The OS image and `unipi-os-configurator`, **or us** — never a human by hand | OS image paths as EVOK reads them, plus our own overlay and cache paths |
   | Readings | Current values, health, counters | The scan loop | Memory only, never persisted |

   Platform facts are descriptions of hardware, not intent. We read EVOK's, in EVOK's format and in
   place, unaffected by ADR-0006's migration. We also **generate our own** — research/05 §2.5 requires
   an autogen equivalent so we do not hard-depend on `unipi-os-configurator`, and §2.6 requires
   extending the definition format by overlay (research/05 §8.5). **Frozen per load, not once per process**:
   immutable and `readonly` while loaded (RC-4), and reloaded when hardware change is detected.

   **Correction, 2026-08-12.** This previously said "continuous discovery is the fix for finding
   2.1". Finding 2.1 is not about discovery: registration was always declarative from config, and the
   bug is that registration was *gated on a one-shot reachability probe*. Reachability is a state of a
   registered endpoint, retried forever. Genuine discovery exists only on buses that have it, and is a
   declared driver capability. A **readings** value may also be a structure, not only a scalar
   (RC-20) — read-only device configuration is a structured reading, so it needs no fifth category
   here.

6. **G-6 — A plugin cannot compromise the daemon.** It may not starve a scan loop, hold a bus past its
   lease, or take the process down with it. A plugin needing bus access gets a leased, time-budgeted
   transaction through the driver that owns that bus — never a client of its own on a port a scan loop
   owns. (Reworded 2026-08-12: "the core" was a package that ADR-0001 dissolved. Unchanged in
   substance, and ADR-0001's manifest loading is the mechanism this will use.)
7. **G-7 — evok and evok-node never run at the same time.** Not a policy: two processes cannot both own
   `/dev/ttyNS0`. Startup preflight refuses to start if evok is active or the ttys are held — loudly,
   and **naming the conflicting unit** — rather than racing for the port and failing unexplainably.

   **Correction, 2026-08-12 — needs Tomas's confirmation.** This previously also refused to start when
   `unipitcp` was active. That cannot be right: EVOK never speaks SPI, and local I/O *is* Modbus TCP
   to `unipitcp` on `127.0.0.1:502` ([raw-hardware-research
   §166](research/appendix/raw-hardware-research.md), Unipi KB `en:sw:02-apis:02-modbus-tcp`). So
   `driver-onboard` **requires** `unipitcp` running; refusing on it would leave onboard I/O with no
   transport at all. Read as scoped to `evok` itself and to the RS-485 ttys, which is what the stated
   reason — two processes cannot both own `/dev/ttyNS0` — actually supports. Reverse this note if the
   original intent was different.

## The drop-in guarantee

What a user installing evok-node is promised:

- `Conflicts: evok`. Both cannot be installed at once. Since they cannot both *run* anyway, the only
  thing this costs is a fast switch back. We declare the shared OS dependencies ourselves so
  removing evok cannot autoremove them out from under us.
- **A one-shot migration** reads `/etc/evok/config.yaml` and `/var/lib/evok/alias.yaml` and writes
  our own config and store. It is a separate tool, run by the operator or by packaging — never by
  the daemon, which has no knowledge of EVOK's config or alias formats and writes no config at all.
  That knowledge lives in the migration tool alone, where it is a pure function and
  fixture-testable.
- `/etc/evok` is left pristine. **Rollback is `apt install evok`.**
- The migration tool warns about anything it cannot represent, at a moment a human is watching.
- **A greenfield install works without EVOK ever having been present.** Packaging ships a default
  config; the migration tool is for machines coming *from* EVOK, not a prerequisite. The daemon exits
  non-zero with an actionable message if config is absent — it does not generate one.

## Non-goals

Each is a thing a reasonable contributor might otherwise assume we want.

- **EVOK v2 compatibility.** Upstream declares v2→v3 migration unsupported.
- **Bug-for-bug fidelity.** We fix by default. Opt-in `compat` flags exist only for shape
  differences a working client could depend on — never to reproduce a `TypeError`.
- **Axon.** Out of scope, and no support is claimed. Its map CSVs stay in
  `docs/modbus-reg-map/axon/` as free cross-check data for the Neuron register model — that is all.
  ([research/09 §5](research/09-test-hardware-coverage.md), superseding the round-1 framing in
  research/05 §7.1)
- **Any safety certification or SIL claim.** The trigger engine is process control. "Critical"
  in this document means *the user cares*, never *safety-rated*.
- **A visual flow editor.** The rule engine is configuration, not a canvas.
- **Replacing Mervis, or being a general-purpose PLC runtime.**
- **Cloud, multi-site or fleet orchestration.** Follows from G-4.
- **Timeseries storage of readings.** A different product. Readings live in memory
  (G-5).
- **Numeric performance targets before M6.** See above.

## Open

- **Whether G-7's `unipitcp` clause was intended** — see the correction on G-7. Blocks nothing until
  N5, and decides whether `driver-onboard` has a transport.
- Fail-safe semantics for the trigger engine.
- Authentication mechanism for the admin surface (G-2), its default-on or default-off
  posture, and how it interacts with the nginx front end (research/07 §5).
- Plugin isolation model — in-process with budgets, or out-of-process. Narrowed 2026-08-12: 1.0 is
  single-threaded, single event loop (ADR-0004), so this is a post-1.0 question and the message
  boundary is what keeps the options open.
- Whether the post-1.0 surfaces are versioned as 2.x or shipped under a separate API path.
- Write-arbitration semantics once more than one API process can issue commands (ADR-0001).
- How much of `inspector` ships inside 1.0. The roadmap lands it after M4 as a consumer of the
  public API; the full SPA above is post-1.0. The line between them is not yet drawn.
