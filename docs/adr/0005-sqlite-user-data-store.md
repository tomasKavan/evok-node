# ADR-0005 — SQLite for user data, with YAML export/import

- **Status:** Accepted — `node:sqlite` stability to confirm against the pinned Node 24 minor
- **Date:** 2026-08-10
- **Refs:** G-5 · ADR-0004 · R04-25, finding 3.9 · docs/research/05-evok-node-design-notes.md §8.6 (Node.js 24) · docs/research/10-test-kit.md (test-host hardware)

## Context

ADR-0004 gives user data its own store. It has to survive a crash mid-write — EVOK's
truncate-then-write lost alias files (finding 3.9) — and it has to hold data that is not flat:
groups with members, explicit ordering, labels, and SPA layout drawings as blobs. Writes are
user-initiated and therefore rare; reads are frequent.

The target hardware constrains the choice. The test host in research/10 is 1 GB RAM / 8 GB
non-replaceable eMMC, and production units are similar, so write amplification matters. These are
also ARM boards, where a native module means maintaining armhf and arm64 prebuilds or building on
device.

## Decision

**SQLite in `/var/lib/evok-node/`, via the built-in `node:sqlite`**, plus `export` and `import`
commands producing human-readable YAML.

Rationale, in order of weight:

1. **Atomicity is structural**, not something we implement. R04-25's temp-file/fsync/rename dance
   becomes the database's problem, and it already solves it correctly.
2. **It fits the shape of the data.** Groups, ordering and layouts are relational; a single YAML
   document models them badly and rewrites everything on every change.
3. **Built in, so no native build.** Avoids the ARM prebuild problem entirely — the decisive
   practical argument over `better-sqlite3`.
4. **Write amplification is far lower** than rewriting a whole file on a timer, which is what we are
   replacing.

The export/import commands are not optional extras: they restore the properties SQLite costs us —
backups a human can read, a site configuration that can live in git, and a diffable artefact for
support.

## Consequences

Makes easy: durability, concurrent readers, schema migration as a known pattern, and querying for
the SPA's filter/sort/search without loading everything into memory.

Makes hard: the on-disk format is opaque, so support and backup flows must go through `export`.
Schema migrations become a thing we own and test — with fixtures, since a migration that corrupts
user data is as bad as the bug we are fixing.

**Open, and it gates nothing yet.** In Node 24 `node:sqlite` is available without the
`--experimental-sqlite` flag but is **not marked fully stable**; sources disagree on whether the
pinned minor sits at "active development" or "release candidate" on Node's stability index, and that
distinction matters enough to check rather than assume. Confirm against the exact minor before the
store is implemented; if the API is still moving, `better-sqlite3` is the fallback and we take on ARM
prebuilds. Tracked in `plan/STATUS.md` open questions.

**Rejected:** YAML or JSON files with atomic writes. Hand-editable and dependency-free, and it would
fix finding 3.9 — but it models groups and layouts poorly, rewrites the world on every change on
wear-sensitive eMMC, and gives the SPA nothing to query. Export/import recovers its only real
advantage.
