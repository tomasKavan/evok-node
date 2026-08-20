# Architecture Decision Records — dissolved, kept as proposals

**Suspended 2026-08-16. Dissolved 2026-08-18 — the set does not come back**, and the re-lock promised
in the note that stood here is withdrawn. ADRs are no longer a documentation kind in this project:
[`docs/dev/`](../../dev/README.md) is the single home for the design *and* the reasoning behind it, and
a decision recorded in two places is a bug (RD-6). The one thing `dev/` could not have provided on its
own — protection against later rewriting — is now RD-8's job instead.

**These fourteen files are proposals, binding on nothing.** Each records reasoning that mostly still
stands, and each is **absorbed** when a dev doc decides it: by restating it, narrowing it, or rejecting
it with a reason. Until then it is input, not authority.

`ADR-NNNN` is no longer a citable prefix. Cite one of these as a research path —
`research/to_revision/0010 §Decision` — never as a decision in force. See the citation table in
[`docs/README.md`](../../README.md).

**Nothing new is added here.** A decision made from now on is written in the dev doc that owns it. The
template and numbering conventions below are kept because the existing files follow them, not because
another file is coming.

Naming: `NNNN-kebab-slug.md`, numbered sequentially.

## Why these existed

Agents reason from first principles when they lack context, and will confidently arrive at a different
answer than we did — often a defensible one, which is worse, because it looks like an improvement. An
ADR was the cheapest way to say *"this was considered; here is what we knew; do not change it without a
new ADR."*

**That job did not go away — it moved.** RD-8 requires every dev doc to say what it rejected and why,
to mark every departure from research, and to leave a dated line when it reverses itself; and it forbids
a smoothing pass from deleting any of that. The research files still carry the evidence.

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

Historical. **Numbers were allocated when the file was written, never reserved**, because an ADR's
number was its identity and a number without a document behind it is a dangling reference that prose
elsewhere starts citing. No number is allocated from here again.

## Index

**Absorbed by** is where each proposal is owed an answer — the file that must restate it, narrow it, or
reject it with a reason. `owed` means M3 has not got there yet. When every row is settled, M3's
absorption of this set is complete; that is the only mechanical completeness check the milestone has.

| # | Proposal | Absorbed by |
|---|---|---|
| [0001](0001-drivers-apis-and-main.md) | Drivers, APIs and `main`: two layers over a message bus | `dev/01` — owed |
| [0002](0002-driver-qualified-addressing.md) | Internal addresses are driver-qualified; the tail belongs to the driver | `dev/03` — owed |
| [0003](0003-introspection-is-the-source-of-truth.md) | Drivers self-describe; compat's translate table is derived | `dev/03`, `dev/14` — owed |
| [0004](0004-single-threaded.md) | Single-threaded, single event loop; not `worker_threads` | `dev/01` — owed |
| [0005](0005-data-lifecycles-and-the-user-data-store.md) | SQLite for the user-data store | `dev/04` — owed |
| [0006](0006-conflicts-with-evok-and-migrate-once.md) | `Conflicts: evok`; EVOK's config migrated once by a separate tool | `dev/02`, `dev/21` — owed |
| [0007](0007-hardware-definitions-by-overlay.md) | Hardware definitions are extended by overlay; the OS image is read-only | none — superseded by [0014](0014-hardware-definitions-and-inventory-are-ours.md) before dissolution |
| [0008](0008-hardware-scope.md) | Hardware scope: Patron, Neuron, Unipi 1.1, Extensions, Gate; Edge a fast follow; Axon dropped | **`GOALS §Hardware scope`, 2026-08-18** |
| [0009](0009-the-compat-surface.md) | The compat surface: stock EVOK 3.0.6, five flags, port 8080, no administration | `dev/14` — owed; admin authentication was already deferred |
| [0010](0010-modbus-serial-behind-our-own-port.md) | `modbus-serial` behind our own port, with a supervising wrapper | `dev/07`, `dev/09` — owed |
| [0011](0011-instruments-share-no-code-with-the-subject.md) | Test instruments share no code with what they measure | **`RT-15`, 2026-08-18.** `dev/19` and `dev/20` still owe the reasoning |
| [0012](0012-generated-address-tables.md) | Generated address tables are the primary safeguard, not a supplement | `dev/07` — owed |
| [0013](0013-workspaces-node-24-and-fastify.md) | npm workspaces, scoped `@evok-node/*` names, Node 24 and fastify | `dev/21` — owed |
| [0014](0014-hardware-definitions-and-inventory-are-ours.md) | Hardware definitions and inventory are ours; nothing is read from `/etc/evok` | `dev/02`, `dev/07` — owed |

Two proposals carried a named open part when the set was locked, and dissolving it does not close
either: `0005`'s `node:sqlite` stability and `0006`'s dependency list, which waits on the capture trip.
Both are open questions in [`plan/STATUS.md`](../../plan/STATUS.md), which is where they are tracked.

## The 2026-08-12 consolidation

The set reached 23 ADRs, of which seven described one architecture and four described one surface. It
was consolidated to 13 — `0001`–`0013` above; `0014` was written after the consolidation — merged where
several files carried one decision, cut to the decision
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
