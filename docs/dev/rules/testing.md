# Testing rules

Binding. Cite as **RT-N**. Framework: **vitest**, workspace mode, one project per package.

We cannot buy hardware that reproduces our worst bug ([research/10 §4](../research/10-test-kit.md)),
so **generated tests are the primary safeguard, not a supplement**. They are safety equipment.

## Fixtures

```
fixtures/
  generated/    derived from docs/modbus-reg-map/ by a committed generator
  captured/     recorded from real hardware or stock EVOK. Immutable.
  handwritten/  small hand-built cases. Editable, must say why in a comment.
```

**RT-1 — Never edit `generated/` or `captured/`.** The most important rule here, because the failure
mode is specific to how agents work: faced with a failing assertion, an agent edits the expected
value and produces a green build over a real bug. If a test fails against a fixture, the code is
wrong.

Enforced three ways: CI regenerates `fixtures/generated/` and fails on any diff (fix the generator,
never the output); `fixtures/captured/` is in `CODEOWNERS`, so changes need Tomas's approval and a PR
explaining why reality changed; both directories are `.prettierignore`d so a stray format pass cannot
rewrite them.

Captured fixtures are irreplaceable — once stock EVOK is off the Patrons they cannot be re-recorded.
Treat them as measurements, not code.

## Tiers

| Tier | What | Where | Runs |
|---|---|---|---|
| **0 · unit** | pure logic, codecs, address maps, decoders | `src/**/*.test.ts` | every save, every push |
| **0 · generated** | address tables for every model × section in the map corpus | `tests/generated/` | every push |
| **0 · simulator** | full stack against the in-process Modbus slave, with fault injection | `tests/integration/` | every push |
| **0 · golden** | replay of transcripts captured from stock EVOK 3.0.6 | `tests/golden/` | every push |
| **1 · hardware** | against the rig | `tests/hardware/` | merge to `main`, or PR labelled `hardware-required` |
| **2 · soak** | days of polling with injected faults | `tests/soak/` | nightly, pre-release |
| **2 · acceptance** | Node-RED and Home Assistant, through nginx | `tests/acceptance/` | pre-release |

**RT-2 — Tier 0 finishes in under two minutes.** Past that, agents stop running it and start
guessing. Protect the budget.

## What must be tested

**RT-3 — Address computation, table-driven and generated,** for every model and section in the
corpus *including the discontinued 28-RO and 30-DI Neurons*. Assert
`(model, section, kind, channel) → (register, bitOffset, coil)`, plus a property test for global
uniqueness: no two circuits on the same coil or (register, bit). This is the test half of RPG-DRV-1
and RPG-DRV-3. Branch coverage floor: **100%**.

**RT-4 — Codecs, golden tables per register type** — `i16`, `u16`, `u32` CDAB word-swapped,
`float32`, raw 0..4000 AO counts, resistance scaling — including negatives, boundaries, and
NaN → `null`.

**RT-5 — Transport, a property test across the transaction-id wrap** (`0xFFFF → 0`, ≥200 000
transactions), asserting every response matches its own request. Plus one test per injectable fault,
and specifically **stale-frame desync**: timeout, late response, next request to the same unit and
function code — the late response must be rejected, never returned as the new answer.

**RT-6 — Every fault has a named assertion about observable API behaviour.** "Device marked
offline", "error returned with kind `bus_timeout`", "other devices unaffected" — never merely "does
not crash".

**RT-7 — A regression test names its origin.**
`it('rejects a stale frame after timeout (#regression-142)')`.

**RT-8 — One test per upstream finding, written before the feature.**
[research/04](../research/04-known-bugs-and-lessons.md) documents 29 real production failures with
their mechanisms and the 40 design rules they imply — a ready-made regression suite for bugs we have
not written yet, and the highest-value test backlog we have. Tag them `upstream-regression`.

