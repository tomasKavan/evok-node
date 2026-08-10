# Bug dispositions

**Updated:** 2026-08-10 · **Closed:** 0 of 29

Every known EVOK finding and what we did about it. Closing this file is half the definition of 1.0
([`../GOALS.md`](../GOALS.md)); the other half is compatibility.

Findings and their IDs come from [`../research/04-known-bugs-and-lessons.md`](../research/04-known-bugs-and-lessons.md),
which has the evidence — commit hashes, issue numbers, `[V-src]` markers — and the 40 design rules
these imply. The ~90 raw findings sit behind it in
[`../research/appendix/raw-bug-archaeology.md`](../research/appendix/raw-bug-archaeology.md). **This
file adds no evidence and repeats no detail. It tracks outcomes only.**

## Vocabulary

One disposition per finding, optionally qualified by `unverifiable`.

| Disposition | Means |
|---|---|
| **construction** | The design makes it unrepresentable. Evidence is the type, the schema or the load-time validation — not a test that the bug is absent. |
| **test** | Fixed, with a regression test that fails against the old behaviour. |
| **compat-flagged** | Fixed, with opt-in bug-compatible behaviour behind a `compat` flag, because a working client could depend on the old shape. |
| **won't fix** | With a reason. |
| **+ unverifiable** | A *qualifier*, not a disposition of its own: fixed and tested as far as we can, with a residual gap needing hardware that **does not exist or we will not own** — not hardware merely not yet built or wired. Names the gap in the row. Two rows carry it: 1.1 and 4.3. |

**`construction` is rarer than it looks, and only three rows qualify: 1.3, 2.4 and 3.3.** The bar is
that the *mechanism* is a type, an exhaustive switch or a schema — not that a correct implementation
would avoid the bug. Normalising a library's error taxonomy (3.1), a codec (3.8), a flush policy
(3.9) and a deadline (4.4) are all our own runtime code, and code needs a test. This was corrected on
2026-08-10 after an initial pass marked nine rows `construction`; the drafting error was treating
"the design prevents it" as equivalent to "the design intends to prevent it".

## Rules

1. **A PR that closes a finding fills in its `Closed by` cell in the same PR.** Same rule as
   `STATUS.md`; same reason.
2. **`construction` is a claim about the design, and reviewers check it.** "The types prevent it" is
   only true if a reviewer can see how. If it needs a test to be sure, it is `test`.
3. **`unverifiable` needs the gap named** in the row, and the gap must match a line in `STATUS.md` —
   either its blocked table (waiting on hardware we will have) or its known-permanent-gaps section
   (hardware that does not exist). "The rig is not built yet" is neither; that is a schedule, and the
   row stays plain `test`.
4. Intended dispositions below are **predictions, not commitments**. If implementation shows a
   different disposition is right, change it here in that PR with a one-line note.

---

## Tier 1 — actuates the wrong physical output

| # | Finding | Intended | Milestone | Closed by |
|---|---|---|---|---|
| 1.1 | >16-channel addressing drives the wrong relay | test + **unverifiable** — no device has >16 channels of one type in a section, so the bank-stride half cannot be reproduced | M1, M6 | |
| 1.2 | Modbus TID overflow mismatches responses | test | M2 | |
| 1.3 | Register cache shared between slaves | construction | M3 | |
| 1.4 | Torn 32-bit counters across register blocks | test | M3 | |

**1.1 is the project's defining gap**, and the gap is narrower than it is usually stated. No
purchasable Unipi device has more than 16 channels of one type **in a single section**
([research/10 §4](../research/10-test-kit.md)), so the *missing bank stride* half of the M403 failure
cannot be reproduced. The other half — `RO`/`DO`/`LED` ignoring `start_index` when a definition
declares two feature blocks of the same type — **is** testable on hardware we have: a deliberately
split definition on the L527's section 3, verified through the RO→DI loopback so the rig sees which
relay actually closed. Compensating controls for the untestable half are the generated address tables
and the fatal-on-duplicate-registration assertion.

## Tier 2 — the service stops working and needs a restart

| # | Finding | Intended | Milestone | Closed by |
|---|---|---|---|---|
| 2.1 | Discovery is a one-shot startup step | test | M5 | |
| 2.2 | One unreachable slave blocks every bus and client; backlog replays stale commands | test | M2, M3 | |
| 2.3 | Unbounded WebSocket send buffering | test | M4 | |
| 2.4 | Closing the last WebSocket can stop polling | construction | M3 | |
| 2.5 | One missing 1-Wire sensor froze all sensors | test | M3 | |
| 2.6 | A failing register block discards the whole scan pass | test | M3 | |
| 2.7 | Crash-loop on config errors | test | M5 | |

2.2 has two halves and both must close: bus isolation, and command expiry so a recovered bus cannot
replay a 40-second-old "close relay". 2.4 is `construction` because polling becomes a property of the
device, never of who is listening — there is no code path from a socket closing to a scan stopping.

