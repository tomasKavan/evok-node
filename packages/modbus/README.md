# `@evok-node/modbus`

Framing, transaction correlation, timing, backoff and per-device quarantine — the supervising wrapper
around `modbus-serial`, not our own framer.

Every silent-wrong-data failure in the upstream corpus lives here or in addressing, which is why this
lands before any API and gets verified hardest. A Modbus exception PDU is a failure, never a value a
caller can mistake for success (RC-7).

**Must not depend on:** any driver, any api, `main`, `hw-definitions`.