The only exemption is a finding dispositioned `construction` in
[`../research/14-bug-dispositions.md`](../research/14-bug-dispositions.md), where the mechanism is a type or an
exhaustive switch and the test would be asserting that the compiler works. **That is three findings
out of 29** — 1.3, 2.4 and 3.3. A claimed fourth is probably code you intend to write correctly,
which is what a test is for.

## Instruments

**RT-15 — A test instrument shares no code with the path it measures.** Enforced from the layering
table in `.dependency-cruiser.cjs`, as `layer-simulator`, `layer-rig` and `rig-no-modbus-client`:

- **`rig` imports nothing of ours at all.**
- **`simulator` may import `messaging` and `hw-definitions`, and never `modbus`.** It implements its own
  slave-side CRC-16 and PDU framing.

The failure this prevents is silent and specific: a symmetric bug in shared code — a byte order, a CRC
seed, a length-field off-by-one — **cancels out**. Instrument and subject agree, the suite is green, and
the wrongness surfaces only against real hardware, which for most of our model coverage is never. The
accepted cost is CRC-16 and PDU framing implemented twice, forever, in exchange for the simulator being
able to disagree with us — and a framer whose purpose is never to emit a bad CRC cannot be asked to emit
one, which RT-5 requires it to do.

**The two allowed imports are deliberate, and one of them is a residual risk.** `messaging` is the
internal contract, not a measurement path. `hw-definitions` carries the generated address tables, and a
simulator addressed from the same table as the subject *can* cancel an error in that table — the exact
mechanism this rule exists to break. It is allowed anyway because the alternative is a second address
derivation, which is a worse thing to get wrong. What closes the gap is that the tables are generated
from [`docs/modbus-reg-map/`](../modbus-reg-map/README.md) and re-generated in CI with a diff gate
(RT-1, RT-3), so their correctness is asserted against ground truth rather than against agreement
between the two sides.

Beyond those two, the sides may share **data** — codec golden vectors, captured transcripts — but never
code. A fixture is a measurement both sides are checked against; that is the opposite of a shared
implementation, and it is what makes a symmetric bug detectable.

**Owed:** a differential test asserting the two framers agree on valid frames cannot live in either
package, since both directions of that import are forbidden. A neutral location is decided when the
simulator lands. Until then both framers are checked against known-answer CRC vectors from the Modbus
specification and against captured transcripts — byte-level agreement with reality rather than with each
other.

The `rig` has a second reason: a wedged evok-node must not be able to disable the mechanism meant to
recover it. So all switching is the test host's own RO/DO and never a DUT's, and loopbacks are
cross-unit — each direction measured by an independent device, because a DUT's own AO→AI loop can cancel
a shared codec error and pass. Design detail is `dev/19` and `dev/20`.

## Coverage

**RT-9 — No global coverage gate**, because it produces tests written to hit lines. Hard per-module
floors instead, where a bug is expensive:

| Module | Branch coverage floor |
|---|---|
| `hw-definitions` address computation | **100%** |
| `modbus` framing, correlation, timing | **95%** |
| `protocol` codecs and schemas | **95%** |
| `core` device decode and lifecycle | 90% |
| everything else | none |

**RT-10 — Mutation testing (Stryker) on address computation and codecs, weekly.** Those two cannot
be checked against hardware for the cases that matter most, so we verify the *tests* rather than
trust them.

## Style

**RT-11 — No wall-clock sleeps.** Fake timers or an injected clock. A test that sleeps is a test that
goes flaky on the CI runner.

**RT-12 — Tests are independent and order-free.** No shared mutable module state.

**RT-13 — No mocking our own code in integration tests** — use the simulator. Mocks assert what we
believe; the simulator asserts what the maps say.

**RT-14 — Hardware tests read the wiring from `rig.yaml`,** call `rig reset` in `beforeEach`, and are
safely re-runnable after a crashed run. A test that hardcodes a channel number is a bug.

`describe` names the unit; `it` reads as a sentence:
`it('returns device_offline when the slave does not answer')`.
