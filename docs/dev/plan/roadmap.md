# Roadmap

The milestone sequence. One line of intent per milestone, and its state — nothing else. Task detail lives in `milestones/MN-*.md`; current state lives in [`STATUS.md`](STATUS.md).

The roadmap is deliberately short. It ends at the last milestone whose shape is actually understood, and grows from there. A milestone listed here without a file under `milestones/` is named, not planned.

| # | Milestone | State | Output |
|---|---|---|---|
| **M1** | **Research** — what EVOK and Unipi hardware actually do | **done** | [`docs/dev/research/`](/docs/dev/research/README.md) |
| **M2** | **Repo scaffolding** — workspace, TS, tests, lint, CI, layering guard | **done** | `packages/`, root config, `.github/workflows/` |
| **M3** | **Development documentation** — the design we implement against | **underway** | [`docs/dev/`](/docs/dev/README.md) |

**M4 and beyond are not defined**, on purpose. M3 is what tells us what they are: it settles the architecture, absorbs the proposals in [`research`](/docs/dev/research/README.md).

## Milestone states

| State | Means |
|---|---|
| `named` | listed here, not yet broken into tasks. No file under `milestones/` |
| `planned` | has a `milestones/MN-*.md` file with tasks |
| `underway` | work has started. May be `named` or `planned` — M1 and M3 predate the milestone-file convention and have neither file |
| `done` | every task it had meets RPL-2 — demonstrable, not merely written |

M1 and M2 are marked `done` retrospectively: they were completed before this roadmap existed, so their
evidence is the output column, not a task file.
