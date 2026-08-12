# ADR-0005 — Four kinds of data, and SQLite for the user-data store

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

Four kinds of data, four lifecycles, four locations:

| | Contents | Written by | Where |
|---|---|---|---|
| **Config** | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human by hand, or the migration tool at install (ADR-0006) | `/etc/evok-node/config.yaml` |
| **User data** | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users at runtime, through an API and then `driver-store` | `/var/lib/evok-node/` |
| **Platform facts** | What the hardware is: EVOK's `autogen.yaml` and `hw_definitions/*.yaml`, our overlays, our generated autogen equivalent | The OS image, `unipi-os-configurator`, or us — never a human by hand | EVOK's paths in EVOK's format, read in place; ours alongside (ADR-0007) |
| **Readings** | Current values, health, counters | The scan loop | Memory only |

**The daemon never writes its config file.** Not "avoids writing" — never; that is why migration is a
separate tool (ADR-0006). Readings are never persisted; a timeseries product is an explicit non-goal.

Platform facts are the row most easily got wrong, because "read EVOK's files" is only half of it. We
**also generate** an autogen equivalent keyed on a `unipiid` fingerprint, so we do not hard-depend on
`unipi-os-configurator` (research/05 §2.5), and we **extend** the definition format by overlay rather
than reusing it verbatim (ADR-0007). What makes it one category is that it describes hardware rather
than intent, and that a human never hand-authors it.

**Frozen per load, not once per process.** Immutable and `readonly` while loaded (RC-4, which exists
because of the `deepcopy` aliasing bug, finding 1.3) — but reloadable when hardware change is
detected. Load-once-at-startup *is* finding 2.1, the highest-leverage item in the corpus.

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
