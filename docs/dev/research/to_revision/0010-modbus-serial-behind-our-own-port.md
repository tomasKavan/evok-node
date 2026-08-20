# ADR-0010 — `modbus-serial` behind our own port, with a supervising wrapper

- **Status:** Proposal, **not in force** — the set was dissolved 2026-08-18, see [README](README.md). Was: Accepted.
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §8.4, §2.3 ·
  docs/research/04-known-bugs-and-lessons.md finding 1.2 · RC-6, RC-9, RC-14, RC-22 ·
  ADR-0001, ADR-0011

## Context

Finding 1.2 — pymodbus's transaction-id overflow, which returns one slave's response as another's — was
the reason to consider writing our own framer. The July 2026 library survey removed that reason: **no JS
library has that bug.** It found a different defect of equal severity in every mature one.

> **Stale-frame desync after a timeout.** The RX buffer is never flushed. Request A times out, A's
> response arrives late, request B is written, and the framer matches A's stale frame — valid CRC, right
> unit id, right function code, right length — returning A's data as B's. For a polling loop hitting the
> same registers that is silent stale data, not an error.

Verified present in `modbus-serial` and `jsmodbus@4.0.10`. Survey and evidence: research/05 §8.4.

## Decision

**`modbus-serial` as the PDU/transport layer, behind our own port interface, with a subclassed
`RTUBufferedPort`.** Modbus TCP uses the library as-is: MBAP framing is length-prefixed and unambiguous,
and 8.0.25 fixed split-segment handling.

The wrapper's **eight obligations** — per-port mutex, RX flush before every request, strict unit-id and
function-code gate, t3.5 pacing, our own outer deadline, our own reconnect supervisor, retry with
backoff on idempotent reads only, and a cap on outstanding TCP requests — are enumerated with the
upstream issue behind each in research/05 §8.4. **All load-bearing, none optional.** That list is the
specification and is not repeated here.

Why `modbus-serial` and not `jsmodbus`, which has the better architecture: it is the only mature option
that is simultaneously maintained (8.0.25, 2026-03-20), on current `serialport ^13`, in real field use,
and validating unit id, function code, expected length *and* CRC after matching. `jsmodbus` has
published nothing to npm since 2023-12-21 with a 20-month-unanswered release request, so adopting it
means vendoring a dev branch — at which point we own the code anyway.

**One obligation is now partly structural.** Under ADR-0001 a driver owns exactly one transport
endpoint, so a bus has one master in-process by construction and the per-port mutex is that driver's
concern alone rather than a queue shared between components. It still has to exist:
`modbus-serial`'s `_unitID`, `_port._id` and `_port._cmd` are single mutable slots that any overlap
destroys, including a driver's own concurrent requests.

## Consequences

Makes easy: eight known defects fixed once, in one package that only drivers import; a replaceable
dependency, since the port interface is the seam RC-22 asks for; and library errors mapped onto our
error kinds once, in the adapter (RC-9).

Makes hard: we own a subclass of a library's internal port class. It is the extension point the library
documents — ports are duck-typed on `open/close/write/isOpen` plus the transaction-id accessors — but it
is still internal surface, so a minor upgrade can break it. The dependency is pinned deliberately and
the wrapper needs a conformance suite against `simulator`, whose independent framer (ADR-0011) is what
makes that suite worth running.

**Rejected:**

- **Our own framer** over `serialport`/`net`, the leaning in research/05 §2.3. The correlation bug that
  justified it does not exist in JS, and RC-22 prefers a maintained library behind an interface. We
  write slave-side framing anyway for the simulator, so the knowledge is not absent from the project —
  it is deliberately not on the master path.
- **`njs-modbus`,** which has the strongest discipline of any library (flush before every request, and
  the only t3.5 implementation). It is **BUSL-1.1, not open source.** Read its `RtuProtocolLayer` as a
  design reference for the framing FSM; **do not copy it.**
- **A private fork of `modbus-serial`,** which is what `node-red-contrib-modbus` does. A dependency
  fetched by URL is not one we can patch, audit or upgrade on our own schedule, and the subclass gets
  the same fixes inside our own tree.
