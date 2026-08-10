# Status

**Updated:** 2026-08-10 · **Milestone:** M0 — scaffolding · **Version:** unreleased

## Where we are

Research is complete and lives in [`docs/research/`](../research/). Goals and non-goals are now
settled in [`docs/GOALS.md`](../GOALS.md). Project governance (rules, plan structure, ADRs) is being
set up now. **No implementation code exists yet, and the repository has no commits.**

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
  non-goals. Six new ADRs (0013–0018) record the decisions behind it. Scattered goal statements in
  research files carry dated superseded-by notes.

## In progress

- **M0 — scaffolding.** Repo layout, npm workspaces, strict TS, eslint + dependency-cruiser,
  vitest, CI skeleton, ADRs written up from the research decisions.

## Next

- **M1 — generated fixtures and simulator.** The map-corpus parser, generated address tables, the
  Modbus slave simulator, codec golden tables. Highest-leverage work in the project: it is the
  permanent substitute for hardware we can no longer buy.

## Blocked / waiting on hardware

| Item | Waiting on |
|---|---|
| Golden transcript capture | **Human task, time-sensitive.** Must be recorded from stock EVOK 3.0.6 on L527/M527/S167 *before* anything replaces EVOK on those units. Unrecoverable afterwards. |
| Stock `hw_definitions` + `autogen.yaml` + firmware versions | Same trip as the transcript capture. |
| Stock `config.yaml` + `/var/lib/evok/alias.yaml` | Same trip. These are the migration tool's golden fixtures (ADR-0015). |
| evok packaging metadata — `apt-cache show evok`, `dpkg -L evok`, systemd unit names, its nginx site file | Same trip. Decides the `Conflicts:`/`Depends:` list in ADR-0014 and how the `:80` site conflict is handled. **Do not `apt purge evok` before migrating** — purge destroys the fixtures above. |
| Tier-1 hardware tests | Rig not built. Needs a second Patron M527 as test host, wiring, `rig` service. |
| RS485 baud-encoding, DirectSwitch write path, unit-0 aggregate reads | Verification on hardware. See [research/05](../research/05-evok-node-design-notes.md) §7.4. |
| Neuron and Unipi 1.1 support | Hardware not yet purchased. Map-driven and simulator-verified until then. |

## Known permanent gaps

- **No purchasable Unipi device has >16 channels of one type**, so the highest-severity bug class
  (silently driving the wrong relay) can never be verified on hardware. Mitigated by generated
  address tables plus a fatal-on-duplicate-registration assertion. See
  [research/10 §4](../research/10-test-kit.md).

## Open questions

1. Which extension models are actually on hand (an xS51 is the top purchase).
2. Which Debian generation each Patron runs — ideally one on 12 and one on 13.
3. `node:sqlite` stability on the Node 24 minor we pin — it is available without a flag but is a
   release candidate, not fully stable. Fallback is `better-sqlite3`, which needs armhf/arm64
   prebuilds. See ADR-0017.
4. Deferred by design, listed so they are not mistaken for oversights: trigger-engine fail-safe
   semantics, the admin-surface authentication mechanism, and the plugin isolation model. See
   [`GOALS.md`](../GOALS.md) §Open.
