# ADR-0001 — The core↔API contract is a serialisable message boundary

- **Status:** Accepted — generalised, not superseded, by ADR-0008 (2026-08-12)
- **Date:** 2026-08-10
- **Refs:** G-1 · docs/research/05-evok-node-design-notes.md §1, §5, §7.2, §7.3 · ADR-0008, ADR-0011, ADR-0012

> **Amendment, 2026-08-12.** Everything below stands. What changed is arithmetic: the boundary is
> *N drivers ↔ M APIs*, not one core ↔ one API layer, because ADR-0008 dissolved `core` and `server`.
> Three additions, none contradicting the decision:
>
> - **Provenance is satisfied by an explicit `Origin`** on every request envelope (`{ api, client? }`) —
>   the thing this ADR left owed for future write arbitration.
> - **Deadlines live in the envelope** (RC-26), making RC-14 structural on the message path rather than
>   a rule each call site must remember.
> - **Separate processes are now deliberately deferred**, with the reasoning in ADR-0012 — including why
>   `worker_threads` is not an intermediate step worth taking for 1.0. The codec keeps that option open
>   as a side effect, which is not why it exists.
>
> Introspection payloads (ADR-0010) are envelopes too, and the round-trip property test below covers
> them.

## Context

The library-first decision in research/05 §7.2 made `core/` usable without the API layer, and §5
concluded that a unix
socket or in-process mode would then be "purely additive later". That holds only if the boundary is
*already* expressible as messages. The post-1.0 direction has several API surfaces over one core —
classic compat, a new API, an admin surface, plugin-contributed routes — which makes running core
and API as separate processes a likely end state rather than a hypothetical.

A boundary that is merely a TypeScript interface will accumulate callbacks, class instances,
`Buffer`s, `EventEmitter`s and shared mutable objects, because nothing stops it. Each is invisible
in-process and fatal across one. Discovering that later means a rewrite of every adapter.

## Decision

The core↔API contract is defined as **serialisable message envelopes with an explicit codec
boundary**, from the first commit. Commands and events are data, validated by schema, with no host
object types in their shape. Delivery for 1.0 is in-process; the low-level transport itself remains
deferred per research/05 §7.3.

The `protocol` package holds this internal contract alongside the public wire schemas. Enforcement
is by review plus a schema round-trip property test on every envelope type — anything that does not
survive serialise/deserialise is not a valid message.

## Consequences

Makes easy: adding a second API surface; splitting into processes as a deployment change; testing
adapters against recorded message logs with no core running; a future unix-socket or shared-memory
transport.

Makes hard: any adapter that wants to hand core a callback or subscribe by passing a function. Those
become explicit subscription messages with correlation ids, which is more code for the single-process
case we ship first. Streaming large payloads is less natural than passing a `Buffer` would be.

Costs paid now for a benefit taken later — accepted deliberately, because the alternative is not
"decide later" but "decide by accident".

**Rejected:** keeping the TS-interface boundary and revisiting when the split is needed (research/05
§7.2's original framing). Rejected because the failure is silent and only detectable at the moment
it is most expensive. **Also rejected:** building multi-process now — it adds IPC, supervision and
write-arbitration work before any compat feature exists, and 1.0 does not need it.

**Now owed:** write-arbitration semantics for the case where several API processes issue conflicting
commands for one circuit. Not needed for 1.0's single process, but the envelope must carry enough
provenance (origin, ordering) that arbitration can be added without a schema break.
