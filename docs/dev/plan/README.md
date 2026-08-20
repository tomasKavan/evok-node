# The plan

*What do we do next?* — the one part of `docs/` that changes constantly. Brief, task-shaped, and
citing the design and the research rather than repeating either. Read order and precedence:
[`CLAUDE.md`](../../CLAUDE.md).

Neither research nor design is a plan. To know how a register behaves, read
[`research/`](../research/README.md); to know how we build it, read [`dev/`](../dev/README.md); to
know what happens next, read here.

This README holds no state of its own — only the rules and the shape. State is in `STATUS.md`,
sequence is in `roadmap.md`.

## Files

| File | Purpose |
|---|---|
| **`STATUS.md`** | **Read this first.** Current state: done, in progress, next, blocked. Present tense only — it records where we are, never how we got here. |
| **`roadmap.md`** | The milestone sequence: `MN`, one line of intent each, with its state. Milestones are added only when the work before them is understood (RPL-4). |
| `milestones/MN-*.md` | One file per milestone once it is planned — the task list. Absent until then; a milestone in `roadmap.md` with no file is not yet planned. |

## Rules

Binding. Cite as **RPL-N** — formerly `RP-N`, numbers unchanged.

**RPL-1 — `STATUS.md` is updated in the same PR as the work.** Not afterwards, not in a batch. A PR
that completes a task and leaves `STATUS.md` stale is incomplete; the checklist item exists for this.

**RPL-2 — A task is done when its acceptance criteria are demonstrable**, not when the code exists.
Demonstrable means a test, a command someone can run, or a captured artefact.

**RPL-3 — When reality diverges from the plan, change the plan in the PR that diverges.** Silent
drift is what makes a plan worthless. A one-line note saying why is enough.

**RPL-4 — Agents do not invent milestones.** Milestones are `MN`, numbered in `roadmap.md`, and only
Tomas adds one. If work doesn't fit the current milestone, open an issue proposing it and continue
with what does fit. Mid-task scope creep is expensive to unwind. The roadmap does not run ahead of
what is understood: it ends at the last milestone whose shape is actually known, and grows from there.

**RPL-5 — Milestone files stay under one page.** If a milestone needs more, it is two milestones.

**RPL-6 — Every task links to its issue,** and any task with a hardware or research dependency says
so.

**RPL-7 — No task depends on hardware that does not exist yet.** Hardware-dependent work is isolated
in its own tasks so the rest can proceed. See
[research/09](../research/09-test-hardware-coverage.md) for what we can and cannot verify.

## Task format

Terse. The issue holds the detail; this holds the shape.

Tasks are numbered `M<milestone>.<n>` and live in that milestone's file. The example below is
**format only** — no milestone owns this task, because no milestone past M3 exists.

```markdown
### M9.3 — Generated address tables            `#17` `area/definitions` `risk/high`
Generate `(model, section, kind, channel) → (register, bitOffset, coil)` for every model in
`docs/modbus-reg-map/`, including discontinued Neurons.
**Done when:** tables committed under `fixtures/generated/`; the generator is re-run in CI and
diffs fail; uniqueness property test passes for all 83 model×section combinations.
**Refs:** dev/07 §3, research/06 §3, research/10 §4
```

A task cites the dev doc it implements. A task with no dev doc to cite is a sign the design is
missing, not that the doc is unnecessary.

The read order for someone starting cold is in [`CLAUDE.md`](../../CLAUDE.md), plus `roadmap.md` and
the current milestone file. It should take ten minutes and be sufficient; if it isn't, that is a bug
in these documents — fix it.
