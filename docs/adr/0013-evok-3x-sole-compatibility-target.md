# ADR-0013 — EVOK 3.x is the sole compatibility target

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §7, §2.1 ·
  docs/research/01-evok-api-surface.md §9 · docs/research/07-client-compatibility.md §6 ·
  docs/GOALS.md G-3, §Non-goals

## Context

EVOK has a decade of history and two incompatible generations. Its v2 device names are still being
written into new clients — `unipi-mqtt-ng` was published in **February 2026** against v2 names and is
therefore completely broken on EVOK 3 — so "compatible with EVOK" is not one target. Upstream
declares v2→v3 migration unsupported. Separately, EVOK's own documentation and code disagree in
twelve places
([research/01 §9](../research/01-evok-api-surface.md)), so even within v3 there are two candidate
contracts.

## Decision

**The compatibility contract is stock EVOK 3.0.6 as deployed on Unipi OS**, cross-read against
upstream `main` at `47c95c8`. Nothing earlier is a target.

Where the documentation and the code disagree, **the code is the contract** — clients were written
against the running server, not against the docs. Where the code is outright broken (bulk `group_*`,
static 1-Wire sensors, RPC method signatures, `register` events, alt-name filters) we implement the
documented intent correctly and with no flag: no working client can depend on a `TypeError`.

The three clients that are broken against EVOK 3 *because* they use v2 names
([research/07 §6](../research/07-client-compatibility.md)) stay broken by default. Emitting v2
vocabulary is at most an opt-in per-connection mode (`emitLegacyDevNames`, ADR-0021), never a
default. **Alt-name acceptance on input is permanent** — that is EVOK 3 behaviour, not a v2
concession, and February 2026's client is the argument for keeping it forever.

## Consequences

Makes easy: a single oracle. Every compat claim is checkable against golden transcripts captured
from one stock 3.0.6 unit, which is what makes `COMPATIBILITY.md` a deliverable rather than a
narrative (RD-3). It also bounds the surface: `research/01` describes one server, not a family.

Makes hard: the oracle is perishable. A behaviour nobody captured before EVOK leaves those Patrons
cannot be recovered, which is why the capture trip is time-sensitive rather than merely scheduled.

**Rejected: bug-for-bug fidelity.** Already a non-goal in `GOALS.md`; recorded here because it is
the alternative a reader will reach for when a golden transcript and a fixed payload disagree. The
answer is the flag set (ADR-0021), which is closed, not a general policy of imitation.

**Rejected: emitting both vocabularies** so the three v2 clients work too. Requirements 6, 7 and 20
in research/07 are precise about which spelling goes in which direction — alt-names accepted on
input, canonical names emitted, with `dev:"temp"` the single exception. Emitting `relay` *and* `ro`,
or `relay_type` and `dev:"neuron"`, breaks every client that conforms to EVOK 3 in order to repair
three that conform to nothing current.

**Rejected: tracking upstream's `main` rather than a release.** Upstream moves rarely and the oracle
has to be a fixture. A moving target cannot be captured. We re-pin deliberately if 3.0.7 ships, as a
dated note here and a re-capture — not implicitly.
