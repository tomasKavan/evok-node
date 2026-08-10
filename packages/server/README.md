# `@evok-node/server`

The daemon. Fastify adapters for every EVOK 3.x surface — REST, JSON, bulk, WebSocket, webhook,
JSON-RPC — plus startup preflight, which refuses to run and names the offending unit if evok or
`unipitcp` holds the buses (GOALS invariant 7).

Speaks EVOK's vocabulary outward because clients depend on it, and translates at ingress using
`protocol`. Emits the flat projection of our model and nothing more: no groups, ordering, labels or
other field EVOK 3.0.6 did not emit (`CLAUDE.md` rule 17).

**Must not depend on:** `inspector`, `simulator`, `rig`, `client`. Never writes config — config is
operator intent, written by a human or the migration tool (ADR-0003, ADR-0004). Administration and
introspection never appear on this surface's compat routes (ADR-0006).
