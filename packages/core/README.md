# `@evok-node/core`

The daemon without an API: device registry, device model and decode, the scan scheduler, staleness,
aliases and groups. Consumes commands and emits events as serialisable envelopes — usable as a
library with no HTTP server present.

The registry is where RC-18 is enforced — the check that stops us silently driving the wrong relay.
Readings carry staleness (RC-20) and every source emits one envelope (RC-21).

**Must not depend on:** `server`, `inspector`, `client`, or any HTTP, WebSocket or transport-facing
code — RC-10, enforced by `dependency-cruiser`. One process today; the split must stay a deployment
change (G-1, ADR-0001).
