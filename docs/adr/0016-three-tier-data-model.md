# ADR-0016 — Three kinds of data; the daemon never writes its config

- **Status:** Accepted
- **Date:** 2026-08-10
- **Refs:** docs/GOALS.md invariant 5 · docs/research/04-known-bugs-and-lessons.md findings 3.9, 2.4, rules 23 and 25 · docs/research/03-config-and-hw-definitions.md §3

## Context

EVOK keeps aliases in RAM and flushes them to `/var/lib/evok/alias.yaml` on a 300 s timer with a
truncate-then-write and no flush on shutdown — so a clean restart loses up to five minutes of
changes, and a crash mid-write leaves a truncated file (finding 3.9). The underlying mistake is
treating operator-authored configuration and user-authored runtime data as one undifferentiated
"settings" problem.

The post-1.0 direction makes this sharper. Aliases stop being a flat `name → circuit` map and gain
grouping, ordering, labels and SPA layout drawings, all created through the API at runtime. Putting
any of that in `config.yaml` would mean the daemon writing a file a human also hand-edits.

## Decision

Three kinds of data, three lifecycles, three locations:

| | Contents | Written by | Where |
|---|---|---|---|
| **Config** | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human, by hand | `/etc/evok-node/config.yaml` |
| **User data** | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users, via the API at runtime | `/var/lib/evok-node/` (ADR-0017) |
| **Readings** | Current values, health, counters | The scan loop | Memory only |

**The daemon never writes its config file.** Not "avoids writing" — never. And readings are never
persisted; that is a timeseries product and an explicit non-goal.

## Consequences

Makes easy: config stays hand-editable and git-trackable with no write-back race, and a reviewer can
diff a site's intent. Durability requirements land only on the store, where research/04 rule 25
(atomic write, flush on shutdown) applies to one component instead of being a scattered concern.
Config validation can report every error at once and exit non-zero (rule 13) because it has no
mutable half-state.

Makes hard: anything the API might want to change that looks like configuration — a scan rate, an
enabled API — cannot be changed through the API without either an explicit config-reload story or
promotion to user data. The post-1.0 SPA offers "configuration", so that boundary will need
deciding per field. Deciding it per field is the point; the alternative is a daemon that rewrites its
own config and a user whose hand edits vanish.

**Consequent invariant:** because user data is richer than EVOK's flat alias map, the compat surface
must emit only the flat projection of it — GOALS.md invariant 3, `CLAUDE.md` rule 17.

**Rejected:** one settings store covering both, as EVOK effectively has. It is what produced finding
3.9 and makes hand-editing unsafe.
