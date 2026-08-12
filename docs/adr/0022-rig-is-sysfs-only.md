# ADR-0022 — The rig is sysfs-only and shares no code with what it measures

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/10-test-kit.md §Tier 1 (test host, loopbacks, fault injection) ·
  RC-11 · ADR-0007

## Context

Tier 1 runs on a second Patron M527 whose own I/O *is* the instrumentation — its RO/DO switch
extension power and cut RS-485 pairs, its DI observe DUT outputs, its AI/AO close analog loops
([research/10](../research/10-test-kit.md)). The tempting implementation is to drive that I/O with
evok-node itself, or at least with our own `modbus` package. Both are wrong for reasons that only
show up as a *passing* test.

## Decision

**The rig drives its own I/O through sysfs only** — plain reads and writes under
`/run/unipi-plc/by-sys/…` to DO/RO/DI/AI/AO and ULED nodes. No Modbus client, no `unipitcp`
involvement, and no workspace import at all (RC-11, generated into `.dependency-cruiser.cjs` as
`layer-rig` plus `rig-no-modbus-client`).

Three consequences of that are part of the decision, not detail:

- **All switching is the test host's own RO/DO, never a DUT's.** A wedged DUT that owns its own
  recovery relay cannot be recovered.
- **Loopbacks are cross-unit.** Test-host AO → DUT AI and DUT AO → test-host AI, so each direction is
  measured by an independent device. A DUT's own AO→AI loop can cancel a shared codec error and pass.
- **Topology is declarative** in `rig.yaml`, and tests express intent (`rig bus cut ext_a`), never
  wiring. `rig reset` returns a known-good state, so a crashed run cannot poison the next one.

Two failure modes, both specific: a bug in a shared transport can make a test pass that should fail,
and a wedged evok-node must not be able to disable the mechanism meant to recover it. The first is the
same symmetric-cancellation argument as ADR-0007 — the instrument must not share code with what it
measures — and for tier 1 the instrument is the rig.

## Consequences

Makes easy: trusting a green tier-1 run; recovering a DUT unattended, which is what "no human in the
loop, ever" requires; and a rig that survives any refactor of ours, because it depends on nothing of
ours.

Makes hard: the rig maps its own channels to sysfs paths itself, and sysfs and Modbus name channels
differently, so that mapping is hand-checked once and lives in `rig.yaml` rather than being derived
from `hw-definitions`. Two other prices, accepted: the host cannot power-cycle itself, so recovering
the rig controller is manual; and the documented ULED Modbus/sysfs caching conflict is harmless only
because the host never speaks Modbus to its own boards — a property to keep, not a coincidence.

**Rejected: driving the rig with evok-node.** The fastest thing to build, and the one program in the
building that must not be trusted by the thing measuring it.

**Rejected: our `modbus` package behind an interface.** Same symmetric-bug cancellation as ADR-0007,
and it reintroduces the shared-failure path: the transport that wedges is then the transport that was
supposed to observe the wedge.

**Rejected: a USB relay board, signal generator and DMM.** The host's own 5 RO + 4 DO + 8 DI + 5 AI +
5 AO cover every rig function, on the same architecture and OS as the DUTs. Fewer moving parts is
fewer rig failures misread as product failures. The one adapter still worth buying is a listen-only
USB-RS485 sniffer — frame capture is the difference between a diagnosis and a guess when a timing test
fails.

**Rejected: running CI on the rig controller.** An M527 is an excellent rig service host and a poor CI
runner: 1 GB RAM, 8 GB eMMC, and CI write churn wears eMMC that is not replaceable. The rig is driven
over the network from a `hardware`-labelled job running elsewhere — the `hardware` workflow in
[git rules](../rules/git.md).
