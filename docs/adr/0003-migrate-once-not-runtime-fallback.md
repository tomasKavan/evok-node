# ADR-0003 — Migrate EVOK's config once; no runtime fallback to `/etc/evok`

- **Status:** Accepted
- **Date:** 2026-08-10
- **Refs:** docs/GOALS.md §The drop-in guarantee · docs/research/03-config-and-hw-definitions.md §1, §3 · ADR-0002

## Context

An earlier design had the daemon read `/etc/evok-node/config.yaml` if present and otherwise fall
back to `/etc/evok/config.yaml` plus `/var/lib/evok/alias.yaml`, with config flags selecting which
source won for each concern.

That puts EVOK's config and alias formats — and their traps, catalogued in research/03: the
`autogen.yaml` deep-merge, the alias file silently yielding `{}` for any unexpected `version` (the
docs' own example writes `version: 2.0` unquoted, which YAML parses as a float), the non-atomic
writes — permanently inside the daemon's startup path. It also creates precedence logic
whose failures are undiagnosable in the field: "which file won?" is exactly the class of question
research/04 §4.6 shows Unipi's support load is made of.

Aliases are mutable through the API, so a fallback also needs a write policy: write into
`/var/lib/evok/alias.yaml` and we mutate another package's state, breaking clean rollback; write to
our own store and the two sources diverge silently.

## Decision

**A one-shot migration tool**, run explicitly by the operator or by packaging — **never by the
daemon.** It reads `/etc/evok/config.yaml` and `/var/lib/evok/alias.yaml` and writes
`/etc/evok-node/config.yaml` plus our own store (ADR-0005). After that the two installations share
no state.

That the migrator, not the daemon, writes the config file is what keeps ADR-0004 and G-5 absolute. If no config exists, the daemon reports that and exits non-zero naming what to do;
it does not helpfully generate one.

**Greenfield installs do not depend on the migrator.** A machine that never ran EVOK has nothing to
migrate, so packaging ships a **default config as a conffile**. The migrator is the path *from* EVOK,
not the only path in — otherwise a fresh install would exit non-zero pointing at a tool with no
inputs.

The daemon has **no knowledge of EVOK's config or alias formats**. That knowledge lives only in the
migration tool.

The tool accepts explicit input paths so it can run against a backup or a copy, and it warns — at a
moment a human is watching — about anything it cannot represent.

`/etc/evok` is never written. `autogen.yaml` and `hw_definitions/*.yaml` are unaffected by this ADR:
they remain runtime daemon inputs read from the OS image, as research/03 §2 and §4 describe.

## Consequences

Makes easy: a strict, versioned, single-source config schema that is ours alone. Testing — the
migrator is a pure function `(evok config, alias file) → (our config, store)` and gets golden
fixtures from the capture trip, the same discipline as everything else in the project. Clean
rollback, because EVOK's files are untouched.

Makes hard: nothing at runtime. The cost is one more artefact to build and a documented step for the
operator.

**Ordering trap.** With ADR-0002's `Conflicts: evok`, evok is already removed by the time evok-node
installs. `apt remove` leaves the inputs in place, so migration still works — but `apt purge` does
not, hence the standalone tool and the explicit "migrate before purging" warning.

**Rejected:** runtime fallback with per-concern source flags. It was the original design; it loses on
diagnosability and on permanently coupling the daemon to a format we are replacing.
