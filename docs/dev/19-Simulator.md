# 19 — Simulator

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** simulating each component well enough that most tests need no hardware.

**Written alongside 01–18, not after them.** Start it as notes and finalise once the full picture
exists — its shape is a consequence of theirs, and writing it early would fix decisions the other
files have not made yet.

**Covers**

- **What is simulated:** Modbus slaves generated from the register-map corpus, RS-485 line behaviour,
  1-Wire buses, and stub drivers and APIs for testing the far side of the messaging boundary.
- **Fidelity policy.** Which real misbehaviours are reproduced deliberately — timeouts, partial
  frames, wrong values, slow units, units that vanish — and which are explicitly out of scope. A
  simulator that only does the happy path proves almost nothing.
- **Instrument independence:** it shares **no code** with the subject, including its own framer
  (ADR-0011). This looks like duplication, so the reason has to be written down where people will find
  it.
- **Generation from the corpus,** and drift detection when the corpus changes.
- **How tests drive it,** and — stated plainly — **what it cannot prove.** That list is 20's
  justification.

**Inputs:** research/09 · research/10 · ADR-0011, ADR-0012 (suspended)
