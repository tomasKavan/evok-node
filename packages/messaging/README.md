# `@evok-node/messaging`

The single source of truth for the **internal** driver↔API contract: envelopes, request and event
shapes, the introspection descriptor, error kinds, correlation, deadlines, and the fan-in helper that
queries several drivers with a per-driver deadline (RC-28).

Everything here must survive serialise/deserialise — that is the property test, and anything that does
not is not a valid message (ADR-0001). Deadlines live in the envelope so RC-14 cannot be forgotten
(RC-26).

**Must not depend on:** anything of ours. It is the root of the DAG.

**Must not contain:** any package's *public* wire schema. One package holding both the internal contract
and a public surface is how internal metadata reaches a compat shape (ADR-0008, RC-12).
