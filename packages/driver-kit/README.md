# `@evok-node/driver-kit`

How to be a driver: the endpoint dispatcher (`bind`/`unbind`/`attach`), the handshake, deadline
enforcement, and assembling the introspection catalogue.

Does **not** own a generic scan loop or `readAt`/`stale` — that turned out to be transport-specific
enough that `hw-modbus-kit` (`@evok-node/modbus`, design/07a) owns its own, rather than this package
guessing at a shared shape before a second scan-based driver exists to correct it against. Revisit once
one does.

Enforces the property that makes a stateless API safe regardless: an endpoint's `effect` is mandatory
with no default.

**Must not depend on:** any api, `main`, `modbus`, `hw-definitions` — transport and hardware knowledge
belong to the concrete drivers.

**Its surface is a guess** until a second driver exists. Revisit this boundary once
`driver-extension` can correct it.
