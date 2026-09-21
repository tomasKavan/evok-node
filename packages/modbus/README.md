# `@evok-node/modbus`

Framing, transaction correlation, timing, backoff and per-device quarantine — the supervising wrapper
around `modbus-serial`, not our own framer.

Every silent-wrong-data failure in the upstream corpus lives here or in addressing, which is why this
lands before any API and gets verified hardest. A Modbus exception PDU is a failure, never a value a
caller can mistake for success (RCD-7).

Also hosts `hw-modbus-kit` (`src/hw-modbus-kit/`, design/07a): the binder that turns a `hw-definitions`-
resolved definition into bound `driver-kit` devices, shared by `driver-onboard` and `driver-extension` so
neither hand-binds a register address itself. Kept in its own subpath, not blended into the transport
engine above — the source tree still separates "wire protocol" from "hardware definition," even though
the package boundary no longer does.

**Must not depend on:** any driver, any api, `main`.
