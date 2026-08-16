# Architecture Decision Records — under revision

**Suspended 2026-08-16. Nothing binding may cite an ADR until this set is re-locked.** The whole set
moved here, into `docs/research/`, because it is now input to the development documentation rather
than settled output. Expect ADRs to be rewritten, merged and dropped during that pass; the
immutability lock that held from 2026-08-12 is lifted for its duration and goes back on — with a
dated note here — before development starts.

Read these for the reasoning that produced them. Do not treat any of them as a decision in force.

Naming: `NNNN-kebab-slug.md`, numbered sequentially.

## Why these exist

Agents reason from first principles when they lack context, and will confidently arrive at a different
answer than we did — often a defensible one, which is worse, because it looks like an improvement. An
ADR is the cheapest way to say *"this was considered; here is what we knew; do not change it without a
new ADR."*

The research files carry the evidence; the ADR carries the decision. A rejected alternative gets one
sentence — what it was and why it lost — because that sentence is the whole guard rail.

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
What this makes easy, what it makes hard, and what we now have to do because of it — including any
compensating control. Then **Rejected:**, one line each.
```

## Numbering

**Numbers are allocated when the file is written, never reserved.** The next ADR takes the next free
number. An ADR's number is its identity, so a number that exists without a document behind it is a
dangling reference — and prose elsewhere will start citing it. Cite unwritten decisions by their
research section instead.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-drivers-apis-and-main.md) | Drivers, APIs and `main`: two layers over a message bus | Accepted |
| [0002](0002-driver-qualified-addressing.md) | Internal addresses are driver-qualified; the tail belongs to the driver | Accepted |
| [0003](0003-introspection-is-the-source-of-truth.md) | Drivers self-describe; compat's translate table is derived | Accepted |
| [0004](0004-single-threaded.md) | Single-threaded, single event loop; not `worker_threads` | Accepted |
| [0005](0005-data-lifecycles-and-the-user-data-store.md) | SQLite for the user-data store | Accepted — `node:sqlite` stability to confirm |
| [0006](0006-conflicts-with-evok-and-migrate-once.md) | `Conflicts: evok`; EVOK's config migrated once by a separate tool | Accepted — dependency list pending the capture trip |
| [0007](0007-hardware-definitions-by-overlay.md) | Hardware definitions are extended by overlay; the OS image is read-only | Superseded by [0014](0014-hardware-definitions-and-inventory-are-ours.md) |
| [0008](0008-hardware-scope.md) | Hardware scope: Patron, Neuron, Unipi 1.1, Extensions, Gate; Edge a fast follow; Axon dropped | Accepted |
| [0009](0009-the-compat-surface.md) | The compat surface: stock EVOK 3.0.6, five flags, port 8080, no administration | Accepted — admin authentication deferred |
| [0010](0010-modbus-serial-behind-our-own-port.md) | `modbus-serial` behind our own port, with a supervising wrapper | Accepted |
| [0011](0011-instruments-share-no-code-with-the-subject.md) | Test instruments share no code with what they measure | Accepted |
| [0012](0012-generated-address-tables.md) | Generated address tables are the primary safeguard, not a supplement | Accepted |
| [0013](0013-workspaces-node-24-and-fastify.md) | npm workspaces, scoped `@evok-node/*` names, Node 24 and fastify | Accepted |
| [0014](0014-hardware-definitions-and-inventory-are-ours.md) | Hardware definitions and inventory are ours; nothing is read from `/etc/evok` | Accepted |

## Awaiting write-up

Settled decisions with no ADR yet. **Unnumbered on purpose**: each takes the next free number when
someone writes it. Until then, cite the research section.

| Decision | Source |
|---|---|
| Licence choice | T0.6 — **not settled yet**: MIT or Apache-2.0 is still open, so there is no decision to record |

## The 2026-08-12 consolidation

The set reached 23 ADRs, of which seven described one architecture and four described one surface. It
was consolidated to the 13 above: merged where several files carried one decision, cut to the decision
plus one line per rejected alternative, and reread against the modularisation — ADR-0001 still named
the dissolved `core` and `protocol` packages, the store was not identified as `driver-store`, and the
old ADR-0006's deferred mechanism had already been replaced by the projection table.

Numbering was restarted rather than left gapped, because the set was pre-1.0 and unreleased. **This
table is the one-time redirect; delete it at the `0.x-alpha` smoothing pass (RD-5).**

| Old | New |
|---|---|
| 0001 core↔API message boundary, 0008 drivers/APIs/main, 0011 main not in the data path, 0014 library first | **0001** |
| 0009 driver-qualified addressing | **0002** |
| 0010 introspection is the source of truth | **0003** |
| 0012 single-threaded | **0004** |
| 0004 four kinds of data, 0005 SQLite user-data store | **0005** |
| 0002 `Conflicts: evok`, 0003 migrate once | **0006** |
| 0016 hardware definitions extended by overlay | **0007** |
| 0020 hardware scope | **0008** |
| 0006 admin never on compat, 0013 EVOK 3.x sole target, 0017 nginx fronts compat, 0021 compat flag set | **0009** |
| 0015 `modbus-serial` with supervising wrapper | **0010** |
| 0007 simulator has its own framer, 0022 rig is sysfs-only | **0011** |
| 0023 generated address tables | **0012** |
| 0018 Node 24 and fastify, 0019 npm workspaces | **0013** |
