# evok-node

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a
load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; this project exists
to fix them. The interface is inherited; the design is not.

**Status: pre-implementation.** The workspace builds and the test harness runs, and that is all —
every package entrypoint is a placeholder. There is nothing to install and no usage example yet, and
there will not be a usage section here until there is something behind it. See
[`docs/plan/STATUS.md`](docs/plan/STATUS.md) for where the work actually is.

## Working in this repository

```bash
npm install
npm run build     # tsc -b across all packages, in reference order
npm run lint      # eslint, type-checked config
npm run layering  # dependency-cruiser: the package DAG. Needs a build first
npm test          # vitest, tier 0 only
```

These are the same checks the `pr` workflow runs, one job each; M0 T0.8 collapses them into a single
`npm run verify` so that local green means CI green. `npm run layering` needs `dist/` to exist,
because workspace imports resolve through `node_modules`.

Requires Node 24 — declared once, in the root `package.json` `engines.node`, which is also where CI
reads it from. `npm run coverage` reports per-package coverage; the per-module floors from the
[testing rules](docs/rules/testing.md) are wired in `vitest.config.ts` behind a single switch and are
off until there is something to cover.

## Packages

| Package | Purpose |
|---|---|
| [`protocol`](packages/protocol) | wire schemas and the core↔API message contract |
| [`modbus`](packages/modbus) | transport: framing, correlation, timing, circuit breakers |
| [`hw-definitions`](packages/hw-definitions) | model descriptors, overlays, generated address tables |
| [`core`](packages/core) | registry, device model, scheduler, aliases. No API dependency |
| [`server`](packages/server) | fastify adapters for every EVOK surface. The daemon |
| [`client`](packages/client) | first-party TypeScript client |
| [`simulator`](packages/simulator) | Modbus slave simulator generated from the register-map corpus |
| [`inspector`](packages/inspector) | web UI, over the public API only |
| [`rig`](packages/rig) | hardware-rig control service. Private, sysfs only |

Each package's README states what it **must not** depend on. Those constraints are the design, not
documentation of it.

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — how to work here: read order, precedence, how rules are cited. Start
  here. It holds no rules itself.
- [`docs/GOALS.md`](docs/GOALS.md) — goals, non-goals, invariants (**G-N**), what 1.0 is. Wins over
  everything else.
- [`docs/rules/`](docs/rules/code.md) — the binding rules: code (**RC**), testing (**RT**), docs
  (**RD**), git (**RG**).
- [`docs/plan/`](docs/plan/README.md) — what happens next (**RP**) ·
  [`docs/adr/`](docs/adr/README.md) — why we decided (**A-NNNN**) ·
  [`docs/research/`](docs/research/) — what is true about EVOK and Unipi hardware.

Licence not yet chosen — M0 task T0.6, with an ADR recording the choice.
