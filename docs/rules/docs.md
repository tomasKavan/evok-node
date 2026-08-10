# Documentation rules

**Brevity is the rule, not a preference.** Long documentation goes stale, and stale
documentation is worse than none because it is believed. If you can delete a sentence and lose
nothing, delete it.

## The one principle

**Document the non-obvious *why*. Never the *what*.** The what is in the code and the types.

Do not write:

> `getRegister(count, index)` — gets `count` registers starting at `index`.

Do write:

> Reads from the cache snapshot, not the bus. Returns `null` if the block has never been read —
> "no value yet" and "value 0" are different, and clients depend on the distinction.

## What must exist, and nothing else

| Doc | Length | Owner |
|---|---|---|
| `docs/GOALS.md` | 1 page | goals, non-goals, invariants, what 1.0 is. Authoritative on scope |
| Root `README.md` | 1 page | what it is, install, minimal example, link to the rest |
| Per-package `README.md` | ~10 lines | purpose, and **what it must not depend on** |
| `docs/adr/` | 1 page each | decisions, dated, immutable once accepted |
| `docs/plan/` | see [plan rules](../plan/README.md) | what we do next |
| `docs/COMPATIBILITY.md` | as long as needed | **first-class deliverable** — see below |
| API reference | generated | typedoc from types + JSDoc. Never hand-written |
| `CHANGELOG.md` | generated | changesets. Never hand-written |

Anything not on this list needs a reason to exist.

## `COMPATIBILITY.md` is a product feature

This is the document our users actually need: **exactly where we behave differently from EVOK
3.x**, and where we deliberately fix its bugs. It is derived from
[research/01 §9](../research/01-evok-api-surface.md) and
[research/07](../research/07-client-compatibility.md), and every entry must be backed by a
golden-transcript test or marked as untested.

It is also a check on ourselves: a divergence nobody wrote down is a divergence nobody decided.

## JSDoc

Required on every **exported** symbol: one summary line, plus `@param`/`@returns` only where the
name isn't self-explanatory. Enforced — typedoc runs with `--validation.notDocumented` and CI
fails on undocumented exports.

Not required on internal functions. If an internal function needs prose to be understood, rename
it or split it.

Required regardless of visibility: a comment on any **invariant a reader could plausibly
violate** ("callers must hold the port mutex"), and on any magic number with its source.

## Write as you implement

Documentation ships in the **same PR** as the code. The PR checklist has a docs item, and it is
not a formality — a PR that adds an exported symbol without a JSDoc summary fails CI.

Two exceptions, both explicit:

- **Alpha/beta smoothing passes.** Documentation written incrementally reads like sediment.
  Before `0.x-alpha` and before `0.x-beta` there is a scheduled milestone task to read everything
  end to end and rewrite for coherence. That is when structure, ordering and tone get fixed —
  not during feature work.
- **`docs-debt` label.** If a PR knowingly leaves documentation thin, it opens a `docs-debt`
  issue rather than blocking. The smoothing pass closes them.

## Prohibited

- Restating a type signature in prose.
- Documenting features that do not exist yet. Aspirational docs are lies with a delay. The one
  exception is `GOALS.md`, whose job is to state intent — and which must therefore label
  post-1.0 direction as direction, never as behaviour.
- Tutorials before `0.1.0`. The API will move.
- A `docs/` file that duplicates a research file — link it instead.
- Emoji, decorative headings, and "Overview" sections that overview nothing.
- Marketing tone. This is an industrial control library; the audience wants precision.

## Research vs docs

`docs/research/` is **not** user documentation. It is our knowledge base about EVOK and Unipi
hardware: long, cited, evidence-marked, and permanent. It follows different rules — completeness
beats brevity there, because its job is to stop us re-deriving hardware behaviour.

Corrections to research are **dated and marked**, never silent edits. See the correction note in
`research/02-hardware-model.md` §3.3 for the format.
