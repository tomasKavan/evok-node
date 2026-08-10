# `@evok-node/modbus`

Modbus transport: framing, transaction correlation, inter-frame timing, retries and circuit
breakers, over `modbus-serial` behind an interface thin enough to replace it. A response is matched
to its own request or it is discarded — a late frame after a timeout is never returned as the new
answer.

A Modbus exception PDU is a failure, never a value a caller can mistake for success. The library's
error taxonomy is normalised into ours here, once, at this boundary.

**Must not depend on:** `core`, `server`, `client`, `inspector`, `simulator`, `hw-definitions`.
This package moves bytes to a unit id; it knows nothing about models, circuits or channels. Depends
on `protocol` only, for the branded address types and the error kinds.
