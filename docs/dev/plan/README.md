# The plan

Because this section is used and edited also by Agents, it's written more explanatory with explicit rules.

*What do we do next?* — the one part of `docs/` that changes constantly. Brief, task-shaped, and
citing the design and the research rather than repeating either.

Neither [`research`](/docs//dev/research/README.md) nor [`design`](/docs/dev/README.md) is a plan. 

## Files

- **`STATUS.md`** - Current state: done, in progress, next, blocked. Present tense only — it records where we are, never how we got here.
- **`roadmap.md`** - The milestone sequence: `M`, one line of intent each, with its state. Milestones are added only when the work before them is understood.
- `milestones/M-*.md` - One file per milestone once it is planned — the task list. Absent until then; a milestone in `roadmap.md` with no file is not yet planned.

## Rules

### **`STATUS.md` is updated in the same PR as the work.**
`STATUS.md` is updated in the same PR as the work. Not afterwards, not in a batch. A PR that completes a task and leaves `STATUS.md` stale is incomplete; the checklist item exists for this.

### **A task is done when its acceptance criteria are demonstrable**
A task is done when its acceptance criteria are demonstrable, not when the code exists. Demonstrable means a test, a command someone can run, or a captured artefact.

### **Diverent reality from the plan.**
When reality diverges from the plan, change the plan in the PR that diverges. Silent drift is what makes a plan worthless. A one-line note saying why is enough.

### **Agents do not invent milestones.** 
Milestones are `M`, numbered in `roadmap.md`, and only humans adds one. If work doesn't fit the current milestone, open an issue proposing it and continue with what does fit. Mid-task scope creep is expensive to unwind. The roadmap does not run ahead of what is understood: it ends at the last milestone whose shape is actually known, and grows from there.

### **Milestone files stay under one page.** 
If a milestone needs more than 1 page, it is probably two milestones.

## Task format

Brief. The issue/desing docu holds the detail; this holds the shape.

Tasks are numbered `M<milestone>.<n>` and live in that milestone's file. Eg: (not real task)

```markdown
### M9.3 — Generated address tables            `#17` `area/definitions` `risk/high`
Generate `(model, section, kind, channel) → (register, bitOffset, coil)` for every model in `docs/modbus-reg-map/`, including discontinued Neurons.
**Done when:** tables committed under `fixtures/generated/`; the generator is re-run in CI and diffs fail; uniqueness property test passes for all 83 model×section combinations.
**Refs:** dev/07 §3, research/06 §3, research/10 §4
```

A task cites the dev doc it implements. A task with no dev doc to cite is a sign the design is missing, not that the doc is unnecessary.
