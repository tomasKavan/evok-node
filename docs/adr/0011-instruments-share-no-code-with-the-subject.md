# ADR-0011 — Test instruments share no code with what they measure

- **Status:** Accepted
- **Date:** 2026-08-10
- **Refs:** docs/research/10-test-kit.md §Tier 0, §Tier 1 · RC-11 · docs/plan/STATUS.md open
  question 5 · ADR-0010

## Context

Two instruments measure our own code. `simulator` is a Modbus **slave** that stands in for hardware we
do not own; the `rig` is a second Patron M527 whose own I/O *is* the instrumentation — its RO/DO switch
extension power and cut RS-485 pairs, its DI observe DUT outputs, its AI/AO close analog loops
([research/10](../research/10-test-kit.md)). In both cases the cheap implementation is to reuse our
`modbus` package, or evok-node itself. Both are wrong for the same reason, and it only ever shows up as
a **passing** test.

The failure is specific: a symmetric bug in shared code — a byte order, a CRC seed, a length-field
off-by-one — **cancels out.** Instrument and subject agree, every test passes, and the wrongness is
discovered only against real hardware, which for most of our model coverage is never. For the rig there
is a second failure: a wedged evok-node must not be able to disable the mechanism meant to recover it.

## Decision

**Neither instrument imports anything of ours.** Encoded in `.dependency-cruiser.cjs`, generated from
the layering table there, as `layer-simulator`, `layer-rig` and `rig-no-modbus-client`.

**`simulator` implements its own slave-side CRC-16 and PDU framing.** Our `modbus` package is the master
side and wraps `modbus-serial` rather than framing frames itself (ADR-0010), so the shared surface would
have been CRC-16 and PDU encode/decode in mirror image. research/10's tier-0 requirements are explicit
that the simulator must inject CRC errors, truncated frames, garbage bytes, late responses and t3.5
violations — a framer whose entire purpose is to never emit those cannot be asked to emit them, and a
shared implementation would need a defect-injection switch inside production transport code.

**The `rig` drives its own I/O through sysfs only** — plain reads and writes under
`/run/unipi-plc/by-sys/…` to DO/RO/DI/AI/AO and ULED nodes. No Modbus client, no `unipitcp`. Three
consequences are part of the decision:

- **All switching is the test host's own RO/DO, never a DUT's.** A wedged DUT that owns its own recovery
  relay cannot be recovered.
- **Loopbacks are cross-unit.** Test-host AO → DUT AI and DUT AO → test-host AI, so each direction is
  measured by an independent device. A DUT's own AO→AI loop can cancel a shared codec error and pass.
- **Topology is declarative** in `rig.yaml`, and tests express intent (`rig bus cut ext_a`), never
  wiring. `rig reset` returns a known-good state, so a crashed run cannot poison the next one.

The two sides may share **data** — generated address tables, codec golden vectors, captured transcripts
under `fixtures/` — but never code. A fixture is a measurement both sides are checked against; that is
the opposite of a shared implementation, and it is what makes a symmetric bug detectable.

## Consequences

**The cost, plainly:** CRC-16/Modbus and PDU framing exist twice — on the order of 150 lines, the same
spec clauses implemented twice, able to drift. A bug in the simulator's framer presents as a bug in ours
and costs a debugging session to attribute. We pay that on every change to framing, forever, in exchange
for the simulator being able to disagree with us.

Makes easy: protocol-level fault injection, which is most of what tier 0 is for; trusting a green
simulator suite and a green tier-1 run; recovering a DUT unattended, which is what "no human in the
loop, ever" requires; and both instruments surviving any refactor of ours, because they depend on
nothing of ours.

Makes hard: the rig maps its own channels to sysfs paths itself, and sysfs and Modbus name channels
differently, so that mapping is hand-checked once and lives in `rig.yaml` rather than being derived from
`hw-definitions`. The host cannot power-cycle itself, so recovering the rig controller is manual. And
the documented ULED Modbus/sysfs caching conflict is harmless only because the host never speaks Modbus
to its own boards — a property to keep, not a coincidence.

**Now owed:** a differential test asserting the two framers agree on valid frames cannot live in either
package, since both directions of that import are forbidden. A neutral location is decided when M1 lands
the simulator. Until then both framers are checked against known-answer CRC vectors from the Modbus
specification and against the captured transcripts — byte-level agreement with reality rather than with
each other.

**Rejected:**

- **Sharing the framer and injecting faults by wrapping or monkey-patching it.** Cheaper in lines, and
  what most projects do; rejected because it puts a fault-injection seam in production transport code
  and the symmetric-bug failure is silent.
- **A third package holding a shared CRC and framing primitive.** The DRY answer, and it reintroduces
  exactly the cancellation this decision prevents while adding a package. Worth reopening only if the
  duplication grows well beyond framing.
- **Driving the rig with evok-node** — the fastest thing to build, and the one program in the building
  that must not be trusted by the thing measuring it.
- **Our `modbus` package behind an interface, for the rig** — same cancellation, plus the transport that
  wedges is then the transport that was supposed to observe the wedge.
- **A USB relay board, signal generator and DMM.** The host's own 5 RO + 4 DO + 8 DI + 5 AI + 5 AO cover
  every rig function, on the same architecture and OS as the DUTs. The one adapter still worth buying is
  a listen-only USB-RS485 sniffer — frame capture is the difference between a diagnosis and a guess when
  a timing test fails.
- **Running CI on the rig controller.** An M527 is an excellent rig service host and a poor CI runner:
  1 GB RAM, 8 GB eMMC, and CI write churn wears eMMC that is not replaceable. The rig is driven over the
  network from a `hardware`-labelled job elsewhere — the `hardware` workflow in
  [git rules](../rules/git.md).

This settles the `simulator → modbus` half of open question 5. The `ui → client` edge remains open, and
`.dependency-cruiser.cjs` deliberately does not rule on it.
