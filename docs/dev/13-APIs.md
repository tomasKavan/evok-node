# 13 — APIs

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** what every API must be, whatever it speaks. The concepts 14–18 specialise rather than
restate.

**Covers**

- **The two obligations: hold no state data · do not block.** Device state lives in drivers. An API
  holds only what it needs to translate internal messages to and from its own surface.
- **What "translation state" legitimately is:** projection tables, subscriptions, sessions, schema
  caches — and why it is *rebuilt* rather than persisted. The line between this and device state is
  the one thing this file must make unmissable.
- **Consuming introspection:** how an API discovers what a driver offers and decides what to expose,
  the declared-drivers list, and what happens when a configured driver is one it does not understand.
- **Heavy computation.** An API that needs it **declares** it and is spawned accordingly instead of
  blocking the loop. Define "heavy" in terms someone can check.
- **Lifecycle and reload from the API's side:** connected clients across a driver restart, and what a
  client is promised while a driver is gone.
- **Error surfaces:** turning internal failure into a protocol error without leaking internals.

**Inputs:** research/12 · ADR-0001, ADR-0003, ADR-0009 (suspended)
