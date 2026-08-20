# Git, issues and CI rules

Binding. Cite as **RG-N**.

Trunk-based: one protected branch, short-lived work branches, squash merge. No `develop`, no
long-lived feature branches — with several agents working in parallel, a branch that lives for days
rots, and resolving the conflicts is expensive and error-prone.

## Branches and commits

**RG-1 — `main` is the only protected branch.** Pull request required, **one approval (Tomas)**, no
direct pushes, no force-push, all required checks green, linear history, **squash merge only**,
branches deleted on merge.

**RG-2 — Work branches are `<type>/<issue>-<slug>`.**

```
feat/42-modbus-rtu-framer
fix/87-stale-frame-desync
chore/12-dependency-cruiser-config
docs/33-compatibility-page
test/51-generated-address-tables
```

**RG-3 — Update a branch by rebasing on `main`, never by merging `main` into it.** Merge commits
defeat the linear history requirement and make the squash diff unreadable.

**RG-4 — Conventional Commits,** enforced by `commitlint`, scoped to the package:

```
feat(modbus): add t3.5 inter-frame pacing to the RTU port
fix(core): reset ds_mode to Simple when both DS bits are clear
test(hw-definitions): generate address tables for discontinued Neurons
chore(fixtures): re-record captured transcripts from L527
```

`feat!:` or a `BREAKING CHANGE:` footer for breaking changes. **The wire API is the public
contract** — renaming a JSON field is breaking even if no TypeScript type changed.

## Pull requests

**RG-5 — One issue, one PR, one concern.** If the description needs the word "also", split it. Keep
PRs small: a 2000-line PR from an agent cannot be meaningfully reviewed, which means the review gate
has silently stopped working.

**RG-6 — The PR body is the primary artifact,** because Tomas reviews every PR and does not write
code. Required:

```markdown
## What
One paragraph. What changed and why.

## How verified
Which tests, which tier. If hardware was involved, which rig elements.

## Design change
Only if this PR changes `docs/dev/`. What the design said, what it now says, and why.
Approving this PR approves the new design (RD-8).

## Checklist
- [ ] Tests added or updated (docs/rules/testing.md)
- [ ] docs/plan/STATUS.md updated
- [ ] Docs updated here, or a `docs-debt` issue opened
- [ ] Any decision made is recorded in `docs/dev/`; any divergence from it is under **Design change**
- [ ] No changes to fixtures/generated/ or fixtures/captured/ (or explained above)
```

The **Design change** heading is omitted when there is none — an empty one invites "n/a" on a PR that
did change the design. A PR whose code contradicts `docs/dev/` and says nothing about it is the one case
this review gate exists to catch (RD-8).

## Issues

Every unit of agent work is an issue with explicit acceptance criteria. Labels:

| Group | Values |
|---|---|
| `area/` | `transport`, `definitions`, `core`, `api`, `client`, `inspector`, `simulator`, `rig`, `ci` |
| `type/` | `feat`, `bug`, `chore`, `docs`, `test`, `spike` |
| `risk/` | `high` (actuates hardware, or touches addressing or transport), `normal` |
| `state` | **`agent-ready`**, `needs-spec`, `blocked` |
| other | `hardware-required`, `docs-debt`, `upstream-regression` |

**RG-7 — An issue is `agent-ready` only if it states** the acceptance criteria testably; which
packages and roughly which files; the test strategy and tier; and links to the relevant research
section. Otherwise it is `needs-spec`.

This gate matters more than any other process rule here. An underspecified issue handed to an agent
does not produce a question — it produces confident, plausible, wrong code, and reviewing that costs
more than specifying the issue would have.

**RG-8 — A `risk/high` issue must name a hardware or generated-table verification** in its
acceptance criteria, not just unit tests.

## CI

| Workflow | Trigger | Contents |
|---|---|---|
| `pr` | PR opened/updated | prettier, eslint, `tsc`, dependency-cruiser, tier 0, fixture-drift, coverage floors, changeset present |
| `main` | push to `main` | everything in `pr`, plus the hardware tier on the self-hosted runner, plus a build of all packages |
| `hardware` | PR labelled `hardware-required`, or manual | tier 1 on the rig, preceded by `rig loopback verify` |
| `nightly` | schedule | soak, mutation testing on codecs and addressing, dependency audit |
| `release` | tag `v*` | build, publish to npm, GitHub release from changesets |
| `prerelease` | manual | publish under the `next` dist-tag |

`rig loopback verify` runs before the hardware tier so that a hardware failure tells you immediately
whether the rig or the code is wrong.

**RG-9 — If CI fails, fix the cause.** Disabling a check, loosening a threshold or editing an
expected value to go green is a blocking review comment. The fixture-drift check is required (RT-1).

**RG-10 — Every PR that changes behaviour includes a changeset;** CI fails without one, except for
`chore` and `docs`. Versions and the changelog are generated, never hand-edited. Pre-1.0 versioning
is `0.x`, where `x` bumps for breaking changes, since the wire contract is still being established.
Alpha and beta go out under the `next` dist-tag, after the smoothing pass (RD-5).

**RG-11 — Commit hygiene.** Never commit generated output without the generator change that produced
it. Never commit a `.only`, or a skipped test without an issue link. Never commit secrets, rig IP
addresses or SSH keys — `rig.yaml` in the repo uses placeholders, and the real one lives on the test
host.
