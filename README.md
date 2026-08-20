# evok-node

A Node.js/TypeScript drop-in replacement for Unipi Technology's **EVOK 3.x** API. EVOK is a load-bearing part of Unipi's FOSS stack with a long tail of open, known defects; this project exists to fix them. The interface is inherited; the design is not.

Main features:
* EVOK 3 full compatibility API
* Flexible and extendible by plugins
* Strong on driver and API separation
* Rich web UI with inspector and device status and logs

## Unipi devices user and administrators

TBD - link to user docu

## Developers

TBD - link to dev docu



## Working in this repository

```bash
npm install
npm run build     # tsc -b across all packages, in reference order
npm run lint      # eslint, type-checked config
npm run layering  # dependency-cruiser: the package DAG. Needs a build first
npm test          # vitest, tier 0 only
```

These are the same checks the `pr` workflow runs, one job each. A single `npm run verify` that collapses
them, so local green means CI green, is still outstanding — see
[`STATUS.md`](docs/plan/STATUS.md). `npm run layering` needs `dist/` to exist, because workspace imports
resolve through `node_modules`.

Requires Node 24 — declared once, in the root `package.json` `engines.node`, which is also where CI
reads it from. `npm run coverage` reports per-package coverage; the per-module floors from the
[testing rules](docs/rules/testing.md) are wired in `vitest.config.ts` behind a single switch and are
off until there is something to cover.

## Packages

Two layers — **drivers act, APIs query** — with `main` orchestrating and sitting on no request path.
Anything that looks like a third kind of component is a driver whose transport is not Modbus.

| Package | Purpose |
|---|---|
| [`messaging`](packages/messaging) | the internal driver↔API contract: envelopes, introspection schemas, codecs, deadlines |
| [`hw-definitions`](packages/hw-definitions) | our hardware definitions, model descriptors, generated address tables |
| [`modbus`](packages/modbus) | transport: framing, correlation, timing, circuit breakers |
| [`main`](packages/main) | the daemon: config, validation, spawn, supervise, reload |
| [`driver-kit`](packages/driver-kit) | shared driver runtime: scan loop, reading state, handshake, introspection |
| [`driver-onboard`](packages/driver-onboard) | the controller's own I/O sections, over Modbus TCP |
| [`driver-extension`](packages/driver-extension) | Unipi RTU extensions, one instance per RS-485 line |
| [`api-nextgen`](packages/api-nextgen) | our WebSocket + HTTP surface. Owns its public schema |
| [`api-compat`](packages/api-compat) | the EVOK 3.x surface. Owns the projection table |
| [`simulator`](packages/simulator) | Modbus slave simulator generated from the register-map corpus |
| [`client`](packages/client) | first-party TypeScript client |
| [`ui`](packages/ui) | the web SPA, over the public API only |
| [`rig`](packages/rig) | hardware-rig control service. Private, sysfs only |

Each package's README states what it **must not** depend on. Those constraints are the design, not
documentation of it — and they are enforced from a single table in `.dependency-cruiser.cjs`.

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — how to work here: workflow and package layout. Start here. It holds no
  rules itself.
- [`docs/README.md`](docs/README.md) — the map: what exists, in what order to read it, how rules are
  cited, and which document wins.
- [`docs/GOALS.md`](docs/GOALS.md) — goals, non-goals, invariants (**G-N**), what 1.0 is. Wins over
  everything else.
- [`docs/rules/`](docs/rules/code.md) — the binding rules: code (**RCD**), packages (**RPG-\***),
  testing (**RT**), docs (**RD**), git (**RG**).
- [`docs/dev/`](docs/dev/README.md) — **the design, and what implementation is written against.**
  Start at [`00-Intro.md`](docs/dev/00-Intro.md).
- [`docs/plan/`](docs/plan/README.md) — what happens next (**RPL**) ·
  [`docs/research/`](docs/research/README.md) — what is true about EVOK and Unipi hardware, plus the
  [dissolved ADR set](docs/research/to_revision/README.md), kept as proposals.

Licence not yet chosen.

