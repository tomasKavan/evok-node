# 13 — APIs

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** what every API must be, whatever it speaks. Each api's own file (15 onwards)
specialises these rather than restating them.

**Covers**

- **The two obligations: hold no state data · do not block.** Device state lives in drivers. An API
  holds only what it needs to translate internal messages to and from its own surface.
- **What "translation state" legitimately is:** projection tables, subscriptions, sessions, schema
  caches — and why it is *rebuilt* rather than persisted. The line between this and device state is
  the one thing this file must make unmissable.
- **Protocol identity state — the one persistent kind.** Some state an api owns can't be rebuilt:
  Matter's fabric table, operational keys, ACLs, fabric-scoped bindings/groups/scenes, the
  tail → endpoint-number map and message counters (16a) — losing it un-pairs every controller. It is
  never device state; it's the api's own identity on its protocol, like an HTTP api's TLS keys.
  Persisted through 06 in the api's own `api.<id>` namespace, secrets as sensitive keys (06 §5a).
  Define it narrowly, so "hold no state" still means exactly what it says for everything else.
  It is an api's state because there the api *is* the device. In the opposite case — evok-node as a
  protocol **client**, e.g. 12a's own Matter controller (12a §4a) — the client is a driver, and its
  fabric is that driver's user data.
- **Consuming introspection:** how an API discovers what a driver offers and decides what to expose,
  the declared-drivers list, and what happens when a configured driver is one it does not understand.
- **Heavy computation.** An API that needs it **declares** it and is spawned accordingly instead of
  blocking the loop. Define "heavy" in terms someone can check.
- **Lifecycle and reload from the API's side:** connected clients across a driver restart, and what a
  client is promised while a driver is gone.
- **Error surfaces:** turning internal failure into a protocol error without leaking internals.

**Inputs:** research/12 · to_revision/0001, 0003, 0009
