# 14 — Compat API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the EVOK 3.x surface as a **first-class deliverable** — the reason the project exists, not a
compatibility shim bolted to the side.

**Covers**

- **The premise.** Bug-for-bug is not the goal: we reproduce EVOK's *interface* and deliberately fix
  its defects, with every divergence enumerated in `COMPATIBILITY.md` (RD-3). Where compatibility and
  correctness genuinely conflict, this file states the tie-breaker.
- **Scope.** Understands the **onboard and extension drivers only**. Plugin devices are not projected
  here, and possibly not even their data types. Argue why that is a feature rather than a limitation.
- **The projection table:** derived from introspection, never hand-written. EVOK's naming, aliases and
  dev/circuit addressing fall out of it — show how.
- **At most one onboard driver; zero is legal.** Zero is the Gate, which serves an empty surface. EVOK
  itself degrades oddly here, so our behaviour is captured rather than inferred.
- **Legacy configuration:** which EVOK options we honour, which we accept and ignore, which we refuse
  — and the same three-way split for aliases.
- **Golden transcripts as the test method,** and what stays unverifiable until capture happens.

**Inputs:** research/01 · research/07 · research/14 · ADR-0009 (suspended) · `COMPATIBILITY.md` (RD-3)

**Open:** **blocked on golden-transcript capture** for the Gate's empty-surface shape and the
split-definition baseline. Time-sensitive and unrecoverable — see [`STATUS.md`](../plan/STATUS.md).
