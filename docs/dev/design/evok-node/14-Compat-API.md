# 14 — Compat API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the EVOK 3.x surface as a **first-class deliverable** — the reason the project exists, not a
compatibility shim bolted to the side.

**Covers**

- **The premise.** Bug-for-bug is not the goal: we reproduce EVOK's *interface* and deliberately fix
  its defects, with every divergence enumerated in `COMPATIBILITY.md` (RD-3). Where compatibility and
  correctness genuinely conflict, this file states the tie-breaker.
- **Scope.** Understands the **onboard and extension drivers only**. Plugin devices are not projected
  here, and possibly not even their data types. Argue why that is a feature rather than a limitation.
- **The projection table:** derived from introspection, never hand-written. EVOK's naming, aliases and
  dev/circuit addressing fall out of it — show how.
- **At most one onboard driver; zero is legal.** Zero is the Gate, which serves an empty surface. EVOK
  itself degrades oddly here, so our behaviour is captured rather than inferred.
- **Legacy configuration:** which EVOK options we honour, which we accept and ignore, which we refuse
  — and the same three-way split for aliases.
- **Golden transcripts as the test method,** and what stays unverifiable until capture happens.

**Inputs:** research/01 · research/07 · research/14 · to_revision/0003, 0009 ·
`COMPATIBILITY.md` (RD-3)

**Open:** **blocked on golden-transcript capture** for the Gate's empty-surface shape and the
split-definition baseline. Time-sensitive and unrecoverable — see [`STATUS.md`](../plan/STATUS.md).

**Also open:** alias data is shared with `api-nextgen`, and apis can't reach each other or own
anything addressable (01 §6/§9) — needs a small owning driver exposing `CALL` endpoints
(`setAlias`/`resolveAlias`/...) backed by its own KV-store namespace, not raw shared KV access.
Design when writing 14/15.


-- From former ADRs

**The oracle is stock EVOK 3.0.6 as deployed on Unipi OS**, cross-read against upstream `main` at
`47c95c8`. Nothing earlier is a target. Where documentation and code disagree, **the code is the
contract** — clients were written against the running server. Where the code is outright broken (bulk
`group_*`, static 1-Wire sensors, RPC method signatures, `register` events, alt-name filters) we
implement the documented intent correctly and **with no flag**: no working client can depend on a
`TypeError`. **Alt-name acceptance on input is permanent** — that is EVOK 3 behaviour, not a v2
concession, and February 2026's client is the argument for keeping it forever.

**The flag set is exactly five, and closed.** A new payload fix does not mint a new flag without an ADR
(G-3). Every default reads backwards at first glance, so each has a named client behind it:

```yaml
compat:
  wsAlwaysArray: true       # repairs HA and phillipsnick's node, which crash against EVOK today.
                            #   Not legacy: the flag exists only to reproduce EVOK's object/array
                            #   inconsistency for A/B testing against a transcript. RC-21 is the rule
  legacyErrorStatus: true   # live requirement, both halves, by different clients: unipi-mqtt checks
                            #   status_code == 200 and ignores success; the vendor web UI relies on
                            #   jQuery's error: callback; pimatic reads success and not the status
  batchEvents: false        # evok2mqtt does json.loads(payload)[0], so a batched frame silently drops
                            #   N−1 devices. EVOK batches, so matching it would be defensible; off is
                            #   strictly better for that client and costs only frame overhead
  acceptAliasPrefix: true   # repairs Unipi's own v3 Node-RED node, which still builds v2 al_<alias>
                            #   into circuit, so aliased set commands from it silently do nothing
  emitLegacyDevNames: false # opt-in only, per-connection at most: enabling it also needs relay_type
                            #   and dev:"neuron", which breaks every conforming client
```

**`api-compat` listens on `:8080` with EVOK's paths, and nginx in front on `:80` remains a documented
deployment requirement for it.** The stock `evok` nginx site works unchanged because our port and paths
match; we ship a reference site file for from-scratch installs, and we neither generate nor edit one —
finding 4.7 is ten "fix nginx autodetection" commits deep and is precisely that failure class.
`api-nextgen` serves its own API and, when `ui: true`, the built SPA at its own `/`, same origin, from a
packaging path rather than a bundled import, so nothing imports `ui`. **A nextgen-only install needs no
nginx at all,** which the greenfield half of the drop-in guarantee requires. research/07 §5's "we do not
ship a built-in `:80` listener" is narrowed, not overruled: its subject is `api-compat`.

- Compat API only exposes what is in the original EVOK. The goal is not to have extendable copat API. It wouldn't make sense.
