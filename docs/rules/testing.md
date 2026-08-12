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
uniqueness: no two circuits on the same coil or (register, bit). This is the test half of RC-17 and
RC-18. Branch coverage floor: **100%**.

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
[`../plan/bug-dispositions.md`](../plan/bug-dispositions.md), where the mechanism is a type or an
exhaustive switch and the test would be asserting that the compiler works. **That is three findings
out of 29** — 1.3, 2.4 and 3.3. A claimed fourth is probably code you intend to write correctly,
which is what a test is for.

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
