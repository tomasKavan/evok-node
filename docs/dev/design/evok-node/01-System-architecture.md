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
- **The isolation seam.** G-1 says one process *for now*, and `to_revision/0004` proposes going further
  to single-threaded — deciding which of those 1.0 actually commits to is this file's job. Either
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

**Inputs:** research/12 · to_revision/0001, 0002, 0003, 0004 ·
[`GOALS.md`](../GOALS.md) invariants · `.dependency-cruiser.cjs`

**Open:** whether in-driver and inspector plugins are real extension points at 1.0, or just internal
structure we should stop calling plugins.



TO review - from GOALS.md

1. **G-1 — Driver↔API is a serialisable message boundary.** Not a function-call interface that happens to
   be crossable. One process for now; splitting components into separate processes later must be
   additive. A function-call boundary leaks callbacks, class instances and Buffers and makes the
   split a rewrite. Supersedes the "purely additive later" framing in
   [research/05](research/05-evok-node-design-notes.md) §5 and §7.3.

3. **G-4 — One instance, one PLC.** As EVOK. Circuit ids stay flat. A SPA may point at several
   instances and aggregate client-side.

5. **G-6 — A driver or api module (internal or plugin) cannot compromise the daemon.** It may not starve a scan loop, hold a bus past its
   lease, or take the process down with it. A plugin needing bus access gets a leased, time-budgeted
   transaction through the driver that owns that bus — never a client of its own on a port a scan loop
   owns. 


-- from forme ADRs

- 2 type of modules - drivers and APIs, main module to orchestrate, some common services. Strong emphasis on separation, modules is possible to configure to run in separate thread or process. Driver acts, API queries.
