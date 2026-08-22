# 03 — Internal messaging

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the contract every driver and API talks through. The single seam that turns isolation into a
deployment choice instead of a rewrite.

**Covers**

- **Why a message boundary and not function calls.** It is the whole reason thread and process
  placement stays out of module code. Say it once, here.
- **Transport-agnostic by construction:** the same code path in-thread, cross-thread and
  cross-process. What that rules out, concretely.
- **Envelope format:** driver-qualified addressing, correlation, deadlines, error shape, and fan-in
  for reads that span drivers.
- **Introspection.** How a driver describes what it has — endpoints, kinds, data types, units,
  capabilities — and how an API turns that description into its own surface **without knowing the
  driver exists at build time**.
- **Driver classes and the data-type taxonomy:** the shared vocabulary that makes introspection
  interpretable, and how a plugin extends it without forking it.
- **Wiring is configuration.** Which links exist follows from config: an API is connected to the
  drivers it declares, and to nothing else.
- **Signalling to and from `main`:** reload, `readyToStop`, stop, health, fatal escalation. Both
  directions, and what a module must actually do on each.
- **TBD — the subscribe mechanism.** Push versus pull, per-endpoint versus per-driver, diff versus
  snapshot, backpressure, resync after a gap. Named here so it is not silently assumed by 15 and 16,
  which both depend on it.

**Inputs:** research/12 · research/08 (latency and scan budget) · to_revision/0002, 0003, 0004

**Open:** subscribe, as above. Also whether failures cross the boundary as envelopes or as thrown
errors — 06's "do not throw" rule leans one way, ergonomics the other.


-- from former ADRs

- communication between drivers and APIs are serializable messages. It possible to pass them between modules running in one thread as well as between modules running in different threads and processes.
- Internal addresses are: **`<driverId>:<driver-defined tail>`**, case-sensitive, e.g. `PLC:DI.2.01`.
- **Convention, not grammar:** a driver exposing relay and digital I/O uses uppercase `DI`, `DO`, `RO`, `AI`, `AO`, `LED` in the tail.
- Drivers answer `introspect` request and describe themselves as response. Introspection contains driver class, type, version and list of endpoints and other driver-specific infos.
- Endpoints (anything addressable in driver):
  - **`shape`** — `channel`, a structured reading, or a `method`. Not everything is a channel: a read-only network configuration is a reading whose value is a structure, and logs are a stream. Forcing those into the reading-and-state shape is the mistake this field avoids.
  - **`type`** — from a **closed enum in `@evok-node/messaging`**. Eg. DI, DO, RO. Type might have optionals which might be also described (DI has counter, ...)
  - **`effect`** — **mandatory, no default** (RC-29). Means "changing device status in any way"
  - **`returns`** — a **closed keyword set** to start: scalars plus `struct`.