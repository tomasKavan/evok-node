# Testing rules

Framework: **vitest** (workspace mode, one project per package).

The governing idea: we cannot buy hardware that reproduces our worst bug
([research/10 §4](../research/10-test-kit.md)), so **generated tests are the primary safeguard,
not a supplement**. They are load-bearing safety equipment.

## Tiers and triggers

| Tier | What | Where | Runs |
|---|---|---|---|
| **0 · unit** | pure logic, codecs, address maps, decoders | `src/**/*.test.ts` | every save (watch), every push |
| **0 · generated** | address tables for every model × section in the map corpus | `tests/generated/` | every push |
| **0 · simulator** | full stack against the in-process Modbus slave, incl. fault injection | `tests/integration/` | every push |
| **0 · golden** | replay of transcripts captured from stock EVOK 3.0.6 | `tests/golden/` | every push |
| **1 · hardware** | HIL against the rig | `tests/hardware/` | merge to `main`, or PR labelled `hardware-required` |
| **2 · soak** | days of polling with injected faults | `tests/soak/` | nightly and pre-release |
| **2 · acceptance** | Node-RED and Home Assistant, through nginx | `tests/acceptance/` | pre-release |

Tier 0 must finish in **under two minutes**. If it doesn't, agents stop running it and start
guessing. Protect that budget.

## Fixtures

```
fixtures/
  generated/    derived from docs/modbus-reg-map/ by a committed generator
  captured/     recorded from real hardware or stock EVOK. Immutable.
  handwritten/  small hand-built cases. Editable, must carry a comment saying why.
```

**Never edit `generated/` or `captured/`.** This is the single most important testing rule,
because the failure mode is specific to how agents work: an agent facing a failing assertion will
"fix" the expected value and produce a green build over a real bug.

Enforcement, all three layers:

- CI **regenerates** `fixtures/generated/` and fails on any diff. The fix is to change the
  generator, never the output.
- `fixtures/captured/` is in `CODEOWNERS` — changes need Tomas's explicit approval, and the PR
  must explain why reality changed.
- Both directories are `.prettierignore`d and marked read-only in the repo docs so an
  accidental format pass can't rewrite them.

Captured fixtures are irreplaceable: once stock EVOK is off the Patrons, they cannot be
re-recorded. Treat them like measurements, not like code.

## What must be tested, and how

**Address computation** — table-driven, generated, for every model and section in the corpus
*including the discontinued 28-RO and 30-DI Neurons*. Assert
`(model, section, kind, channel) → (register, bitOffset, coil)`. Plus a property test asserting
global uniqueness: no two circuits map to the same coil or (register, bit).

**Codecs** — golden tables per register type (`i16`, `u16`, `u32` CDAB word-swapped, `float32`,
raw 0..4000 AO counts, resistance scaling), including negatives, boundaries, and NaN → `null`.

**Transport** — a property test driving the transaction id across the `0xFFFF → 0` boundary over
≥200 000 transactions, asserting every response matches its own request. Plus explicit tests for
each failure the fault-injection layer can produce, and specifically the
**stale-frame-desync** case (timeout, late response, next request to the same unit and function
code — the response must be rejected, never returned as the new answer).

**Every fault has a named assertion about observable API behaviour** — "device marked offline",
"error returned with kind `bus_timeout`", "other devices unaffected". Not merely "does not
crash".

**Regression tests carry their origin.** A bug fix ships with a test named for the issue:
`it('rejects a stale frame after timeout (#regression-142)')`.

### Seed backlog: one test per upstream finding

[`research/04-known-bugs-and-lessons.md`](../research/04-known-bugs-and-lessons.md) documents
**29 real production failures** with their mechanisms, and the 40 design rules they imply. **Each
finding becomes a test before the corresponding feature is written.** That is a ready-made,
evidence-based regression suite for bugs we have not written yet, and it is the highest-value test
backlog available to us. Tag them `upstream-regression` so the set is greppable.

The only exemption is a finding dispositioned `construction` in
[`../plan/bug-dispositions.md`](../plan/bug-dispositions.md), where the mechanism is a type or an
exhaustive switch and a test would be asserting that the compiler works. **That is three findings out
of 29** — 1.3, 2.4 and 3.3. If you find yourself claiming a fourth, you are probably describing code
you intend to write correctly, which is what a test is for.

## Coverage

No global coverage gate — it produces tests written to hit lines. Instead, hard per-module
thresholds where a bug is expensive:

| Module | Branch coverage floor |
|---|---|
| `hw-definitions` address computation | **100%** |
| `modbus` framing, correlation, timing | **95%** |
| `protocol` codecs and schemas | **95%** |
| `core` device decode and lifecycle | 90% |
| everything else | none |

**Mutation testing (Stryker) on address computation and codecs**, weekly. Those two modules
cannot be validated against hardware for the cases that matter most, so we verify the *tests*
instead of trusting them.

## Style

- `describe` names the unit; `it` reads as a sentence: `it('returns device_offline when the slave
  does not answer')`.
- **No wall-clock sleeps.** Fake timers, or an injected clock. A test that sleeps is a test that
  will be flaky on the CI runner.
- Tests are independent and order-free. No shared mutable module state.
- No mocking of our own code in integration tests — use the simulator. Mocks assert what we
  believe; the simulator asserts what the maps say.
- Hardware tests call `rig reset` in `beforeEach` and must be idempotent and safely re-runnable
  after a crashed run.
- Hardware tests read the wiring from `rig.yaml`. A test that hardcodes a channel number is a
  bug.
