# Git, issues and CI rules

Trunk-based. One protected branch, short-lived work branches, squash merge. No `develop`, no
long-lived feature branches — with several agents working in parallel, branches that live for
days rot and conflict resolution is expensive and error-prone.

## Branches

`main` is the only protected branch:

- pull request required, **1 approval (Tomas)**, no direct pushes, no force-push
- all required checks green
- linear history, **squash merge only**
- branches deleted on merge

Work branches: **`<type>/<issue>-<slug>`**

```
feat/42-modbus-rtu-framer
fix/87-stale-frame-desync
chore/12-dependency-cruiser-config
docs/33-compatibility-page
test/51-generated-address-tables
```

Update a branch by **rebasing** on `main`, never by merging `main` into it — merge commits defeat
the linear history requirement and make the squash diff unreadable.

Release branches only if we ever maintain a 1.x while building 2.x. Not now.

## Commits

**Conventional Commits**, enforced by `commitlint`. Scope is the package name:

```
feat(modbus): add t3.5 inter-frame pacing to the RTU port
fix(core): reset ds_mode to Simple when both DS bits are clear
test(hw-definitions): generate address tables for discontinued Neurons
chore(fixtures): re-record captured transcripts from L527
```

`feat!:` or a `BREAKING CHANGE:` footer for breaking changes. **The wire API is the public
contract** — a change to a JSON field name is breaking even if no TypeScript type changed.

## Pull requests

**One issue, one PR, one concern.** If a PR needs the word "also" in its description, split it.

Tomas reviews every PR and does not write code, so the PR body is the primary artifact.
Required:

```markdown
## What
One paragraph. What changed and why.

## How verified
Which tests, which tier. If hardware was involved, say which rig elements.

## Checklist
- [ ] Tests added or updated (see docs/rules/testing.md)
- [ ] `docs/plan/STATUS.md` updated
- [ ] Docs updated in this PR, or a `docs-debt` issue opened
- [ ] ADR added if a decision was made
- [ ] No changes to `fixtures/generated/` or `fixtures/captured/` (or explained above)
```

Keep PRs small. A 2000-line PR from an agent cannot be meaningfully reviewed, which means the
review gate silently stops working.

## Issues

Every unit of agent work is an issue with **explicit acceptance criteria**. Labels:

| Group | Values |
|---|---|
| `area/` | `transport`, `definitions`, `core`, `api`, `client`, `inspector`, `simulator`, `rig`, `ci` |
| `type/` | `feat`, `bug`, `chore`, `docs`, `test`, `spike` |
| `risk/` | `high` (actuates hardware, or touches addressing/transport), `normal` |
| `state` | **`agent-ready`**, `needs-spec`, `blocked` |
| other | `hardware-required`, `docs-debt`, `upstream-regression` |

### The `agent-ready` gate

An issue is `agent-ready` **only** if it states:

1. the acceptance criteria, testably;
2. which package(s) and roughly which files;
3. the test strategy and tier;
4. links to the relevant research section.

Otherwise it is `needs-spec`. This gate matters more than any other process rule here: an
underspecified issue handed to an agent does not produce a question, it produces confident,
plausible, wrong code — and reviewing that costs more than specifying the issue would have.

`risk/high` issues additionally require the acceptance criteria to name a hardware or
generated-table verification, not just unit tests.

## CI workflows and triggers

| Workflow | Trigger | Contents |
|---|---|---|
| `pr` | PR opened/updated | prettier, eslint, `tsc`, dependency-cruiser, tier-0 unit + generated + simulator + golden, fixture-drift check, coverage floors, changeset present |
| `main` | push to `main` | everything in `pr`, plus `hardware` tier on the self-hosted runner, plus a build of all packages |
| `hardware` | PR labelled `hardware-required`, or manual | tier 1 on the rig. Preceded by `rig loopback verify` — if the rig is miswired, fail loudly |
| `nightly` | schedule | soak tests, mutation testing on codecs and addressing, dependency audit |
| `release` | tag `v*` | build, publish to npm, GitHub release from changesets |
| `prerelease` | manual | publish under the `next` dist-tag |

**Fixture-drift check** is a required check: regenerate `fixtures/generated/` and fail on diff.

`rig loopback verify` running before the hardware tier is deliberate — a hardware failure should
tell you whether the rig or the code is wrong, immediately.

## Releases

**changesets.** Every PR that changes behaviour includes a changeset; CI fails without one
(except for `chore`/`docs`). Version bumps and the changelog are generated — never hand-edited.

Pre-1.0 versioning: `0.x` where `x` bumps for breaking changes, since the wire contract is being
established. Alpha and beta go out under the `next` dist-tag with a scheduled docs smoothing pass
first (see [docs rules](docs.md)).

## Commit hygiene for agents

- Never commit generated output without the generator change that produced it.
- Never commit a `.only` in a test, or a skipped test without an issue link.
- Never commit secrets, rig IP addresses, or SSH keys. `rig.yaml` in the repo uses placeholder
  addresses; the real one lives on the test host.
- If CI fails, fix the cause. Disabling a check, loosening a threshold or editing an expected
  value to go green is a blocking review comment.
