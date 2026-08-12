# `@evok-node/api-nextgen`

Our own surface, not an extension of EVOK's — G-2 and RC-24 forbid admin, introspection and richer
metadata riding on the compat shapes, and EVOK's envelope is frozen by real clients.

A stateless translator: it holds no state and caches no readings. Its **public schema names no driver
type** (RC-30), so a new driver adds data and never schema. Serves the `ui` at `/` when `ui: true`, which
is why its reserved route prefixes are chosen once and then fixed.

**Must not depend on:** any driver, `main`, `modbus`, `hw-definitions`.
