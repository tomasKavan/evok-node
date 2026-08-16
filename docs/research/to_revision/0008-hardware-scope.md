# ADR-0008 — Hardware scope: Patron, Neuron, Unipi 1.1, Extensions, Gate; Edge as a fast follow; Axon dropped

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §8.3, §7.1 ·
  docs/research/09-test-hardware-coverage.md §5 · docs/GOALS.md §Non-goals · ADR-0007, ADR-0012

## Context

"Every model EVOK v3 supports" and "everything the register-map corpus covers" are **not the same
set**, and the project had been using them interchangeably. EVOK 3's README claims exactly *NEURON,
PATRON, GATE and Unipi 1.1 including Extension modules*. The corpus additionally holds 18 Axon models
and 4 Edge models — Axon discontinued, Edge the current flagship and claimed by EVOK nowhere.

## Decision

**1.0 supports Patron + Neuron + Unipi 1.1 + Extensions + Gate.** Gate falls out for free: it has no
local I/O, so EVOK on a Gate exists only to reach extensions.

**Edge is a fast follow after 1.0. Axon is dropped** — its map CSVs stay in
`docs/modbus-reg-map/axon/` as free cross-check data for the Neuron register model; no support is
claimed and no Axon hardware is needed. `Iris`, named in `evok/config.py:79` and in `unipi-tools`'
README but in no public product line, is disregarded.

**Two obligations land now rather than with the models,** because deferring either means a breaking
change in the first minor release after 1.0:

- The overlay format (ADR-0007) must already accommodate Edge — per-channel mode sets, per-model mode
  enums (4–20 mA, 90–2000 Ω against the PLC families' 0–20 mA and 0–1960 Ω), and unit-0 devices.
- Family forks are **capability flags derived from definition plus identity**, never model-name
  conditionals: `persistsConfig` (false on Unipi 1.1, whose configuration is not saved and must be
  reapplied on every power-on), `hasMasterWatchdog`, `serialConfigSurvivesSectionRestart`,
  `hasUnitZeroAggregate`, `aiAbstraction`, `hasBoardFirmware`. See research/05 §7.1.

## Consequences

Makes easy: a scope claim we can stand behind, because it is EVOK's own claim — which is what a
drop-in replacement's scope has to be. Gate also gives us the zero-local-I/O case, and that is a real
compat shape rather than an edge case: `api-compat` allows at most one onboard driver, and zero is the
Gate.

Makes hard: **two in-scope families have no hardware yet.** Neuron and Unipi 1.1 are map-driven and
simulator-verified until purchased (ADR-0012), and Unipi 1.1 is entirely unverified —
`unipi-one-modbus` on port 50200, no board firmware, no NV save, 18-bit AI. research/09 §5 puts a
Neuron **L203** and a Unipi 1.1 at purchase priorities 2 and 3 for that reason.

**Rejected:**

- **Edge inside 1.0** — structurally different (slot/card identity, unit-0 ULED, per-channel AI
  modes), and EVOK claims it nowhere, so it would add scope to the one thing 1.0 is defined as. Its
  maps being the best-documented in the corpus makes it tempting, not in scope.
- **Dropping Edge entirely** — its product page does list EVOK support and it is the current flagship.
  Being format-ready costs one design pass now; retrofitting a definition format costs a breaking
  release.
- **Supporting Axon because the maps are already there** — a claim of support is a claim to test, on
  hardware we will never buy for a discontinued line.
