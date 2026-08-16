# `@evok-node/rig`

Drives the hardware-in-the-loop rig: relays, bus cuts, power control, `rig reset` to a known-good state.

**Must not depend on:** anything of ours, and must never speak Modbus — enforced in
`.dependency-cruiser.cjs`, which is the only place that rule is written. The instrument must not
share code with the thing it measures — if the rig used our transport, a transport bug would corrupt the
measurement meant to catch it.
