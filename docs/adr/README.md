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

## Index

### Written

| # | Decision | Status |
|---|---|---|
| [0013](0013-core-api-message-boundary.md) | The core↔API contract is a serialisable message boundary | Accepted |
| [0014](0014-conflicts-with-evok.md) | `Conflicts: evok`, with shared OS dependencies declared by us | Accepted — dependency list pending the capture trip |
| [0015](0015-migrate-once-not-runtime-fallback.md) | Migrate EVOK's config once; no runtime fallback to `/etc/evok` | Accepted |
| [0016](0016-three-tier-data-model.md) | Three kinds of data; the daemon never writes its config | Accepted |
| [0017](0017-sqlite-user-data-store.md) | SQLite for user data, with YAML export/import | Accepted — `node:sqlite` stability to confirm |
| [0018](0018-admin-never-on-compat-surface.md) | Administration never rides on the classic surface | Accepted — mechanism deferred |

### Awaiting write-up

Populated in M0 task T0.7. Decisions already settled:

| # | Decision | Source |
|---|---|---|
| 0001 | EVOK 3.x as the sole compatibility target | research/05 §7 |
| 0002 | Library first, service second | research/05 §7.2 |
| 0003 | `modbus-serial` plus a supervising wrapper, not our own framer | research/05 §8.4 |
| 0004 | Hardware definitions extended by overlay, never by editing the OS image | research/05 §8.5 |
| 0005 | nginx remains the `:80` front end | research/07 §5 |
| 0006 | Node.js 24; fastify for HTTP | research/05 §8.6, §8.11 |
| 0007 | npm workspaces; scoped `@evok-node/*` package names | this session |
| 0008 | Hardware scope: Patron, Neuron, Unipi 1.1, Extensions, Gate; Edge as fast follow; Axon dropped | research/05 §8.3 |
| 0009 | Compatibility flag set, and `wsAlwaysArray` defaulting on | research/07 §7 |
| 0010 | The rig uses sysfs only and shares no code with the code under test | research/10 |
| 0011 | Generated address tables as the primary safeguard, given no purchasable hardware exceeds 16 channels of one type | research/10 §4 |
| 0012 | Licence choice | T0.6 |
