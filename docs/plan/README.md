# The plan

## Four kinds of document, four jobs

| | Question it answers | Lifetime | Style |
|---|---|---|---|
| **`docs/GOALS.md`** | *What are we trying to achieve, and what do we refuse to do?* | permanent; amended by dated note | 1 page, terse |
| **`docs/research/`** | *What is true* about EVOK and Unipi hardware? | permanent; corrected, never rewritten | long, cited, evidence-marked |
| **`docs/plan/`** (here) | *What do we do next?* | changes constantly | brief, task-shaped, references research |
| **`docs/adr/`** | *Why* did we decide this? | permanent; superseded, never edited | 1 page, dated |

Research is not a plan. If you need to know how a register behaves, read research. If you need to
know what to build, read here. If you're about to relitigate a decision, read the ADR first. If you
are about to argue that something is in or out of scope, read [`GOALS.md`](../GOALS.md) — it wins
over all three.

## Files

| File | Purpose |
|---|---|
| **`STATUS.md`** | **Read this first.** Current state: done, in progress, next, blocked. |
| `roadmap.md` | Milestones M0–M6, one paragraph each. The shape of the whole project. |
| `milestones/M*.md` | Per-milestone task lists with acceptance criteria and exit criteria. |
| `bug-dispositions.md` | Every known EVOK finding and what we did about it. Closing it is half the definition of 1.0. |

## Rules

1. **`STATUS.md` is updated in the same PR as the work.** Not afterwards, not in a batch. A PR
   that completes a task and leaves `STATUS.md` stale is incomplete — the checklist item exists
   for this.
2. **A task is done when its acceptance criteria are demonstrable**, not when the code exists.
   "Demonstrable" means a test, a command someone can run, or a captured artefact.
3. **When reality diverges from the plan, change the plan in the PR that diverges.** Silent drift
   is the failure mode that makes a plan worthless. A one-line note saying why is enough.
4. **Agents do not invent milestones.** If work doesn't fit the current milestone, open an issue
   proposing it and continue with what does fit. Scope creep by an agent mid-task is expensive to
   unwind.
5. **Milestone files stay under one page.** If a milestone needs more, it is two milestones.
6. **Every task links to its issue**, and every task with a hardware or research dependency says
   so explicitly.
7. **No task may depend on hardware that does not exist yet.** Hardware-dependent work is
   isolated in its own tasks so the rest can proceed. See
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

## Cold start

An agent picking this up with no context should read, in order: `CLAUDE.md` →
[`docs/GOALS.md`](../GOALS.md) → `docs/plan/STATUS.md` → the current milestone file → the rules file
for the area it is touching → the research file for the domain it is touching. That path should take
ten minutes and be sufficient. If it isn't, that's a bug in these documents — fix it.
