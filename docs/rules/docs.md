# Documentation rules

Binding. Cite as **RD-N**.

**Brevity is the rule, not a preference.** Long documentation goes stale, and stale documentation is
worse than none because it is believed. If you can delete a sentence and lose nothing, delete it.

**RD-1 — Document the non-obvious *why*, never the *what*.** The what is in the code and the types.

Do not write:

> `getRegister(count, index)` — gets `count` registers starting at `index`.

Do write:

> Reads from the cache snapshot, not the bus. Returns `null` if the block has never been read —
> "no value yet" and "value 0" are different, and clients depend on the distinction.

**RD-2 — These documents exist, and nothing else.** Anything not on the list needs a reason.

| Doc | Length | Job |
|---|---|---|
| `CLAUDE.md` | 1 page | how to work here: read order, precedence, citations |
| `docs/GOALS.md` | 1 page | goals, non-goals, invariants, what 1.0 is. Authoritative on scope |
| `docs/rules/` | 1–2 pages each | code (RCD), testing (RT), docs (RD), git (RG) |
| `docs/rules/packages/` | ~½ page each | rules binding inside named packages only (RPG-\*) |
| `docs/plan/` | brief, task-shaped | what we do next; its own rules are RPL |
| `docs/dev/` | 1–3 pages each | **the design** — how each part is built and why. Numbered `00`–`20` in reading order; see RD-8 |
| `docs/research/` | as long as needed | what is true about EVOK and the hardware |
| `docs/COMPATIBILITY.md` | as long as needed | **first-class deliverable** — see RD-3 |
| Root `README.md` | 1 page | what it is, install, minimal example, links |
| Per-package `README.md` | ~10 lines | purpose, and **what it must not depend on** |
| API reference | generated | typedoc from types + JSDoc. Never hand-written |
| `CHANGELOG.md` | generated | changesets. Never hand-written |

`docs/adr/` is **absent on purpose from 2026-08-16 to the re-lock.** The set lives in
`docs/research/to_revision/` while it is under revision, and comes back as its own directory — 1 page
each, dated, immutable once accepted — when it is settled again.

**RD-3 — `COMPATIBILITY.md` is a product feature.** It states **exactly where we behave differently
from EVOK 3.x**, including where we deliberately fix its bugs. Derived from
[research/01 §9](../research/01-evok-api-surface.md) and
[research/07](../research/07-client-compatibility.md); every entry is backed by a golden-transcript
test or marked untested. It is also a check on us: a divergence nobody wrote down is a divergence
nobody decided.

**RD-4 — JSDoc on every exported symbol.** One summary line, plus `@param`/`@returns` only where the
name isn't self-explanatory. Enforced — typedoc runs with `--validation.notDocumented` and CI fails
on undocumented exports. Not required on internal functions; an internal function that needs prose
to be understood should be renamed or split. Required regardless of visibility: any invariant a
reader could plausibly violate — "callers must hold the port mutex". Comments inside a function are
RCD-16's job, not this rule's.

**RD-5 — Docs ship in the same PR as the code.** Two explicit exceptions. Alpha/beta **smoothing
passes**: documentation written incrementally reads like sediment, so before `0.x-alpha` and
`0.x-beta` a scheduled task reads everything end to end and rewrites for coherence — that is when
structure, ordering and tone get fixed, not during feature work. And the **`docs-debt` label**: a PR
that knowingly leaves docs thin opens a `docs-debt` issue instead of blocking, and the smoothing
pass closes it.

**RD-6 — Prohibited.**

- Restating a type signature in prose.
- Documenting features that do not exist yet **as though they exist**. Aspirational docs are lies with
  a delay. Two exceptions, both of which must label what they are: `GOALS.md`, which might state post-1.0 direction as direction and never as behaviour; and `docs/dev/`, whose whole job is to describe a design before it is built (RD-8).
- Tutorials before `0.1.0`. The API will move.
- A `docs/` file that duplicates a research file — link it instead.
- Restating a rule that already has a number. Cite it.
- Emoji, decorative headings, and "Overview" sections that overview nothing.
- Marketing tone. This is an industrial control library; the audience wants precision.

**RD-7 — Research follows different rules.** `docs/research/` is not user documentation; it is our
knowledge base about EVOK and Unipi hardware — cited, evidence-marked, permanent. Completeness beats
brevity there, because its job is to stop us re-deriving hardware behaviour. Corrections are **dated
and marked**, never silent edits; see `research/02-hardware-model.md` §3.3 for the format.

**RD-8 — `docs/dev/` is design, and follows different rules.** It describes the system as designed, which means it legitimately runs ahead of the code — the RD-6 exception exists for exactly this. The precedence **ordering** is stated once, in [`docs/README.md`](docs/README.md) — do not restate it elsewhere.

- **No rule numbers.** How to cite one, and what to do with something that should be binding, is in
  the citation section of [`docs/README.md`](docs/README.md).
- **Every departure from research is marked and linked.** A dev doc may reject or narrow a research
  finding; one that does so silently is indistinguishable from one that got it wrong.
- **Unsettled means TBD, with the question written out.** An unmarked guess reads as a decision, and
  will be implemented as one.
- **Say what was rejected and why.** That is the part nobody can reconstruct later, and the reason
  these files exist rather than just the types.
- **When the code diverges, the dev doc is wrong** and is fixed in the PR that diverges — the same
  discipline as RPL-3. Design docs that describe a system nobody built are the failure mode this rule
  exists to prevent.
