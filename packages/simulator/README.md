# `@evok-node/simulator`

Serves any model in the map corpus, and injects the faults hardware cannot be asked for: wrong CRCs,
truncated frames, stale responses, silent slaves.

The permanent substitute for hardware we can no longer buy, and the only substrate the drivers are tested
against. Ships publicly from N1.

**Must not depend on:** `modbus`. It has its own framer, deliberately — a shared framer cannot be asked to
emit a wrong CRC (ADR-0007). Also: no driver, no api, no `main`.
