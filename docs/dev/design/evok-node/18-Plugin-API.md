# 18 — API plugins

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** writing an API surface that is not ours.

**Covers**

- **The minimum surface,** and what the runner provides.
- **Declaring which drivers you consume,** and building your own projection from their introspection.
  The same problem as 12, approached from the other side — cross-reference rather than repeat.
- **Dos and don'ts:** do not own device state · do not block · no direct driver access · no reliance
  on our private schemas.
- **Spawning and threading** for a plugin that does real work, per 13's "declare heavy" rule.
- **Logging standards,** shared with 12.
- **Worked example: MQTT.** Publish endpoint state, accept commands, derive topics from introspection.
  Chosen because it exercises subscription, translation and the write path at once, while being a
  protocol we owe no compatibility guarantee to.

**Inputs:** 03 · 13 · to_revision/0001

**Open:** whether MQTT stays an example in this file or becomes a shipped package. Shipping it changes
its status from illustration to obligation.
