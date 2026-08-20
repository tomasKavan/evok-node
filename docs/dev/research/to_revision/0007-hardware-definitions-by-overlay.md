# ADR-0007 — Hardware definitions are extended by overlay; the OS image is read-only

- **Status:** Proposal, **not in force** — the set was dissolved 2026-08-18, see [README](README.md). Was: Superseded by 0014.
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §8.5, §2.6, §7.1 ·
  docs/research/06-register-maps.md §2.7 · docs/GOALS.md G-5 · ADR-0006, ADR-0008

## Context

We need fields EVOK's hardware-definition format does not have: per-channel mode sets, per-model mode
enums, unit-0 devices, an expected DI/DO/AI/AO census to cross-check against registers 1001/1002,
bank-stride hints, per-feature `eventable`, and conversion-time hints for resistance AI. Edge as a
fast follow (ADR-0008) makes them due **now**, before the format ships, or the first minor release
after 1.0 breaks it. Meanwhile `/etc/evok/hw_definitions/` belongs to the OS image and to EVOK, and we
read it in place (G-5).

## Decision

**Three layers, merged base → overlay → site**, per research/05 §8.5:

```
base      /etc/evok/hw_definitions/*.yaml     OS image — read-only, verbatim, never written
overlay   <pkg>/definitions/overlays/*.yaml   ships with evok-node, versioned with it
site      /etc/evok-node/overlays/*.yaml      the operator's own, survives our upgrades
```

Keyed by model name, so one overlay file touches one model. Overlays are **additive and corrective,
never a full redefinition**, and may correct a wrong field in a stock definition. They carry
`definitionVersion` and `appliesTo`, so an overlay written against a different stock definition is
refused rather than mis-merged. Every merged field records its provenance, so
`evok-node check-definitions` can print which layer a value came from.

Two asymmetries that are the decision, not detail:

- **The base layer alone is always sufficient** to run in EVOK-equivalent mode. A missing overlay
  degrades to exactly what EVOK does, logged at info. No overlay is ever *required*.
- **Unknown fields in a stock definition are a warning; unknown fields in ours are an error.** Unipi
  will add fields to theirs. Ours are ours.

For a model with no stock definition at all, an overlay may be a complete definition — same format,
same loader, nothing to merge onto. Merging is a pure function in `hw-definitions`; which component
calls it is the layering table's business, not this ADR's.

## Consequences

Makes easy: Edge's requirements later with no format break; correcting a wrong stock field without
touching a file `apt` owns; a definition linter that can explain itself. Merged definitions are frozen
per load, not per process (G-5, RC-4).

Makes hard: three-layer precedence is a real merge with real tests, and provenance-per-field is more
than a deep merge. `appliesTo` also means a stock definition that changes under us causes a **refusal
to apply** an overlay — noisier than silently proceeding, which is the point, but a support call we
have chosen to receive.

**Rejected:**

- **Editing the OS image's definitions in place, or shipping replacements.** An `apt` upgrade of the
  package owning those files overwrites or conflicts with ours, and it breaks the promise that
  `/etc/evok` is left pristine (ADR-0006, GOALS §The drop-in guarantee).
- **Our own format with a converter from EVOK's** — it doubles the ground truth and loses "the base
  layer alone runs", which is what makes a model we have never seen work at EVOK parity on day one.
- **Requiring an overlay per supported model** — any model without one becomes unsupported, the exact
  opposite of the compatibility guarantee.
- **Treating an unknown field in a stock definition as fatal** — attractive for strictness, and it
  means the next field Unipi adds takes the daemon down on every unit that upgrades.
