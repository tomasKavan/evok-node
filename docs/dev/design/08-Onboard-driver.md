# 08 — Onboard driver

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the controller's own I/O sections, reached over Modbus TCP to `unipitcp`.

**Covers**

- **Why TCP to `unipitcp` and not SPI ourselves.** G-7's coexistence line, and what we therefore do
  not own or control.
- **Model identification:** register 1004, the census fallback, and the behaviour on an unknown or
  ambiguous model. A model without 1004 is normal, not incomplete.
- **Sections,** and the *at most one onboard driver* constraint, which 14 owns and this file only
  obeys. Zero onboard sections is legal — see 14 for what that means to a client.
- **Configuration:** what a user sets, what is derived from the model, and what is refused outright.
- **Unipi OS interaction:** what `unipitcp` expects, `run.d`, and what our package installs where.
- **Autogen:** deriving the instance's endpoint set from model plus definition, EVOK-style — and
  where we deliberately diverge from `autogen.yaml`.

**Inputs:** research/02 · research/03 · research/06 · `GOALS §Hardware scope` · to_revision/0014

**Open:** partly **blocked on the capture trip** — AI/AO mode enumerations and which `run.d` exists.
[`STATUS.md`](../plan/STATUS.md) is authoritative on what is still missing and why; do not restate it
here, it will go stale.
