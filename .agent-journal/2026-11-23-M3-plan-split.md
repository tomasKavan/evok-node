# 2026-11-23 — M3 — Plan split: core design, core implementation, design II

Role: sparring partner, then system designer. Task: reshape the plan after M3.7b.

## Decisions with Tomas

- M3 designs only the core before implementation; the rest moves to a new milestone. Reason: start coding without waiting for UIs, Matter and the rig.
- M4 = core implementation (named, planned by M3.21). M5 = design II (planned). Reason: Tomas's ordering.
- WS API (M3.8) stays in M3. Reason: 15 is a memo, and the Inspector, bootstrap, `RemoteLink` and the auth extensions all depend on it.
- The Inspector UI-plugin contract (`inspector-panel`, management view, usage outside config) goes from M3.10 into M3.9; the main plugins go to M5.3.
- M3.14 is narrowed: renumber before code cites sections, no memo text in docs designed in M3, the Tester role in AGENTS.md.
- M3.17 covers Modbus only; 1-Wire and DALI simulators go to M5.7.
- Moved tasks get new numbers, and every reference is updated: M3.6a→M5.1, M3.7→M5.2, M3.10→M5.3 (contract parts →M3.9), M3.11→M5.4, M3.12→M5.5, M3.13→M5.6, M3.18–20→M5.8–10.

## Edited

- `plan/milestones/M3-design.md`, new `plan/milestones/M5-design.md`, `plan/roadmap.md`, `plan/STATUS.md`.
- Task references in design docs 02b, 12a, 12c index, 12c-04/07/08/09/10/12/13, 13a, 16a and in research/auth (README, 06, 07) and research/matter/09.

## Left

- M3 still has M3.8, M3.9, M3.14–M3.17 and M3.21.
