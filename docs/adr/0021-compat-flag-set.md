# ADR-0021 — The compat flag set is closed at five, and `wsAlwaysArray` defaults on

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/07-client-compatibility.md §7, §2, §4, §6 ·
  docs/research/05-evok-node-design-notes.md §2.1 · docs/GOALS.md G-3 · RC-21, RD-3 · ADR-0013

## Context

We fix EVOK's bugs by default. That still leaves shape differences a *working* client could depend on,
and the question is how many knobs those need. Reading the source of every known client
([research/07](../research/07-client-compatibility.md)) turned an open-ended list into a short one,
and each entry now has a named client behind it rather than a hypothesis.

## Decision

**The flag set is exactly five, with these defaults:**

```yaml
compat:
  wsAlwaysArray: true
  legacyErrorStatus: true
  batchEvents: false
  acceptAliasPrefix: true
  emitLegacyDevNames: false
```

`emitGlobDevId` is dropped: zero hits across eight clients, two protocol libraries and the vendor web
UI. **The set is closed** — a new payload fix does not mint a new flag without an ADR (G-3).

Why each default is what it is, since every one of them reads backwards at first glance:

- **`wsAlwaysArray: true` is not a legacy accommodation.** Always-array *repairs* HA (uncaught
  `AttributeError`) and phillipsnick's node (which takes down the whole Node-RED process), both of
  which crash against EVOK today. RC-21 is the rule; the flag exists only to reproduce EVOK's
  object/array inconsistency for A/B testing against a captured transcript.
- **`legacyErrorStatus: true` is a live requirement, not legacy.** `unipi-mqtt` checks
  `status_code == 200` and ignores `success`; the vendor web UI relies on jQuery's `error:` callback;
  pimatic reads `success` and not the status. Both halves are load-bearing, by different clients.
- **`batchEvents: false`** — evok2mqtt does `json.loads(payload)[0]`, so a batched frame silently
  drops N−1 devices. EVOK itself batches, so matching it would be defensible; defaulting off is
  strictly better for that client and costs only WebSocket frame overhead.
- **`acceptAliasPrefix: true`** repairs Unipi's *own* v3 Node-RED node, which still builds v2
  `al_<alias>` into `circuit`, so aliased set commands from the vendor's node silently do nothing.
- **`emitLegacyDevNames: false`** is opt-in only, and per-connection at most. Turning it on would also
  need `relay_type` and `dev:"neuron"`, which breaks every conforming client (ADR-0013).

## Consequences

Makes easy: an operator-visible list of exactly what we do differently, one line per divergence, each
with an entry in `COMPATIBILITY.md` backed by a golden transcript or marked untested (RD-3). Two of
the five let us A/B our fixed behaviour against stock EVOK, which is how a divergence gets attributed
rather than argued about.

Makes hard: every flag is a second code path with its own transcript test. That cost is why the set is
closed — a flag with no named client behind it is a configuration surface nobody asked for, and
five is already the width of the compat test matrix.

**Rejected: no flags at all.** Tempting, since four of the five defaults are simply "correct". But the
fixed side of `wsAlwaysArray` and `legacyErrorStatus` cannot be compared against stock EVOK without a
switch, and `batchEvents` is a genuine choice between matching EVOK and not breaking a real client.

**Rejected: `emitGlobDevId`,** which the original sketch in research/05 §2.1 included. It survives in
EVOK's documentation and in no client.

**Rejected: per-connection scoping for the whole set.** Only `emitLegacyDevNames` plausibly needs it.
Per-connection state that changes payload shape is the bug class behind EVOK's WS filter, and config is
where an operator can actually see what their server emits.

**Rejected: a generic `compat.level` (`strict` | `fixed`).** It bundles unrelated choices, so a client
needing one bug-compatible shape would silently get the other four as well.
