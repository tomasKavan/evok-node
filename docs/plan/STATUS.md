# Status

**Updated:** 2026-08-10 · **Milestone:** M0 — scaffolding · **Version:** unreleased

## Where we are

Research is complete and lives in [`docs/research/`](../research/). Goals and non-goals are now
settled in [`docs/GOALS.md`](../GOALS.md). The workspace skeleton now builds and tests, with nine
empty packages behind a strict TypeScript base. **No implementation code exists yet** — every
package's entrypoint is a placeholder export.

## Done

- Research: EVOK 3.x API surface, Unipi hardware model, config and hw-definition formats,
  upstream bug archaeology (29 condensed findings, ~90 raw), client compatibility matrix, latency
  budget, test-kit design, register-map corpus imported and indexed.
- Decisions settled and recorded: see [`../adr/`](../adr/) and
  [`../research/05-evok-node-design-notes.md`](../research/05-evok-node-design-notes.md) §7–§8.
- Working rules: [code](../rules/code.md), [testing](../rules/testing.md),
  [docs](../rules/docs.md), [git](../rules/git.md).
- **Goals consolidated (2026-08-10).** [`GOALS.md`](../GOALS.md) is authoritative: the goal, the
  measurable form of it, what 1.0 is, post-1.0 direction, seven invariants, the drop-in guarantee,
  non-goals. Six new ADRs (0001–0006) record the decisions behind it. Scattered goal statements in
  research files carry dated superseded-by notes.
- **M0 T0.1, T0.2, T0.4 (2026-08-10).** npm workspaces with the nine `@evok-node/*` packages, each
  with a README naming what it must not depend on; shared strict TS base with the six T0.2 flags,
  ES2023/NodeNext/Node 24, build order carried by project references; vitest in workspace mode, one
  project per package, coverage floors wired and switched off. `fixtures/` created,
  `.prettierignore`d, fixture directories in `CODEOWNERS`.

## In progress

- **M0 — scaffolding.** Remaining: **T0.3** eslint + dependency-cruiser (the load-bearing layering
  guard — nothing yet stops `core` importing `server`), **T0.5** CI workflows, **T0.6** repo hygiene
  and the licence choice, **T0.7** ADRs for the twelve settled decisions, **T0.8** `npm run verify`.

## Next

- **M1 — generated fixtures and simulator.** The map-corpus parser, generated address tables, the
  Modbus slave simulator, codec golden tables. Highest-leverage work in the project: it is the
  permanent substitute for hardware we can no longer buy.

## Blocked / waiting on hardware

| Item | Waiting on |
|---|---|
| Golden transcript capture | **Human task, time-sensitive.** Must be recorded from stock EVOK 3.0.6 on L527/M527/S167 *before* anything replaces EVOK on those units. Unrecoverable afterwards. |
| Stock `hw_definitions` + `autogen.yaml` + firmware versions | Same trip as the transcript capture. |
| Stock `config.yaml` + `/var/lib/evok/alias.yaml` | Same trip. These are the migration tool's golden fixtures (ADR-0003). |
| evok packaging metadata — `apt-cache show evok`, `dpkg -L evok`, systemd unit names, its nginx site file | Same trip. Decides the `Conflicts:`/`Depends:` list in ADR-0002 and how the `:80` site conflict is handled. **Do not `apt purge evok` before migrating** — purge destroys the fixtures above. |
| `start_index` old-behaviour baseline | **Same trip, and easy to forget.** Finding 1.1's `test` disposition needs a transcript of stock EVOK mis-registering a deliberately split RO definition (two blocks of 7 with `start_index`) on the L527's section 3. After `Conflicts: evok` this requires reinstalling EVOK on a unit; capture it while it is already there. |
| Second Patron M527 as rig test host | Purchase, not a trip. Named in research/10 but missing from the roadmap's purchase track until now. Blocks all tier-1 hardware tests. |
| Tier-1 hardware tests | Rig not built. Needs a second Patron M527 as test host, wiring, `rig` service. |
| RS485 baud-encoding, DirectSwitch write path, unit-0 aggregate reads | Verification on hardware. See [research/05](../research/05-evok-node-design-notes.md) §7.4. |
| Neuron and Unipi 1.1 support | Hardware not yet purchased. Map-driven and simulator-verified until then. |

## Known permanent gaps

- **No purchasable Unipi device has >16 channels of one type in a single section**, so the
  *missing-bank-stride* half of the highest-severity bug class (silently driving the wrong relay) can
  never be verified on hardware. Mitigated by generated address tables plus a
  fatal-on-duplicate-registration assertion. The `start_index` half **is** reproducible on the L527's
  section 3 via a deliberately split definition and the RO→DI loopback. See
  [research/10 §4](../research/10-test-kit.md) and
  [`bug-dispositions.md`](bug-dispositions.md) finding 1.1.

## Open questions

1. Which extension models are actually on hand (an xS51 is the top purchase).
2. Which Debian generation each Patron runs — ideally one on 12 and one on 13.
3. `node:sqlite` stability on the Node 24 minor we pin — it is available without a flag but is a
   release candidate, not fully stable. Fallback is `better-sqlite3`, which needs armhf/arm64
   prebuilds. See ADR-0005.
4. Deferred by design, listed so they are not mistaken for oversights: trigger-engine fail-safe
   semantics, the admin-surface authentication mechanism, and the plugin isolation model. See
   [`GOALS.md`](../GOALS.md) §Open.
5. **Two workspace dependency edges are deliberately undeclared** (T0.1), because declaring one
   wrongly is what `dependency-cruiser` then enforces:
   - `simulator → modbus`. May the simulator reuse our framer, or must it have its own? `CLAUDE.md`
     rule 2 forbids exactly this sharing for `rig` — "the instrument must not share code with what it
     measures" — and the simulator is the instrument for every transport test we can run without
     hardware. Decide before M1.
   - `inspector → client`. T0.3 says `client` and `inspector` depend only on `protocol`, but the
     obvious implementation of `inspector` is a consumer of our own client. Either the rule means
     "no `core`, no `server`" and `client` is allowed, or `inspector` re-implements the calls.
     Decide before `inspector` starts, after M4.
6. **`typescript` is pinned to `~6.0.3`, not the current `latest` (7.0.2).** `typescript-eslint`
   declares `typescript >=4.8.4 <6.1.0`, so T0.3's type-checked lint config — the load-bearing
   layering and no-`any` guard — cannot run on TS 7. The pin is a `~` range on purpose: `^6.0.3`
   would silently allow 6.1 and break lint. Revisit when `typescript-eslint` supports the native
   compiler.
7. **[`rules/code.md`](../rules/code.md) §Types overstates one flag** and should be corrected by one
   line. It says a `switch` with no `default` plus `noFallthroughCasesInSwitch` makes a missed case a
   compile error. It does not: `noFallthroughCasesInSwitch` reports fallthrough (TS7029). What
   catches a *missing* case is a declared return type with no `default` under `noImplicitReturns`
   (TS2366), or an exhaustiveness assignment to `never`. Both are demonstrated in T0.2's verification
   and `noImplicitReturns` is in the shared base because of it.
