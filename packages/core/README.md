# `@evok-node/core`

The daemon without an API: device registry, device model and decode, the scan scheduler, staleness,
aliases and groups. Consumes commands and emits events as serialisable envelopes — usable as a
library with no HTTP server present.

Duplicate circuit ids, or two circuits resolving to the same coil or (register, bit), are a fatal
startup error here. That check is what stops us silently driving the wrong relay.

**Must not depend on:** `server`, `inspector`, `client`, or any HTTP, WebSocket or transport-facing
code — `CLAUDE.md` rule 1, enforced by `dependency-cruiser`. The core↔API contract is messages, not
function calls: nothing crossing it may carry a callback, a class instance or a `Buffer` (ADR-0001).
One process today; the split must stay a deployment change.
