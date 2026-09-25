# 17 — Driver plugins in the nextgen API and the UI

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the end-to-end path by which a third-party driver becomes visible and usable in the nextgen
API (15) and the inspector (16).

**Covers**

- **What good introspection alone buys you** — and that it costs nothing extra. If the common case
  needs more than 01 §6 / 03's introspection, that is a defect in 15, not a gap here.
- **What needs explicit contribution:** display metadata, units, grouping, visual layout, custom
  controls.
- **The inspector plugin seam:** how a driver ships UI without `ui` depending on the driver. Nothing
  imports `ui`, and `ui` must not import a plugin — so the mechanism has to be runtime.
- **Degradation.** What nextgen and the UI show for a data type they do not recognise. Never nothing,
  never a crash — state the fallback.
- **Versioning across three moving parts** (driver, API schema, UI), and what breaks when they
  disagree.

**Inputs:** 01 · 03 · 15 · 16 · to_revision/0003

**Open:** whether the inspector plugin seam exists at 1.0, or generic introspection-driven rendering
is enough to defer it.
