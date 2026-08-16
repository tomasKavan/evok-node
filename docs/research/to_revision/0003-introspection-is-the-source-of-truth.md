# ADR-0003 — Drivers self-describe, and compat's translate table is derived from it

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/12-modularisation.md · docs/research/01-evok-api-surface.md §2 ·
  ADR-0001, ADR-0002

## Context

Once addresses are driver-qualified and their tails driver-defined (ADR-0002), an API needs some way
to know what a driver actually offers. The alternative — a hand-written mapping per driver type in
`api-compat` — drifts from what the drivers expose, and nothing detects the drift.

## Decision

**Every driver answers an `introspect` request with a typed catalogue of its endpoints, and
`api-compat` derives its translate table from that catalogue rather than from hand-maintained
knowledge.**

An **endpoint** is anything addressable. The word is deliberate: `data_point` already means a specific
EVOK type (id 24, `<device_name>_<register_address>`, `datatype: null|float32`), so it cannot also
mean "any addressable value". Each endpoint declares:

- **`shape`** — `channel`, a structured reading, or a `method`. Not everything is a channel: a
  read-only network configuration is a reading whose value is a structure (RC-20), and logs are a
  stream. Forcing those into the reading-and-state shape is the mistake this field avoids.
- **`type`** — from a **closed enum in `@evok-node/messaging`**. This is where ADR-0002's convention
  becomes enforceable: an open string gives every consumer a silent default path, a closed enum makes
  adding `AI`/`AO` a compile error at every site that must handle it.
- **`effect`** — **mandatory, no default** (RC-29). An author can misdeclare it but cannot omit it.
  `run` (id 30) and `nv_save` (id 31) existing as EVOK device types is what leaving this to author
  discipline produced upstream.
- **`returns`** — a **closed keyword set** to start: scalars plus `struct`.

Drivers that genuinely discover devices declare a **capability** for it and push topology-changed
events with a generation counter; an API subscribes only to drivers that have them. Every Modbus
driver's endpoint list comes from config and is static, so it needs none of this (finding 2.1).

**Introspection carries no `compat` block and no projectability flag.** A driver publishes its
endpoints neutrally. Whether any endpoint reaches a public surface is decided by the API doing the
projecting, and by nothing else — which is also the mechanism that keeps administration off the
compat surface (ADR-0009).

## Consequences

Makes easy: a new driver type with no change to any API (RC-30); testing an API against recorded
introspection; the injectivity check on compat's table, which falls out of building it.

Makes hard: introspection is load-bearing rather than a debug affordance, so it needs wire-schema
rigour — zod in `messaging`, ADR-0001's round-trip property test, and a driver declaring something
unrepresentable fails at handshake rather than at first request.

Stated plainly: with a single `struct` keyword, `api-nextgen` is **generic over scalars and
hand-written over structures**. The self-describing-plugin property does not arrive yet.

**Now owed.** `returns` may later widen to schema references. That is additive *internally* — only
our own APIs consume introspection, and exhaustive switching turns every affected site into a compile
error — but **not** additive publicly, so the keyword set must not leak verbatim into `api-nextgen`'s
public schema. T5.x at N5 checks the envelope can already express per-channel mode sets, per-model
mode enums, structured values, several readings under one device, AI/AO scaling and an effectful
method, before N6 makes it public.

**Rejected:**

- **A `compat` block in the descriptor** — it puts EVOK's vocabulary back inside every driver, the
  coupling ADR-0001 exists to remove.
- **`effect` as a convention enforced by the driver author** — a string can be omitted, a mandatory
  field cannot, and the field is free once always present.
