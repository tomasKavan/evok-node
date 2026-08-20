# ADR-0004 — Single-threaded, single event loop; not `worker_threads`

- **Status:** Proposal, **not in force** — the set was dissolved 2026-08-18, see [README](README.md). Was: Accepted.
- **Date:** 2026-08-12
- **Refs:** docs/research/12-modularisation.md · docs/research/08-latency-and-scan-budget.md ·
  docs/research/09-test-hardware-coverage.md · ADR-0001

## Context

ADR-0001 puts several drivers and several APIs in one process. The obvious next question is whether
each should get its own thread, and the obvious answer — "isolation is good" — is wrong here in a way
worth recording, because an agent reasoning from first principles will re-derive it.

## Decision

**One process, one event loop, for 1.0.** No `worker_threads`.

The arguments that do not survive scrutiny for this workload:

- **CPU isolation.** Nothing is compute-bound. CRC-16 over 250-byte frames, value codecs and small
  parses are microseconds. Address-table generation is startup-only and then frozen (RC-4). WebSocket
  fan-out serialises once and sends one buffer to N clients. A bulk query over 200 endpoints is a
  memory read plus a serialise — order 100–200 µs, against clients polling at a few Hz.
- **Memory isolation.** Same process, same RSS ceiling. Buys nothing.
- **Crash isolation.** Real, but nearly worthless given RC-6: if `throw` means programmer error,
  restarting the thread carrying the bug loops.

The one argument that survives is **timer fidelity** — Node timers are event-loop-bound, so API work
delays the next scheduled bus frame. Against research/09's 16 ms RS-485 inter-frame measurement that
is a real mechanism, but the numbers above make it small, and RC-27 plus per-driver deadlines
decouple the query path from the scan loop by construction. Whether residual skew matters is an
**empirical question for the N10 soak**, not a design input.

If measurement ever justifies threads, the shape is **not** one per driver. It is a two-way split
along the criticality line: one thread owning all bus I/O and scan timing, the main thread serving
every API.

## Consequences

Makes easy: debugging, profiling, stack traces, and a solo reviewer's ability to follow a request.
Deadline-driven scheduling with drift compensation — which matters far more to bus timing than thread
topology — stays the thing to get right.

Makes hard: a driver that stalls the loop synchronously stalls everything. That is a bug; RC-14 plus
`scan_frequency` validation are the fix, and finding 4.5 (`scan_frequency: 0` yielding a 10 kHz loop)
is the upstream instance.

**The option stays open, and cheaply.** ADR-0001's serialisable envelopes are exactly
`structuredClone`'s contract, so in-process, worker and out-of-process remain deployment choices —
a side effect of a decision taken for its own reasons, not a reason to keep the codec.

**Now owed:** if a bus thread is ever wanted, first check that `serialport` is context-aware NAPI. A
native addon that cannot open a port from a worker closes the question before it is asked. Twenty
minutes, worth doing before anyone plans on it.

**Rejected:**

- **Out-of-process components for 1.0** — process isolation only pays off alongside supervision,
  restart, state resync and write arbitration. It becomes necessary when plugins run untrusted code
  (G-6), which is post-1.0.
- **Memory footprint as the reason to avoid separate processes.** Node's ~50 MB baseline makes three
  or four processes survivable on a Patron. Recording the weak argument as weak keeps it from being
  cited later.
