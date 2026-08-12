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
| [0001](0001-core-api-message-boundary.md) | The core↔API contract is a serialisable message boundary | Accepted |
| [0002](0002-conflicts-with-evok.md) | `Conflicts: evok`, with shared OS dependencies declared by us | Accepted — dependency list pending the capture trip |
| [0003](0003-migrate-once-not-runtime-fallback.md) | Migrate EVOK's config once; no runtime fallback to `/etc/evok` | Accepted |
| [0004](0004-four-kinds-of-data.md) | Four kinds of data; the daemon never writes its config | Accepted |
| [0005](0005-sqlite-user-data-store.md) | SQLite for user data, with YAML export/import | Accepted — `node:sqlite` stability to confirm |
| [0006](0006-admin-never-on-compat-surface.md) | Administration never rides on the classic surface | Accepted — mechanism deferred |
| [0007](0007-simulator-has-its-own-framer.md) | The simulator does not depend on `modbus` | Accepted |

## Awaiting write-up

Settled decisions with no ADR yet — M0 task T0.7. **Unnumbered on purpose**: each takes the next free
number when someone writes it. Until then, cite the research section.

| Decision | Source |
|---|---|
| EVOK 3.x as the sole compatibility target | research/05 §7 |
| Library first, service second | research/05 §7.2 |
| `modbus-serial` plus a supervising wrapper, not our own framer | research/05 §8.4 |
| Hardware definitions extended by overlay, never by editing the OS image | research/05 §8.5 |
| nginx remains the `:80` front end | research/07 §5 |
| Node.js 24; fastify for HTTP | research/05 §8.6, §8.11 |
| npm workspaces; scoped `@evok-node/*` package names | 2026-07-29 planning session |
| Hardware scope: Patron, Neuron, Unipi 1.1, Extensions, Gate; Edge as fast follow; Axon dropped | research/05 §8.3 |
| Compatibility flag set, and `wsAlwaysArray` defaulting on | research/07 §7 |
| The rig uses sysfs only and shares no code with the code under test | research/10 |
| Generated address tables as the primary safeguard, given no purchasable hardware exceeds 16 channels of one type in a single section | research/10 §4 |
| Licence choice | T0.6 |
