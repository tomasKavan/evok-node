# `@evok-node/simulator`

In-process Modbus slave simulator, generated from the register-map corpus, serving any supported
model × section — plus the fault injection tier-0 integration tests need: timeouts, late frames,
exception PDUs, disappearing units.

It is the permanent substitute for hardware we cannot buy, so it must assert what the maps say, not
what we believe: integration tests use it instead of mocking our own code.

Ships publicly from M1 — it is useful to anyone integrating with Unipi hardware.

**Must not depend on:** `core`, `server`, `client`, `inspector`, `rig`. Depends on `protocol` and
`hw-definitions`. Whether it may share `modbus`'s framer with the code it stands in for is an open
question — see the note in [docs/plan/STATUS.md](../../docs/plan/STATUS.md).
