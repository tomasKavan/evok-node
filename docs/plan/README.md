# The plan

*What do we do next?* — the one part of `docs/` that changes constantly. Brief, task-shaped, and
referencing research rather than repeating it. Read order and precedence:
[`CLAUDE.md`](../../CLAUDE.md).

Research is not a plan. To know how a register behaves, read research; to know what to build, read
here.

## Files

| File | Purpose |
|---|---|
| **`STATUS.md`** | **Read this first.** Current state: done, in progress, next, blocked. |
| `roadmap.md` | Milestones M0–M6, one paragraph each. The shape of the whole project. |
| `milestones/M*.md` | Per-milestone task lists with acceptance criteria and exit criteria. |
| `bug-dispositions.md` | Every known EVOK finding and what we did about it. Closing it is half the definition of 1.0. |
| `capture-trip.md` | The one-session runbook for capturing stock EVOK 3.0.6 before it is replaced. Time-limited: delete it once the fixtures are in `fixtures/captured/`. |

## Rules

Binding. Cite as **RP-N**.

**RP-1 — `STATUS.md` is updated in the same PR as the work.** Not afterwards, not in a batch. A PR
that completes a task and leaves `STATUS.md` stale is incomplete; the checklist item exists for this.

**RP-2 — A task is done when its acceptance criteria are demonstrable**, not when the code exists.
Demonstrable means a test, a command someone can run, or a captured artefact.

**RP-3 — When reality diverges from the plan, change the plan in the PR that diverges.** Silent
drift is what makes a plan worthless. A one-line note saying why is enough.

**RP-4 — Agents do not invent milestones.** If work doesn't fit the current milestone, open an issue
proposing it and continue with what does fit. Mid-task scope creep is expensive to unwind.

**RP-5 — Milestone files stay under one page.** If a milestone needs more, it is two milestones.

**RP-6 — Every task links to its issue,** and any task with a hardware or research dependency says
so.

**RP-7 — No task depends on hardware that does not exist yet.** Hardware-dependent work is isolated
in its own tasks so the rest can proceed. See
[research/09](../research/09-test-hardware-coverage.md) for what we can and cannot verify.

## Task format

Terse. The issue holds the detail; this holds the shape.

```markdown
### T1.3 — Generated address tables            `#17` `area/definitions` `risk/high`
Generate `(model, section, kind, channel) → (register, bitOffset, coil)` for every model in
`docs/modbus-reg-map/`, including discontinued Neurons.
**Done when:** tables committed under `fixtures/generated/`; the generator is re-run in CI and
diffs fail; uniqueness property test passes for all 83 model×section combinations.
**Refs:** research/06 §3, research/10 §4
```

The read order for someone starting cold is in [`CLAUDE.md`](../../CLAUDE.md), plus the current
milestone file. It should take ten minutes and be sufficient; if it isn't, that is a bug in these
documents — fix it.
