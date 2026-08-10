# `@evok-node/protocol`

Wire schemas as zod, and the internal core↔API message envelopes. The single source of truth for the
API contract: zod parses at ingress, `z.toJSONSchema()` produces fastify's route schemas. One
declaration, both uses.

Also the only place the two vocabularies are mapped — EVOK's `dev`/`circuit`/`glob_dev_id` on the
outside, our `DeviceKind`/`id`/`deviceId` on the inside — and the home of the branded scalar types
(`RegisterAddress`, `CoilAddress`, `UnitId`, `BitOffset`) with their range-checking constructors.

**Must not depend on:** any other workspace package. Everything else depends on this, so an edge out
of it is a cycle. No fastify, no Modbus client, no filesystem, no clock.

Envelopes must survive serialise/deserialise — no callbacks, class instances or `Buffer`s in a
message shape (ADR-0001).
