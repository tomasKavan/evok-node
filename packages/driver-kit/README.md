# `@evok-node/driver-kit`

How to be a driver: the scan loop, readings with `readAt` and `stale` (RC-20), the handshake, deadline
enforcement, and assembling the introspection catalogue (ADR-0010).

Enforces the two rules that make a stateless API safe: a driver's query path never blocks on I/O
(RC-27), and an endpoint's `effect` is mandatory with no default (RC-29).

**Must not depend on:** any api, `main`, `modbus`, `hw-definitions` — transport and hardware knowledge
belong to the concrete drivers.

**Its surface is a guess** until a second driver exists. N7 revisits this boundary once
`driver-extension` can correct it (ADR-0008).
