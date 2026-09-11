# Status

**Updated:** 2026-08-23 · **Milestone:** [M3 — development documentation](roadmap.md) ·
**Version:** unreleased

!! Present state only. What changed and when is what git is for; milestone sequence is in [`roadmap.md`](roadmap.md).

**No implementation code exists.** Every package entrypoint is a placeholder export.

## Done

**M1 — Research.** [`docs/dev/research/`](docs/dev/research/README.md) is the knowledge base: EVOK 3.x API surface, Unipi hardware model, config and hw-definition formats, upstream bug archaeology (29 condensed findings from ~90 raw), client compatibility matrix, latency budget, test-kit design, and the register-map corpus imported and indexed under [`docs/modbus-reg-map/`](../modbus-reg-map/README.md). [Goals](/docs/dev/design/evok-node/README.md) is authoritative on scope.

**M2 — Repo scaffolding.** npm workspaces over thirteen packages; a shared strict TS base; vitest in workspace mode with coverage floors wired and switched off; `pr` and `main` CI workflows with actions pinned by SHA; eslint with the type-checked config; `dependency-cruiser` carrying the layering DAG. `npm run build`, `test`, `lint` and `layering` each exit 0 — 27 modules, 13 edges, no violations.

## In progress

**M3 — development documentation.** [`docs/dev/design`](/docs/dev/README.md), sections 2 - 6. 
- Root README.md is finalized, TBD at URLs which is uknown at the moment.
- Dev docs README.md is finalized. Documentaiton has rules.
- AGENTS.md has generic rules and some roles defined, but some role's reading paths and instructions for specific roles are yet TBD.

## Next

**Not yet defined.** M3 defines it (RPL-4). No milestone numbers past M3 exist, and none should be
invented.
