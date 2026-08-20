# 20 — Test rig

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the physical test rig — a project in its own right, on a parallel track.

**Covers**

- **What the rig is and what it exists to prove:** the tier-1 tests simulation cannot (research/09).
  Start from 19's "cannot prove" list.
- **Architecture:** subject host and master/controller host, and why they are separate machines.
- **The `rig` service:** private, sysfs only, no workspace dependencies. Deliberately dumb — say why
  cleverness here would compromise the evidence.
- **Wiring and connection layout:** the RO→DI loopbacks, the RS-485 lines, the units attached, and
  what each connection makes testable.
- **The test battery:** what runs, in what order, and what each test is evidence *for*.
- **Installing release-candidate packages** onto the subject, and resetting cleanly between runs.
- **CI wiring:** how the rig is triggered, how results come back, and why it **gates nothing**
  (RPL-7).

**Inputs:** research/09 · research/10 · RT-15 · [`STATUS.md`](../plan/STATUS.md)
blocked items

**Open:** blocked on rig hardware and wiring; [`STATUS.md`](../plan/STATUS.md) holds the specifics.
Parallel track throughout — it must never be on the critical path.
