# 06 — KV-store driver

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during [M3](../plan/roadmap.md); do not implement against a memo. Replaces "04 — Storage kit": the same ground, but as a driver (`driver-kv-store`), not a library — 01 §2 already said user data's transport is a database file, and this is that driver.

**Job:** a namespaced key-value store, reachable from other drivers and apis the same way any driver is (01 §5–§7), so no module has to invent its own file handling.

**Covers**

- **The four operations:** `has`, `get`, `set`, `delete`. Nothing richer — no ranges, no transactions across keys. A caller that needs more is asking for a different kind of storage, not a bigger version of this one.
- **Namespacing, not arbitration.** 01 §7 draws the parallel with a shared transport: a transport driver arbitrates races, this driver only separates callers. A namespace defaults to the caller's own driver id from config, and a caller may override it in its own config snippet — so two instances of the same driver type never collide by accident, and a deliberate shared namespace is still possible when asked for.
- **In-memory first.** 01 §8's non-blocking rule applies here exactly as it does to every other driver: `has`/`get` answer from an in-memory mirror, never from a synchronous disk read. What `set`/`delete` promise about durability before their response returns is still open (see Open).
- **On-disk layout and the backing store.** Where a namespace's data actually lives, one file per namespace or one shared file — undecided, see Open.
- **Concurrency across a reload.** What a namespace's caller is promised about in-flight `set`/`delete` calls when its own driver instance restarts or reloads (02 §7).
- **Whether apis get a namespace too**, or only drivers. Nothing in 01 restricts it either way; this file decides it.

**Open:** the backing store. `node:sqlite` vs `better-sqlite3` vs a plain append-only file per namespace — undecided, and it is this file's call to make, not `main`'s or any caller's.

**Inputs:** 01 §2, §5, §6, §7 (the KV-store driver is 01's worked second example of a shared, driver-owned resource)
