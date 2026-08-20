# Goals

This document answers *what are we trying to achieve, and what do we refuse to do*. It governs
[`research/`](research/README.md) (what is true) and [`plan/`](plan/README.md) (what next). Where
either states a goal, this file wins.

## The goal

EVOK is a load-bearing part of Unipi's FOSS stack. It is also a decade of accumulated fixes with a
long tail of open, known defects and limited maintainer attention. **evok-node is a drop-in
replacement that addresses the known defects.**

We are offering EVOK's *interface* as a compat api, but we are not inheriting the EVOK *design*.

## How we know we got it

"Reliability" is not measurable and will not be used as an acceptance argument. Two things are:

1. **Every finding in the bug corpus has a disposition.** The 29 findings in
   [research/04](research/04-known-bugs-and-lessons.md) — tiers 1.x through 4.x, with ~90 raw
   findings behind them in the appendix — are tracked in
   [research/14](research/14-bug-dispositions.md). Each resolves to one of: *fixed with a
   regression test* · *fixed by construction* (the design makes it unrepresentable) ·
   *compat-flagged* (fixed, with opt-in bug-compatible behaviour) · *won't fix* (with a reason).
   A fix may additionally be marked *unverifiable* where hardware we do not have would be needed to
   prove it, naming the gap.
2. **The rules in [`docs/rules/`](rules/code.md) hold.** They are binary and mostly CI-enforced. A
   PR either satisfies them or it does not.

Cite an invariant in this file as **G-N** — see the citation table in
[`docs/README.md`](./README.md).

No uptime figures, latency SLOs or jitter budgets are committed here. Numbers invented before
measurement get quietly relaxed. A soak on real hardware measures real behaviour, and targets may be
added afterwards as a dated amendment.

## What 1.0 is

**TBD.** Settled during the development-documentation pass, not before it.

The measurable-success section above is unaffected: it says *how* we will know, and that does not
depend on where the line is drawn.

## Hardware scope

**1.0 supports Patron, Neuron, Unipi 1.1, Extensions and Gate.** Same as EVOK 3.

**Edge is a fast follow after 1.0, and the definition format must already accommodate it** —
eg. per-channel mode sets and enums (4–20 mA, 90–2000 Ω against the PLC families' 0–20 mA
and 0–1960 Ω), and unit-0 devices.

**Axon is dropped** — see Non-goals. **`Iris` is disregarded**: named in `evok/config.py:79` and in
`unipi-tools`' README, but in no public product line.

## Invariants

These follow from the goals above. They are here because each one is expensive or impossible to
retrofit, so they bind from the first commit even where the feature that motivates them is
post-1.0.

1. **G-1 — Driver↔API is a serialisable message boundary.** Not a function-call interface that happens to
   be crossable. One process for now; splitting components into separate processes later must be
   additive. A function-call boundary leaks callbacks, class instances and Buffers and makes the
   split a rewrite. Supersedes the "purely additive later" framing in
   [research/05](research/05-evok-node-design-notes.md) §5 and §7.3.

2. **G-3 — The compat surface is permanent, first-class, and never deprecated.** It is the important reason the
   project exists. No feature may break it, and **no internal metadata leaks into its shapes** —
   compat sees the flat projection of our model, never our groups, ordering, labels or any other
   field EVOK 3.0.6 did not emit. Payload *fixes* are the exception: each is listed in
   `COMPATIBILITY.md` (RD-3) and carries a flag from the closed set settled in
   [research/07 §7](research/07-client-compatibility.md). A new payload fix does not mint a new flag
   without a recorded design decision in `dev/14`.

3. **G-4 — One instance, one PLC.** As EVOK. Circuit ids stay flat. A SPA may point at several
   instances and aggregate client-side.

4. **G-5 — Four kinds of data, four lifecycles.** Conflating the first two is where EVOK's alias handling failed (finding 3.9).

   | | Contents | Written by | Where |
   |---|---|---|---|
   | Config | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human by hand, or the migration tool at install — **never the daemon** | `/etc/evok-node/config.yaml` |
   | User data | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users, through the API at runtime | `/var/lib/evok-node/` — durable store |
   | Platform facts | What the hardware *is*: our hardware definitions, our generated inventory | **Us alone** — our package ships the definitions, our generator writes the inventory; never a human by hand, never the daemon | `<pkg>/definitions/`, `/etc/evok-node/hw_definitions/custom/`, `/etc/evok-node/autogen.yaml` |
   | Readings | Current values, health, counters | The scan loop | Memory only, never persisted |

   Platform facts are descriptions of hardware, not intent. **Frozen per load, not once per process**:
   immutable and `readonly` while loaded (RCD-4), and reloaded when hardware change is detected.

5. **G-6 — A driver or api module (internal or plugin) cannot compromise the daemon.** It may not starve a scan loop, hold a bus past its
   lease, or take the process down with it. A plugin needing bus access gets a leased, time-budgeted
   transaction through the driver that owns that bus — never a client of its own on a port a scan loop
   owns. 

6. **G-7 — evok and evok-node never run at the same time.** Not a policy: two processes cannot both own `/dev/ttyNS0` and connect to the same Modbus TCP server. Startup preflight refuses to start if evok is active or the ttys are held — loudly, and **naming the conflicting unit** — rather than racing for the port and failing unexplainably.

   Scoped to `evok` itself and to the RS-485 ttys. `unipitcp` is not a conflict: local I/O *is* Modbus
   TCP to it on `127.0.0.1:502` ([raw-hardware-research
   §166](research/appendix/raw-hardware-research.md), Unipi KB `en:sw:02-apis:02-modbus-tcp`), so
   onboard I/O requires it running.

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
  Keeping it because the maps are already there was rejected: a claim of support is a claim to test, on
  hardware we will never buy for a discontinued line.
  ([research/09 §5](research/09-test-hardware-coverage.md), superseding the round-1 framing in
  research/05 §7.1)
- **Any safety certification or SIL claim.** The trigger engine is process control. "Critical"
  in this document means *the user cares*, never *safety-rated*.
- **A visual flow editor.** The rule engine is configuration, not a canvas.
- **Replacing Mervis, or being a general-purpose PLC runtime.**
- **Cloud, multi-site or fleet orchestration.** Follows from G-4.
- **Timeseries storage of readings.** A different product. Readings live in memory
  (G-5).
- **Numeric performance targets before they have been measured.** See above.

