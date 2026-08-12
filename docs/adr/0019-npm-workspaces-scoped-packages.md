# ADR-0019 — npm workspaces, with scoped `@evok-node/*` package names

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** 2026-07-29 planning session · docs/research/12-modularisation.md §Package layout ·
  docs/plan/milestones/N0-re-steer-and-scaffolding.md T0.1, T0.3 · RC-10, RC-11 · ADR-0007, ADR-0014

## Context

The design is many small packages with a layering DAG that has to be *enforced*, not merely drawn:
RC-10's partition, RC-11's isolated rig, ADR-0007's simulator exclusion. That needs a monorepo tool,
and the choice was made in the 2026-07-29 planning session before any research file covered tooling.
It is written up here because it has one consequence that decides how much CI we need.

## Decision

**npm workspaces.** No second package manager, no build orchestrator. Thirteen packages under
`packages/`, published as `@evok-node/<name>`; `rig` is `private: true` and never published (RC-11).
Builds are `tsc -b` over the root `tsconfig.json`'s project references.

**The consequence that matters, and the reason this is an ADR rather than a preference:** npm
workspaces give every package a flat `node_modules`, so an import a package never declared resolves
anyway. `tsc -b` does not close the hole either — a cross-package import with no project reference
builds green as long as the target's `dist/` exists, which it does after any earlier build (verified
empirically; see the comment at the top of `.dependency-cruiser.cjs`). So **`dependency-cruiser` is
load-bearing, not a nicety**: without it RC-10 is unenforceable and ADR-0011 is aspirational. The DAG
is stated once, in that file, which also asserts each `package.json` agrees with it.

## Consequences

Makes easy: one lockfile, `npm ci` in CI, no tool a contributor or an OS image has to acquire, and
scoped names that let a plugin driver publish under our namespace later (ADR-0014, RC-30).

Makes hard: no task graph and no remote cache, so CI rebuilds and retests everything on every PR.
Acceptable at thirteen packages this size; revisit only if build time becomes the constraint, not
because a faster tool exists. And the flat-`node_modules` hole is permanent — we pay for it with a
config file that must never be weakened (RG-9).

**Rejected: pnpm,** whose strict linking would close that hole at the source. Rejected because
`dependency-cruiser` is wanted regardless: strict linking enforces *declared* edges, not the DAG's
*direction*, so it would not catch a driver importing an API that it also declared, nor RC-11, nor
ADR-0007's exclusion. Adding a tool to get a partial version of a guard we still have to write is a
net loss.

**Rejected: nx or turborepo.** Build orchestration for a build that takes seconds, and both would put
a cache layer between an agent and the failure it is trying to reproduce.

**Rejected: unscoped names** (`evok-node-modbus`). It squats generic names one at a time, gives no way
to reserve the namespace, and makes "is this ours?" a prefix convention rather than a fact npm
enforces — which is also what the scope check in `.dependency-cruiser.cjs` relies on.

**Rejected: one package.** It is the honest alternative for a project this size, and it is refused for
one reason: the failure this project exists to prevent is a boundary being crossed quietly, and a
single package has no boundaries to check.
