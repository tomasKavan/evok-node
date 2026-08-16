# 00 — Intro

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** orient someone who has never seen this repo — what evok-node is, what EVOK is, why we
replaced it rather than patched it, and how to read everything else here.

**Covers**

- What evok-node is: a Node/TypeScript drop-in replacement for EVOK 3.x on Unipi hardware. **The
  interface is inherited; the design is not.**
- What EVOK is and where it sits in Unipi's stack. What "drop-in" promises, and where the promise
  stops — pointing at `COMPATIBILITY.md` (RD-3) as the enumerated answer.
- Why replace rather than fork and patch. One paragraph, citing research/04 and research/14 rather
  than restating them.
- How this documentation set works: `GOALS.md` / `rules/` / `dev/` / `research/` / `plan/` — what each
  answers and which wins. Brief, because [`CLAUDE.md`](../../CLAUDE.md) is the normative copy; link,
  do not duplicate (RD-6).
- **The ADR boundary.** Once `dev/` carries the design and the why, what is an ADR still for? This
  file is where that line gets drawn, and it has to be drawn before the set is re-locked.
- Reading paths: new contributor · writing a driver · writing an API · fixing a compat bug.

**Inputs:** [`GOALS.md`](../GOALS.md) · research/01 · research/04 · research/14 ·
[`CLAUDE.md`](../../CLAUDE.md)

**Open:** whether ADRs come back at all. If `dev/` records the reasoning, a separate immutable set may
be redundant rather than complementary. M3 decides.
