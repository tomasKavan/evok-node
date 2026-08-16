# 15 — Nextgen API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** our own WS and HTTP surface — designed rather than inherited.

**Covers**

- **One model, two transports.** WS and HTTP, and which is authoritative for what. Not two APIs.
- **Subscriptions and diffs:** what a client subscribes to, what a diff contains, ordering guarantees,
  resync after a gap, and backpressure. The mechanism is decided in 03; **its surface is decided
  here**, and the two must not drift.
- **Consumes every driver,** including ones written after this API. The introspection-driven schema,
  and what "stable" can mean for a schema that is derived rather than declared.
- **Public schema ownership and versioning,** and the `client` package's relationship to it.
- **ACL:** subjects, resources, actions, and where enforcement sits. The authentication *mechanism* is
  **deliberately deferred** (G-2 defers ports, paths and authentication; the deferral is tracked in
  [`STATUS.md`](../plan/STATUS.md)) — so state what ACL assumes of it and nothing more.
- **Serving the inspector UI** at the root.

**Inputs:** research/01 (as contrast) · research/08 · ADR-0003 (suspended) ·
[`STATUS.md`](../plan/STATUS.md), the undeclared-workspace-edges open question

**Open:** `client → api-nextgen` versus a separate `schema-nextgen` package, and the deferred auth
mechanism.
