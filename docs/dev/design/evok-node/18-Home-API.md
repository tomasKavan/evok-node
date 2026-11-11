# 18 — Home API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** the Home UI's and the shell app's api — home devices only, on `ws-kit` (13 §1).

**Covers**

- **What it adds to `ws-kit`:** understands only the home driver (12a); everything else it links, `kv` included, is never relayed (13 §6).
- **Management subset:** which `manage.<method>` tails it relays (12a §5).
- **Auth and ACL** as WS extensions using 13a; `actor` and `access` (13 §5) — a door lock's `unlock`. Uses the access marks as the types wrote them (05a §3.1b), with no override.
- **Defaults:** port, TLS (13 §9).
- **Remote home devices:** what a client sees of a device imported from another PLC (12a §4b).

**Inputs:** 13 · 15 · 12a §4b, §5 · 12b · 13a
