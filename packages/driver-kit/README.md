# `@evok-node/driver-kit`

How to be a driver: the scan loop, readings with `readAt` and `stale` (RPG-DRV-2), the handshake, deadline
enforcement, and assembling the introspection catalogue.

Enforces the two properties that make a stateless API safe: a driver's query path never blocks on I/O
— a query reads state the scan loop already collected — and an endpoint's `effect` is mandatory with no
default.

**Must not depend on:** any api, `main`, `modbus`, `hw-definitions` — transport and hardware knowledge
belong to the concrete drivers.

**Its surface is a guess** until a second driver exists. Revisit this boundary once
`driver-extension` can correct it.
