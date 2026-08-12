# ADR-0013 — npm workspaces, scoped `@evok-node/*` names, Node 24 and fastify

- **Status:** Accepted
- **Date:** 2026-08-12
- **Refs:** docs/research/05-evok-node-design-notes.md §8.6, §8.11, §2.2 ·
  docs/research/12-modularisation.md §Package layout ·
  docs/plan/milestones/N0-re-steer-and-scaffolding.md T0.1, T0.3 · RC-10, RC-11, RC-12, RC-22 ·
  ADR-0001, ADR-0005, ADR-0006, ADR-0011

## Context

Three dependency choices with long half-lives and no cheap reversal: the monorepo tool, the runtime floor
that packaging and every API depend on, and the HTTP framework the shape of our route and validation code
depends on. The design is many small packages with a layering DAG that has to be *enforced*, not merely
drawn — RC-10's partition, RC-11's isolated rig, ADR-0011's simulator exclusion.

## Decision

**npm workspaces.** No second package manager, no build orchestrator. Thirteen packages under
`packages/`, published as `@evok-node/<name>`; `rig` is `private: true` and never published (RC-11).
Builds are `tsc -b` over the root `tsconfig.json`'s project references.

**The consequence that makes this an ADR rather than a preference:** npm workspaces give every package a
flat `node_modules`, so an import a package never declared resolves anyway. `tsc -b` does not close the
hole either — a cross-package import with no project reference builds green as long as the target's
`dist/` exists, which it does after any earlier build (verified empirically; see the comment at the top of
`.dependency-cruiser.cjs`). So **`dependency-cruiser` is load-bearing, not a nicety**: without it RC-10 is
unenforceable and ADR-0001's "nothing imports `main`" is aspirational. The DAG is stated once, in that
file, which also asserts each `package.json` agrees with it.

**Node 24.** Active LTS as of July 2026, EOL 2028-04-30. Keep the code 26-clean and use nothing that would
block a 26 bump; 22 is already in maintenance.

**fastify** in every package that serves HTTP. Its JSON-Schema-first design maps almost 1:1 onto EVOK's own
`schemas.py` — upstream's POST validation *is* JSON Schema — so compat validation transcribes rather than
being re-derived, and schema-driven serialisation suits a fan-out path. Our parse boundary is zod (RC-12)
with `z.toJSONSchema()` feeding fastify's routes, so each schema is written once, in the API package that
owns that surface.

## Consequences

Makes easy: one lockfile, `npm ci` in CI, no tool a contributor or an OS image has to acquire, and scoped
names that let a plugin driver publish under our namespace later (RC-30). `node:sqlite` without a flag,
which is what makes ADR-0005's store a dependency-free choice. And transcribing compat's request validation
from upstream instead of inventing it.

Makes hard: no task graph and no remote cache, so CI rebuilds and retests everything on every PR.
Acceptable at thirteen packages this size; revisit only if build time becomes the constraint, not because a
faster tool exists. The flat-`node_modules` hole is permanent — we pay for it with a config file that must
never be weakened (RG-9). And **neither Debian generation we support ships Node 24**, so packaging must
declare a runtime source or bundle one; that is an ADR-0006 item on the same capture-trip list, since we
need to know what evok's own packaging depends on before writing our `Depends:`.

**Rejected:**

- **pnpm,** whose strict linking would close the flat-`node_modules` hole at source. Rejected because
  `dependency-cruiser` is wanted regardless: strict linking enforces *declared* edges, not the DAG's
  *direction*, so it would not catch a driver importing an API it also declared, nor RC-11, nor ADR-0011's
  exclusion. Adding a tool for a partial version of a guard we still have to write is a net loss.
- **nx or turborepo** — build orchestration for a build that takes seconds, and both put a cache layer
  between an agent and the failure it is trying to reproduce.
- **Unscoped names** (`evok-node-modbus`) — squats generic names one at a time, gives no way to reserve the
  namespace, and makes "is this ours?" a prefix convention rather than a fact npm enforces, which is also
  what the scope check in `.dependency-cruiser.cjs` relies on.
- **One package.** The honest alternative for a project this size, refused for one reason: the failure this
  project exists to prevent is a boundary being crossed quietly, and a single package has no boundaries to
  check.
- **`node:http` plus a small router,** held open in research/05 §2.2 on install-footprint grounds for a
  1 GB Neuron. The footprint argument did not survive contact with the work it saves: hand-rolled routing
  and validation is exactly where a compat shape bug would live, and fastify's tree is small next to
  `serialport` and the definition corpus.
- **express** — no schema-first story, so validation and serialisation are hand-written, and its
  serialisation is slower on the one path where we fan out to N WebSocket clients.
- **Node 22** (maintenance — the floor would need raising inside 1.0's life) and **Node 26** (not LTS until
  October 2026, so it would ship a non-LTS runtime to industrial controllers).
- **Supporting a range of Node majors** — one runtime is one test matrix. Packaging pins it; an embedder
  consuming the libraries (ADR-0001) may be ahead of us but not behind.
