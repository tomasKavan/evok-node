# Roadmap

The milestone sequence. One line of intent per milestone, and its state — nothing else. Task detail lives in `milestones/MN-*.md`; current state lives in [`STATUS.md`](STATUS.md).

The roadmap is deliberately short. It ends at the last milestone whose shape is actually understood, and grows from there. A milestone listed here without a file under `milestones/` is named, not planned.

| # | Milestone | State | Output |
|---|---|---|---|
| **M1** | **Research** — what EVOK and Unipi hardware actually do | **done** | [`docs/dev/research/`](/docs/dev/research/README.md) |
| **M2** | **Repo scaffolding** — workspace, TS, tests, lint, CI, layering guard | **done** | `packages/`, root config, `.github/workflows/` |
| **M3** | **Design** — the core of the system designed before development starts | **underway** | [`milestones/M3-design.md`](milestones/M3-design.md) |
| **M4** | **Core implementation** — planned by M3.21 | `named` | — |
| **M5** | **Design II** — the parts M3 left out: 2N, shell app, Inspector plugins, Home API and UI, Matter bridge, more simulators, test rig | `planned` | [`milestones/M5-design.md`](milestones/M5-design.md) |

**M6 and beyond are not defined**, on purpose. M3.21 plans M4 — the order in which we code the core chapter by chapter, absorbing the proposals in [`research`](/docs/dev/research/README.md).

## Milestone states

| State | Means |
|---|---|
| `named` | listed here, not yet broken into tasks. No file under `milestones/` |
| `planned` | has a `milestones/MN-*.md` file with tasks |
| `underway` | work has started. May be `named` or `planned` — M1 predates the milestone-file convention and has no file |
| `done` | every task it had meets RPL-2 — demonstrable, not merely written |
