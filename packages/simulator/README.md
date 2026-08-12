# `@evok-node/simulator`

In-process Modbus slave simulator, generated from the register-map corpus, serving any supported
model × section — plus the fault injection tier-0 integration tests need: timeouts, late frames,
exception PDUs, disappearing units.

It is the permanent substitute for hardware we cannot buy, so it must assert what the maps say, not
what we believe: integration tests use it instead of mocking our own code.

Ships publicly from M1 — it is useful to anyone integrating with Unipi hardware.

**Must not depend on:** `core`, `server`, `client`, `inspector`, `rig`, **`modbus`**. Depends on
`protocol` and `hw-definitions`. It has its own CRC-16 and PDU codec rather than sharing `modbus`'s,
for the same reason as RC-11: the instrument must not share code with what it measures (ADR-0007).
