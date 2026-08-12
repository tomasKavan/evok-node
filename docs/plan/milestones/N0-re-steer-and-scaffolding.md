# N0 — Re-steer & scaffolding

*Was M0. Renamed and partly rewritten 2026-08-12 for ADR-0008 — the shape the scaffolding targets
changed, so T0.1 and T0.3 had to change with it. T0.2 and T0.4–T0.8 are untouched in substance.*

**Goal:** a repository an agent can work in without being able to break the invariants by
accident, in the shape ADR-0008 settled.

**Exit criteria:** `npm run verify` passes from a clean clone; CI runs tier 0 on every PR; a
deliberate layering violation and a deliberate `any` both fail the build; ADRs exist for every
settled decision.

---

### T0.1 — Workspace skeleton `area/ci` `risk/normal`

npm workspaces with the thirteen packages from `CLAUDE.md` §Layout. Each has `package.json`,
`tsconfig.json` extending a shared base, and a README stating its purpose and what it must not depend
on. Scoped `@evok-node/*`; `rig` is `private: true` and never published.

**Reworked 2026-08-12.** `core`, `server`, `protocol` and `inspector` are gone; `messaging`, `main`,
`driver-kit`, `driver-onboard`, `driver-extension`, `api-nextgen`, `api-compat` and `ui` are new.
Cheap to do now precisely because every entrypoint was still a placeholder export — the same change
after N3 would not have been.

**Done when:** `npm install && npm run build` succeeds from a clean clone; every package builds to
`dist/` with declarations; no package has a dependency it doesn't declare. ✅ *2026-08-12.*

---

### T0.2 — TypeScript configuration `area/ci` `risk/normal`

Shared strict base: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`,
`noImplicitOverride`, `noFallthroughCasesInSwitch`, `isolatedDeclarations`. ES2023 target, NodeNext
modules, Node 24 types.

**Done when:** a test fixture containing an unchecked index access and a missing switch case both
fail `tsc`.

---

### T0.3 — Lint and layering `area/ci` `risk/high`

eslint with the type-checked `@typescript-eslint` config. Banned: `any`, `as` (outside generated
code), non-null `!`, floating promises, `Date.now()` outside logging, `process.env` outside the
config module, barrel files outside package entrypoints.

**`dependency-cruiser` is the load-bearing piece** — we chose npm workspaces, whose flat
`node_modules` will happily resolve an undeclared import, so nothing else prevents a driver from
importing an api, or `main` from importing either. Rules are generated from one table: the layering
DAG in `.dependency-cruiser.cjs`, mirrored in `CLAUDE.md` §Layout; no cycles; `rig` imports nothing of
ours (RC-11); `simulator` excludes `modbus` (ADR-0007).

**Rewritten 2026-08-12** for RC-10's new form. It is now a *partition* — no driver imports an api and
no api imports a driver — rather than the old one-directional `core`↛`server` rule, and `main`'s
absence of any static edge to a concrete driver or api is what makes ADR-0011 enforceable rather than
aspirational.

**Done when:** each of these fails CI in a scratch commit that is then reverted — an import from
`driver-onboard` to `api-compat`, an import from `api-nextgen` to `driver-kit`, an import from `main`
to any concrete driver, an import from `rig` to anything of ours, a bare `any`, a floating promise.
Record the scratch-commit SHAs in the PR body as evidence the guards actually fire.

---

### T0.4 — Test harness `area/ci` `risk/normal`

vitest in workspace mode, one project per package. Coverage reporting with the per-module floors
from [testing rules](../../rules/testing.md) wired but not yet enforced (nothing to cover yet).
`fixtures/` directories created with README files stating the read-only rule.

**Done when:** `npm test` runs across all packages in under 10 s with zero tests, and the fixture
directories are `.prettierignore`d and listed in `CODEOWNERS`.

---

### T0.5 — CI workflows `area/ci` `risk/normal`

The `pr` and `main` workflows from [git rules](../../rules/git.md). Skeleton only for `hardware`, `nightly`,
`release` — registered but no-op until there is something to run.

**Done when:** a PR shows the `pr` workflow green; `main` has required checks configured; branch
protection is on with 1 required approval and linear history.

---

### T0.6 — Repo hygiene `area/ci` `risk/normal`

`CODEOWNERS` (fixtures and `docs/research/` to Tomas), PR template with the checklist,
issue templates for `feat`/`bug`/`spike` that force the `agent-ready` fields, commitlint,
changesets, prettier, `.editorconfig`, MIT or Apache-2.0 licence (note: upstream EVOK is
Apache-2.0 — we share no code, so we are unconstrained, but state the choice in an ADR).

**Done when:** a non-conventional commit message is rejected locally and in CI; opening an issue
offers the templates.

---

### T0.7 — ADRs from settled research decisions `area/ci` `risk/normal`

One ADR per decision already made, dated and referencing the research section that justifies it. The
list is the "Awaiting write-up" table in [`../../adr/README.md`](../../adr/README.md), which is
authoritative: twelve decisions, from EVOK 3.x-only scope through the licence choice.

**Numbers are allocated on write, not reserved** — each of those takes the next free number as it is
written, continuing from **0013**. ADRs 0001–0006 already exist (goals consolidation, 2026-08-10),
0007 is the simulator's framer (written with T0.3), and 0008–0012 are the re-steer (2026-08-12).
None are part of this task.

**Two of the twelve need rereading against ADR-0008 before they are written up**, rather than
transcribed: "library first, service second" (research/05 §7.2) now means a driver or an api package
rather than `core`, and "nginx remains the `:80` front end" (research/07 §5) meets the decision that
`api-nextgen` serves `ui` at `/` itself.

**Done when:** `docs/adr/` contains one file per decision, each with Context / Decision /
Consequences and a link to the research section. These exist so an agent does not re-derive them
from first principles and quietly choose differently.

---

### T0.8 — `npm run verify` `area/ci` `risk/normal`

One command an agent runs before committing: format check, lint, typecheck, dependency-cruiser,
tests, fixture-drift. Must be the same set CI runs on a PR, so local green means CI green.

**Done when:** it exists, is documented in the root README, and matches the `pr` workflow exactly.
