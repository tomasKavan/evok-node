# 16 — Inspector UI

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** the SPA that makes a running daemon observable, testable and configurable.

**Covers**

- **Scope: observe, test, configure** — in that order of confidence. And what it must never let you do
  by accident, because the other end of these endpoints is plant equipment.
- **It is part of the nextgen API, not a peer.** Served at nextgen's root, redirecting to `/ui`,
  speaking the **public API only** — no private channel, no privileged endpoint.
- **Views:** table (dense, every endpoint, live) and visual (device-shaped, per model). What each is
  actually for.
- **Live data** via subscriptions and diffs, and what the UI does when it falls behind, reconnects, or
  loses a driver.
- **Auth and ACL:** the same model as nextgen, with write and test actions gated.
- **Configuration editing** through the `main` driver (02a): forms from module schemas (03a §4), `validate` before `apply`, progress, conflicts, static entries read-only, left-out entries shown with their issues; what the SPA does when the api serving it reloads (02a §7).
- **Remote PLCs (12a §4b):** adding a remote offers only that PLC's home drivers.

**Inputs:** 15 · 02a · 03a · research/01 · [`STATUS.md`](../../plan/STATUS.md), the `ui → client` open question

**Open:** the `ui → client` dependency, and whether configuration editing is in 1.0 at all.
