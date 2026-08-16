# 09 — Extension driver

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** Unipi extensions and accessories over RS-485 — one driver instance per line.

**Covers**

- **One instance per RS-485 line,** and why the *line* rather than the device is the unit of ownership.
  Everything else in this file follows from that.
- **Addressing:** unit IDs, declaration versus discovery, and what happens on a collision or a silent
  unit.
- **Serial timing:** baud encoding, inter-frame gaps, turnaround, and the shared-bus fairness problem
  when many units want the same line. Ties to research/08's budget.
- **Extensions versus accessories:** where the model genuinely differs and where it does not.
- **Bringing your own definition** for an unsupported unit — the practical path, and its limits.
- **Failure isolation:** one dead unit must not stall the line, and must not look like a healthy unit
  reading zero.

**Inputs:** research/02 · research/06 · research/08 · ADR-0010 (suspended) ·
`docs/modbus-reg-map/extensions/`, `docs/modbus-reg-map/accessories/`

**Open:** AI/AO over RTU — float32 AI, raw-count AO, the six-mode enum on an extension — cannot be
verified on the hardware we have. [`STATUS.md`](../plan/STATUS.md) holds the current inventory and is
the only place it is recorded; do not copy it here.
