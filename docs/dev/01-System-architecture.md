# 01 — System architecture

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the shape of the daemon — two component kinds, one orchestrator, and the seams that let
components move without being rewritten.

**Covers**

- **`main` orchestrates:** config, validation, spawn, supervise, reload. It is on **no request path**.
  Say what that buys and what it forbids.
- **Drivers act, APIs query.** There is no third component kind — anything that would have been one is
  a driver whose transport is not Modbus.
- **The four plugin kinds** and what distinguishes them: driver plugin, API plugin, in-driver plugin
  (device definitions, data types, chip families), inspector plugin (UI for the above).
- **Non-blocking loop as architecture, not style.** What "never block" means at each seam, and where
  work that cannot honour it is supposed to go instead.
- **The isolation seam.** G-1 says one process *for now*, and the suspended ADR-0004 went further and
  said single-threaded — deciding which of those 1.0 actually commits to is this file's job. Either
  way, a driver or API must be movable into a worker thread or a separate process **without changing
  its code**. What that costs, and what it therefore
  forbids: shared mutable state, direct imports across components, clone-hostile payloads.
- **APIs choose their drivers.** An API declares which drivers it can consume and which endpoints it
  exposes. Compat's narrow fixed set versus nextgen's open one, and why that asymmetry is correct.
- **The runner.** The module that hosts a component instance, wires its messaging and enforces its
  lifecycle identically regardless of where it runs. This is the piece that makes placement a config
  decision.
- The package-to-component mapping, with the layering DAG in `.dependency-cruiser.cjs` as its
  enforceable form.

**Inputs:** research/12 · ADR-0001, ADR-0002, ADR-0003, ADR-0004 (suspended) ·
[`GOALS.md`](../GOALS.md) invariants · `.dependency-cruiser.cjs`

**Open:** whether in-driver and inspector plugins are real extension points at 1.0, or just internal
structure we should stop calling plugins.
