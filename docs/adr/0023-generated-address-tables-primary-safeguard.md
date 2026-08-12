# ADR-0023 — Generated address tables are the primary safeguard, not a supplement

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/10-test-kit.md §4, §Tier 0 · docs/research/09-test-hardware-coverage.md §2, §5 ·
  docs/research/06-register-maps.md · docs/plan/bug-dispositions.md finding 1.1 · RC-17, RC-18 · ADR-0020

## Context

The highest-severity bug class in the corpus is silently driving the wrong relay — upstream's M403
failure, which had two independent causes: a missing `/16` bank stride, and `RO`/`DO`/`LED` ignoring
`start_index` when a definition declares two feature blocks of the same type.

Verified against the Unipi e-shop, July 2026: M303, M403, L303 and L403 are **all** discontinued, and
**no currently purchasable Unipi device — controller or extension — has more than 16 channels of one
type in a single section.** The largest extension that has ever existed is the xS11 at 12 DI / 13 RO,
and Unipi published no successor to the high-density models. So the bank-stride half of the bug class
can never be reproduced on hardware we can buy
([research/10 §4](../research/10-test-kit.md)).

## Decision

**Cover it by generation, not by hardware.** Address tables asserting
`(model, section, kind, channel) → (register, bitOffset, coil)` are generated from the register-map CSV
corpus for **every model in it, including the discontinued 28-RO and 30-DI Neurons** — still in the
field, and exactly the units that stress the bank arithmetic — and the generator is re-run in CI so a
diff fails. Those tables are the primary safeguard; hardware tests confirm the channels we happen to
own.

Two compensating controls sit under it, both already rules and cited rather than restated: the one
audited address function holding the stride and the mask in exactly one place (RC-17), and
fatal-on-duplicate-registration, which turns a silent wrong-relay actuation into a refusal to start
(RC-18, in both of the places ADR-0008 puts it).

**The half that *is* reproducible is tested on hardware we own.** On the L527's section 3, a
deliberately split RO definition — two blocks of 7 with `start_index` — asserted through the RO→DI
loopback, so the rig observes which relay actually closed rather than what the API claims (ADR-0022).
That is finding 1.1's `test` disposition; the stock-EVOK mis-registration baseline for it is a
capture-trip item, since it needs EVOK still installed.

## Consequences

Makes easy: coverage of models we will never own, which is most of the supported set (ADR-0020); and a
Neuron purchase decided by platform behaviour rather than channel count — research/09 §5 recommends an
**L203** on those grounds, since no purchasable unit would test the arithmetic anyway.

Makes hard: **the corpus becomes ground truth.** A wrong CSV yields a wrong table with a confident
test behind it. Mitigations: the Axon CSVs stay as free cross-check data for the Neuron register model
(ADR-0020), the tables are hand-checked against the models we can measure, and generated fixtures are
read-only with a drift check (RT-1). It also makes the generator N1 work that gates every driver —
which is why N1 sits ahead of all of them, being the only substrate a driver can be tested against.

**Recorded as a permanent gap, not a temporary one.** GOALS' measurable definition of done allows a fix
to be marked *unverifiable*, naming the hardware we do not have. This is that case, and the naming is
the honesty requirement.

**Rejected: commissioning a 28-RO section through Unipi's custom-manufacturing programme.** It needs a
direct quote, is not a catalogue part, and would verify one unit rather than the arithmetic that
generated it.

**Rejected: hand-written expected-value tables.** They drift from the maps silently, and they would
have to be written for the same 80-odd model×section combinations the generator covers — with the
transcription errors landing precisely where nobody can check them against hardware.

**Rejected: relying on RC-18's assertion alone.** It makes the bug loud rather than absent. A refusal
to start on a customer's box is a far better failure than a wrong relay, and a far worse one than a
table that catches it in CI.