## Tier 3 — silently wrong or unusable API behaviour

| # | Finding | Intended | Milestone | Closed by |
|---|---|---|---|---|
| 3.1 | Failed writes returned `success: true` | test | M2 | |
| 3.2 | Write responses return the pre-write value | test | M4 | |
| 3.3 | `ds_mode` never returns to `Simple` | construction | M3 | |
| 3.4 | Payload shape has never been invariant | compat-flagged | M4 | |
| 3.5 | Alt-name filters silently match nothing | test | M4 | |
| 3.6 | Webhooks never fire for 1-Wire | test | M4 | |
| 3.7 | No keepalive, close reasons or subscription echo | test | M4 | |
| 3.8 | Value-conversion bug tail, incl. NaN as invalid JSON | test | M1 | |
| 3.9 | Aliases are not durably written | test | M3 | |
| 3.10 | Bulk `group_queries` / `group_assignments` broken | test | M4 | |

Notes on the ones that are not straightforward:

- **3.2** changes a response shape, so check it against the 22 requirements in
  [research/07](../research/07-client-compatibility.md) before assuming no flag is needed. May
  become `compat-flagged`.
- **3.4** is `compat-flagged`, not `construction`: the always-array envelope is enforced by the type
  system, but `wsAlwaysArray` (research/07 §7) can reproduce the old inconsistency on request, and a
  behaviour a flag can reach is by definition representable. Note research/07's instruction that the
  flag must **default true** and exists only for A/B testing — no working client depends on the old
  shape; both known ones crash on it.
- **3.5** is a fix in two directions: the legacy alt names (`input`, `relay`) must *work*, since
  they are documented and the shipped default `webhook.device_mask` uses them — while genuinely
  unknown filter values must be rejected loudly. Rejecting the alt names would break EVOK's own
  default config.
- **3.9** is `test`, not `construction`. ADR-0005's ACID store removes the *truncation* half for
  free, but the flush policy is ours — research/04 rule 25 requires synchronous-on-change or a bounded
  documented window **plus flush-on-shutdown**, and only a test shows we did that.
- **3.8** is `test` because `rules/testing.md` already mandates golden tables per register type
  including negatives, boundaries and NaN→`null`. The type system stops `NaN` reaching the wire; the
  golden tables are what prove the conversions are right.

## Tier 4 — operability

| # | Finding | Intended | Milestone | Closed by |
|---|---|---|---|---|
| 4.1 | RS-485 timing was never modelled | test | M2 | |
| 4.2 | Backoff defeated by partial recovery | test | M2 | |
| 4.3 | A dead peer starved a healthy device's watchdog | test + **unverifiable** — the FW 6.26-vs-6.28 MWD behaviour fork needs two firmware versions on one section | M3 | |
| 4.4 | Timeouts and reconnect tuned by trial and error; unbounded busy-wait | test | M2 | |
| 4.5 | Idle CPU ~16.6 %; `scan_frequency: 0` yields a 10 kHz loop | test | M3, M6 | |
| 4.6 | Diagnosability was an afterthought | test | M5 | |
| 4.7 | Install-time nginx detection by trial and error | test | M6 | |
| 4.8 | Interlocks were left to clients | test | M3 | |

- **4.1** and **4.3** both need the rig, which is scheduled during M0–M2 — a schedule dependency, not
  an unverifiable gap, hence 4.1 is plain `test`. 4.1 additionally needs the RS-485 baud-encoding
  question in [research/05 §7.4](../research/05-evok-node-design-notes.md) answered on hardware, which
  the rig can answer. **4.3** keeps the qualifier for a different reason: the master-watchdog
  behaviour fork between firmware 6.26 and 6.28 ([research/09](../research/09-test-hardware-coverage.md))
  needs two firmware versions present at once, which our units cannot provide.
- **4.5** splits: rejecting `scan_frequency: 0` is a load-time validation closeable at M3; the idle
  CPU comparison against stock EVOK needs the M6 soak and the baseline measurements from the capture
  trip.
- **4.7** closes via ADR-0002's packaging decision and the Debian 12 + 13 install tests, not by
  fixing detection logic.
- **4.8** closes with declarative interlocks in the device layer — which are also the foundation the
  post-1.0 trigger engine builds on.

---

## Not findings

Recorded so nobody "fixes" them. From research/04 §Explicitly not established:

- **No *credible* evidence of a memory leak in EVOK.** Leak-like reports resolve to restart loops or
  the unbounded-queue mechanisms above — which are plausible leak paths, but no reporter observed RSS
  growth. Do not repeat the leak claim, and do not add a row for it.
- Issue #212's final resolution is unknown — the source page was truncated.
- A forum report of an hourly cron restart on a Neuron 203 + 2×xS30 + xS40 could not be located.
