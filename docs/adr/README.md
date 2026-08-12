# Architecture Decision Records

One file per decision. **Immutable once accepted** — if a decision changes, write a new ADR that
supersedes it and mark the old one `Superseded by ADR-NNNN`. Never edit history; the point of an
ADR is that a reader can see what we knew at the time.

Naming: `NNNN-kebab-slug.md`, numbered sequentially.

## Why these exist

Agents reason from first principles when they lack context, and will confidently arrive at a
different answer than we did — often a defensible one, which is worse, because it looks like an
improvement. An ADR is the cheapest way to say *"this was considered; here is what we knew; do not
change it without a new ADR."*

Keep them to one page. The research files carry the evidence; the ADR carries the decision.

## Template

```markdown
# ADR-NNNN — <title>

- **Status:** Proposed | Accepted | Superseded by ADR-NNNN
  (`Accepted` may carry a trailing qualifier — `Accepted — mechanism deferred` — when the decision
  stands but a named part of it is deliberately left open. The qualifier names what is open.)
- **Date:** YYYY-MM-DD
- **Refs:** docs/research/NN-file.md §X

## Context
What forced a decision. Two or three sentences.

## Decision
What we chose, stated so a reader can act on it.

## Consequences
What this makes easy, what it makes hard, and what we now have to do because of it —
including any compensating control. Name the alternatives rejected and why.
```

## Numbering

**Numbers are allocated when the file is written, never reserved.** The next ADR takes the next free
number. An ADR's number is its identity, so a number that exists without a document behind it is a
dangling reference — and prose elsewhere will start citing it. Cite unwritten decisions by their
research section instead.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-core-api-message-boundary.md) | The core↔API contract is a serialisable message boundary | Accepted — generalised to N drivers ↔ M APIs by ADR-0008 |
| [0002](0002-conflicts-with-evok.md) | `Conflicts: evok`, with shared OS dependencies declared by us | Accepted — dependency list pending the capture trip |
| [0003](0003-migrate-once-not-runtime-fallback.md) | Migrate EVOK's config once; no runtime fallback to `/etc/evok` | Accepted |
| [0004](0004-four-kinds-of-data.md) | Four kinds of data; the daemon never writes its config | Accepted |
| [0005](0005-sqlite-user-data-store.md) | SQLite for user data, with YAML export/import | Accepted — `node:sqlite` stability to confirm |
| [0006](0006-admin-never-on-compat-surface.md) | Administration never rides on the classic surface | Accepted — mechanism deferred; now structural via ADR-0010's table |
| [0007](0007-simulator-has-its-own-framer.md) | The simulator does not depend on `modbus` | Accepted |
| [0008](0008-drivers-apis-and-main.md) | Drivers, APIs and main: two layers, N to M | Accepted |
| [0009](0009-driver-qualified-addressing.md) | Internal addresses are driver-qualified; the tail belongs to the driver | Accepted |
| [0010](0010-introspection-is-the-source-of-truth.md) | Drivers self-describe; compat's translate table is derived | Accepted |
| [0011](0011-main-is-never-in-the-data-path.md) | `main` orchestrates and is never in the data path | Accepted |
| [0012](0012-single-threaded.md) | Single-threaded, single event loop; not `worker_threads` | Accepted |
| [0013](0013-evok-3x-sole-compatibility-target.md) | EVOK 3.x is the sole compatibility target | Accepted |
| [0014](0014-library-first-service-second.md) | Library first, service second; nothing imports `main` | Accepted |
| [0015](0015-modbus-serial-with-supervising-wrapper.md) | `modbus-serial` behind our own port, with a supervising wrapper | Accepted |
| [0016](0016-hardware-definitions-extended-by-overlay.md) | Hardware definitions are extended by overlay; the OS image is read-only | Accepted |
| [0017](0017-nginx-fronts-the-compat-surface.md) | nginx remains the `:80` front end for the compat surface only | Accepted — evok's own nginx site pending the capture trip |
| [0018](0018-node-24-and-fastify.md) | Node.js 24, and fastify for HTTP | Accepted |
| [0019](0019-npm-workspaces-scoped-packages.md) | npm workspaces, with scoped `@evok-node/*` package names | Accepted |
| [0020](0020-hardware-scope.md) | Hardware scope: Patron, Neuron, Unipi 1.1, Extensions, Gate; Edge as a fast follow; Axon dropped | Accepted |
| [0021](0021-compat-flag-set.md) | The compat flag set is closed at five, and `wsAlwaysArray` defaults on | Accepted |
| [0022](0022-rig-is-sysfs-only.md) | The rig is sysfs-only and shares no code with what it measures | Accepted |
| [0023](0023-generated-address-tables-primary-safeguard.md) | Generated address tables are the primary safeguard, not a supplement | Accepted |

## Awaiting write-up

Settled decisions with no ADR yet — N0 task T0.7. **Unnumbered on purpose**: each takes the next free
number when someone writes it. Until then, cite the research section.

| Decision | Source |
|---|---|
| Licence choice | T0.6 — **not settled yet**: MIT or Apache-2.0 is still open, so there is no decision to record |

The other eleven rows became ADRs 0013–0023 on 2026-08-12. Two were reread against ADR-0008 rather
than transcribed: "library first, service second" (0014), whose `core`-based mechanism no longer
exists, and "nginx remains the `:80` front end" (0017), which is now narrowed to the compat surface
because `api-nextgen` serves the SPA at its own `/`.
