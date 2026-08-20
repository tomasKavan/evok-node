# 04 — Storage kit

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** how a module persists anything, without inventing its own file handling.

**Covers**

- **What may be persistent at all,** and the lifecycle classes: config-derived, learned-at-runtime,
  user-owned. Losing one must not mean the same thing as losing another — that distinction is the
  reason this file exists.
- **Key-value store, scoped per spawned instance.** Namespacing, atomicity, expected size, and
  behaviour across upgrade and rollback.
- **Owned-SQLite helper:** creating, migrating and opening a module's own database file. Migration
  ordering, and what a failed migration leaves behind.
- **On-disk layout:** where files live, who owns them, and how packaging and backup see them.
- **Concurrency:** two instances against one store, and the same store across a reload.
- Whether **APIs** get storage at all, or only drivers. 13 says APIs hold no state; this is where the
  exception is either carved out or refused.

**Inputs:** to_revision/0005 · [`STATUS.md`](../plan/STATUS.md), the `node:sqlite` open question

**Open:** the sqlite implementation (`node:sqlite` versus `better-sqlite3`, see STATUS), and whether
the KV store is its own file, a table in the module's database, or both.
