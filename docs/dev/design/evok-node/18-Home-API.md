# 18 — Home API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** the Home UI's and the shell app's api — home devices only, on `ws-kit` (13 §1).

**Covers**

- **What it adds to `ws-kit`:** understands only the home driver (12a); everything else in its `drivers:` but KV is skipped (13 §6).
- **Management subset:** which `manage.<method>` tails it relays (12a §5).
- **Auth and ACL** as WS extensions using 13a; `actor` and `proof` (13 §5) — a door lock's `unlock`.
- **Defaults:** port, TLS (13 §9).
- **Remote home devices:** what a client sees of a device imported from another PLC (12a §4b).

**Inputs:** 13 · 15 · 12a §4b, §5 · 12b · 13a
