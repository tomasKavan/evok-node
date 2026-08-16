# 07 — Modbus driver

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the shared ancestor of onboard (08) and extension (09) — everything Modbus, nothing
Unipi-model-specific.

**Covers**

- **The split.** Transport, framing, correlation, timing, batching and breakers live here; identity,
  layout and configuration live in the children. State the seam, because it is what stops 08 and 09
  from drifting into two implementations.
- **The hardware-definition format.** What a definition declares; how sections, blocks and channels
  map onto registers, coils and bit offsets; how a model is identified; how overlays compose. This is
  the load-bearing half of the file.
- **Generated address tables:** why `(model, section, kind, channel) → (register, bitOffset, coil)` is
  generated and diff-checked in CI rather than computed at runtime, plus the fatal
  duplicate-registration assertion (RPG-DRV-3). This is the direct mitigation for the
  wrong-relay bug class — say so.
- **Data types and encodings,** and where a third party inserts a new one.
- **Bringing your own device definition:** what it may assume, what it may not, and how it is
  validated before anything is driven.
- **Comparison to EVOK's `hw_definitions`:** what we keep, what we deliberately drop, and which of its
  defects are *format* bugs rather than code bugs. Cite research/14 findings; do not restate them.

**Inputs:** research/02 · research/03 · research/06 · research/13 · research/14 ·
[`rules/packages/driver-modbus.md`](../rules/packages/driver-modbus.md) · ADR-0007, ADR-0012,
ADR-0014 (suspended) · [`docs/modbus-reg-map/`](../modbus-reg-map/README.md)
