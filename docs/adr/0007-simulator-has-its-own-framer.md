# ADR-0007 — The simulator does not depend on `modbus`

- **Status:** Accepted
- **Date:** 2026-08-10
- **Refs:** docs/research/10-test-kit.md §Tier 0 · RC-11 · docs/plan/STATUS.md open
  question 5a

## Context

T0.1 left `simulator → modbus` deliberately undeclared, because declaring it wrongly is what
`dependency-cruiser` then enforces. T0.3 has to encode one answer or the other.

The simulator is a Modbus **slave**; our `modbus` package is the **master** side, and it wraps
`modbus-serial` rather than framing frames itself (research/05 §8.4). So the shared surface is not
"a transport" — it is CRC-16 and PDU encode/decode, which both sides need in mirror image.

Two things decide it. RC-11 already forbids exactly this sharing for `rig`: the
instrument must not share code with what it measures, and for every test we can run without
hardware the simulator *is* the instrument. And research/10's tier-0 requirements are explicit that
the simulator must inject CRC errors, truncated frames, garbage bytes, late responses and t3.5
violations. A framer whose entire purpose is to never emit those cannot be asked to emit them; a
shared implementation would have to grow a "produce a wrong CRC" path, which is a defect-injection
switch inside production transport code.

The failure mode this prevents is specific: a symmetric bug in shared framing — a byte order, a CRC
seed, a length-field off-by-one — cancels out. Master and slave agree, every simulator test passes,
and the wrongness is discovered only against real hardware, which for most of our model coverage is
never.

## Decision

`simulator` never imports `@evok-node/modbus`, and implements its own slave-side CRC-16 and PDU
framing. Encoded as `layer-simulator` in `.dependency-cruiser.cjs`, generated from the layering
table there.

The two implementations may share **data** — generated address tables, codec golden vectors,
captured transcripts under `fixtures/` — but never code. A fixture is a measurement both sides are
checked against; that is the opposite of a shared implementation, and it is what makes a symmetric
bug detectable.

## Consequences

**The cost, plainly:** CRC-16/Modbus and PDU framing exist twice. That is on the order of 150 lines
duplicated, and it is real duplication, not incidental — the same spec clauses implemented twice, in
two packages, able to drift. A bug in the simulator's framer presents as a bug in ours, and costs an
agent a debugging session to attribute. We pay this on every change to framing, forever, in exchange
for the simulator being able to disagree with us.

Makes easy: protocol-level fault injection, which is most of what tier 0 is for; trusting a green
simulator suite, because the two sides were written independently; the future case of a second
transport, where the simulator does not have to follow.

Makes hard: nothing about the master path, and one thing about testing it — a differential test that
asserts the two framers agree on valid frames cannot live in either package, since both directions of
that import are forbidden. **Now owed:** a neutral location for cross-implementation tests, decided
when M1 lands the simulator. Until then both framers are checked against known-answer CRC vectors
from the Modbus specification and against the captured transcripts, which is byte-level agreement
with reality rather than with each other.

**Rejected:** sharing the framer and injecting faults by wrapping or monkey-patching it. This is the
cheaper option in lines of code and it is what most projects do. Rejected because it puts a
fault-injection seam in production transport code, and because the symmetric-bug failure above is
silent — the same reason `rig` is forbidden from sharing code under RC-11.

**Rejected:** a third package holding a shared CRC and framing primitive, depended on by both. It
looks like the DRY answer, but it reintroduces exactly the symmetric-bug cancellation the decision
exists to prevent, while adding a package. Worth reopening only if the duplication grows well beyond
framing.

This decision settles open question 5a. Question 5b — `inspector → client` — remains open, and
`.dependency-cruiser.cjs` deliberately does not rule on it.
