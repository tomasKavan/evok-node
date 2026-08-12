# `@evok-node/modbus`

Modbus transport: framing, transaction correlation, inter-frame timing, retries and circuit
breakers, over `modbus-serial` behind an interface thin enough to replace it. A response is matched
to its own request or it is discarded — a late frame after a timeout is never returned as the new
answer.

This is the adapter boundary of RC-7 and RC-9: an exception PDU is a failure, and `modbus-serial`'s
error taxonomy is normalised into ours here, once.

**Must not depend on:** `core`, `server`, `client`, `inspector`, `simulator`, `hw-definitions`.
This package moves bytes to a unit id; it knows nothing about models, circuits or channels. Depends
on `protocol` only, for the branded address types and the error kinds.
