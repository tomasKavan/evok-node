# ADR-0004 — Four kinds of data; the daemon never writes its config

- **Status:** Accepted
- **Date:** 2026-08-10
- **Refs:** docs/GOALS.md invariant 5 · docs/research/04-known-bugs-and-lessons.md finding 3.9, rules 23 and 25 · docs/research/03-config-and-hw-definitions.md §2, §3, §4

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

Four kinds of data, four lifecycles, four locations:

| | Contents | Written by | Where |
|---|---|---|---|
| **Config** | Operator intent: buses, ports, scan rates, enabled APIs, auth, compat flags | A human by hand, or the migration tool at install | `/etc/evok-node/config.yaml` |
| **User data** | Aliases, groups, ordering, labels, layout drawings, rules, plugin settings | Users, via the API at runtime | `/var/lib/evok-node/` (ADR-0005) |
| **Platform facts** | What the hardware is: EVOK's `autogen.yaml` and `hw_definitions/*.yaml`, our overlays, our generated autogen equivalent | The OS image, `unipi-os-configurator`, or us — never a human by hand | EVOK's paths in EVOK's format, read in place; ours alongside |
| **Readings** | Current values, health, counters | The scan loop | Memory only |

**The daemon never writes its config file.** Not "avoids writing" — never; ADR-0003's migration is a
separate tool for exactly this reason. Readings are never persisted; that is a timeseries product and
an explicit non-goal.

Platform facts are the row most easily got wrong, because "read EVOK's files" is only half of it.
research/05 §2.5 requires we **also generate** an autogen equivalent, keyed on a `unipiid`
fingerprint, so we do not hard-depend on `unipi-os-configurator`; §2.6 requires we **extend** the
definition format by overlay rather than reuse it verbatim (research/05 §8.5, and the
base→overlay→site merge in M3). So we both consume and produce this category — what makes it a category is that it describes
hardware rather than intent, and that a human never hand-authors it.

**Frozen per load, not once per process.** Immutable and `readonly` while loaded (`CLAUDE.md`
rule 10, which exists because of the `deepcopy` aliasing bug, finding 1.3) — but reloadable when
hardware change is detected. Load-once-at-startup *is* finding 2.1, the highest-leverage item in the
corpus.

## Consequences

Makes easy: config stays hand-editable and git-trackable with no write-back race, and a reviewer can
diff a site's intent. Durability requirements land only on the store, where research/04 rule 25
(atomic write, flush on shutdown) applies to one component instead of being a scattered concern.
Config validation can report every error at once and exit non-zero (research/04 rule 13) because it
has no mutable half-state.

Makes hard: anything the API might want to change that looks like configuration — a scan rate, an
enabled API — cannot be changed through the API without either an explicit config-reload story or
promotion to user data. The post-1.0 SPA offers "configuration", so that boundary will need
deciding per field. Deciding it per field is the point; the alternative is a daemon that rewrites its
own config and a user whose hand edits vanish.

**Consequent invariant:** because user data is richer than EVOK's flat alias map, the compat surface
must emit only the flat projection of it — GOALS.md invariant 3, `CLAUDE.md` rule 17.

**Rejected:** one settings store covering both, as EVOK effectively has. It is what produced finding
3.9 and makes hand-editing unsafe.
