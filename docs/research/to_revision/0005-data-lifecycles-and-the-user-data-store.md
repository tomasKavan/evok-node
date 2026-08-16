# ADR-0005 — SQLite for the user-data store

- **Status:** Accepted — `node:sqlite` stability to confirm against the pinned Node 24 minor
- **Date:** 2026-08-10
- **Refs:** G-5 · docs/research/04-known-bugs-and-lessons.md finding 3.9, R04-23, R04-25 ·
  docs/research/03-config-and-hw-definitions.md §2, §3, §4 · docs/research/10-test-kit.md ·
  ADR-0001, ADR-0006, ADR-0013

## Context

EVOK keeps aliases in RAM and flushes them to `/var/lib/evok/alias.yaml` on a 300 s timer with a
truncate-then-write and no flush on shutdown, so a clean restart loses up to five minutes of changes
and a crash mid-write leaves a truncated file (finding 3.9). The underlying mistake is treating
operator-authored configuration and user-authored runtime data as one "settings" problem. The post-1.0
direction sharpens it: aliases gain grouping, ordering, labels and SPA layout drawings, all created
through the API at runtime.

## Decision

**The four kinds of data, their lifecycles and their locations are G-5.** They are stated there and only
there — this ADR previously carried a second copy of that table, and the two had already drifted in
wording by the time anyone noticed (RD-6).

What this ADR decides is where the **user-data** row lives and in what.

**The user-data store is SQLite in `/var/lib/evok-node/`, via the built-in `node:sqlite`**, plus
`export` and `import` commands producing human-readable YAML. It is not `main`'s: it is
`driver-store`, a driver whose transport endpoint is a SQLite file (ADR-0001), or else every alias
write passes through `main`. Rationale in order of weight:

1. **Atomicity is structural**, not something we implement. R04-25's temp-file/fsync/rename dance
   becomes the database's problem, and it already solves it correctly.
2. **It fits the shape of the data.** Groups, ordering and layouts are relational; a single YAML
   document models them badly and rewrites everything on every change.
3. **Built in, so no native build** — this avoids the ARM prebuild problem entirely, and is the
   decisive practical argument over `better-sqlite3`. The test host is 1 GB RAM / 8 GB
   non-replaceable eMMC (research/10), so write amplification and armhf/arm64 prebuilds both matter.

Export/import are not optional extras: they restore what SQLite costs us — backups a human can read,
a site configuration that can live in git, and a diffable artefact for support.

**Note, 2026-08-13.** Two statements moved out of this file rather than being edited in place. The
lifecycle table is G-5's, per the RD-6 note above; and the platform-facts claim that we read EVOK's files
and extend them by overlay is **superseded by ADR-0014** — the definitions and the inventory are ours, and
nothing is read from `/etc/evok`. "The daemon never writes its config file" and frozen-per-load (RC-4) are
unaffected and live in G-5.

## Consequences

Makes easy: config stays hand-editable and git-trackable with no write-back race. Durability lands on
one component instead of being scattered. Config validation can report every error at once and exit
non-zero (R04-13) because it has no mutable half-state. And querying for the SPA's filter/sort/search
without loading everything into memory.

Makes hard: anything the API might want to change that looks like configuration — a scan rate, an
enabled API — cannot be changed through the API without either an explicit config-reload story or
promotion to user data. The post-1.0 SPA offers "configuration", so that boundary needs deciding per
field. Deciding it per field is the point; the alternative is a daemon that rewrites its own config
and a user whose hand edits vanish. The on-disk store format is also opaque, so support and backup
flows go through `export`, and schema migrations become ours to own and test with fixtures.

**Consequent invariant:** because user data is richer than EVOK's flat alias map, the compat surface
emits only the flat projection of it — G-3.

**Open, and it gates nothing yet.** In Node 24 `node:sqlite` needs no flag but is **not marked fully
stable**; sources disagree on whether the pinned minor sits at "active development" or "release
candidate". Confirm against the exact minor before the store is implemented; if the API is still
moving, `better-sqlite3` is the fallback and we take on ARM prebuilds. Tracked in `plan/STATUS.md`.

**Rejected:**

- **One settings store covering config and user data,** as EVOK effectively has — it is what produced
  finding 3.9 and makes hand-editing unsafe.
- **YAML or JSON files with atomic writes** for the store. Hand-editable and dependency-free, and it
  would fix finding 3.9 — but it models groups and layouts poorly, rewrites the world on every change
  on wear-sensitive eMMC, and gives the SPA nothing to query. Export/import recovers its only real
  advantage.
