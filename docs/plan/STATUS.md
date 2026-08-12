# Status

**Updated:** 2026-08-12 · **Milestone:** N0 — re-steer & scaffolding · **Version:** unreleased

## Where we are

Research is complete and lives in [`docs/research/`](../research/). Goals are settled in
[`docs/GOALS.md`](../GOALS.md). **The architecture was re-steered on 2026-08-12** — see
[research/12](../research/12-modularisation.md) and ADRs 0008–0012 — and the workspace skeleton has
been rebuilt in the new shape: thirteen packages, building, linting and cruising clean. **No
implementation code exists yet**; every package's entrypoint is a placeholder export.

## The re-steer, in one paragraph

The goal and the definition of 1.0 are unchanged: compatibility complete, every bug disposition
closed. What changed is the path. `core` and `server` dissolved into **drivers** — each owning one
transport endpoint and holding the only copy of its state — and **APIs**, which are stateless
translators, orchestrated by a `main` that sits on no request path. The compat surface moves from the
second milestone to the last: only 7 of the 29 findings depend on it, and three of those are
surface-agnostic mechanisms that get built correctly in the nextgen API first. What protects the model
from being shaped by EVOK is architectural (G-3, RC-24); the ordering is the second line of defence.

## Done

- Research: EVOK 3.x API surface, Unipi hardware model, config and hw-definition formats,
  upstream bug archaeology (29 condensed findings, ~90 raw), client compatibility matrix, latency
  budget, test-kit design, register-map corpus imported and indexed.
- **Goals consolidated (2026-08-10).** [`GOALS.md`](../GOALS.md) is authoritative: the goal, the
  measurable form of it, what 1.0 is, post-1.0 direction, seven invariants, the drop-in guarantee,
  non-goals. ADRs 0001–0006 record the decisions behind it.
- **T0.1–T0.5 (2026-08-10).** npm workspaces, a shared strict TS base with the six T0.2 flags,
  vitest in workspace mode with coverage floors wired and switched off, `pr` and `main` CI workflows
  with actions pinned by SHA, eslint with the type-checked config, and `dependency-cruiser` carrying
  the layering DAG.
- **Re-steer landed (2026-08-12).** ADRs [0008](../adr/0008-drivers-apis-and-main.md),
  [0009](../adr/0009-driver-qualified-addressing.md),
  [0010](../adr/0010-introspection-is-the-source-of-truth.md),
  [0011](../adr/0011-main-is-never-in-the-data-path.md) and
  [0012](../adr/0012-single-threaded.md) written; ADR-0001 amended (generalised, not superseded) and
  ADR-0006 annotated. `roadmap.md` restructured to N0–N10, `bug-dispositions.md` milestones remapped,
  six rules rewritten and seven appended (RC-26…RC-32), `CLAUDE.md` §Layout replaced.
- **Skeleton reworked (2026-08-12).** Thirteen packages: `core`, `server`, `protocol` and
  `inspector` removed; `messaging`, `main`, `driver-kit`, `driver-onboard`, `driver-extension`,
  `api-nextgen`, `api-compat` and `ui` added. Root `tsconfig.json` references, the
  `dependency-cruiser` DAG, vitest projects and coverage floors all follow. `npm run build`, `test`,
  `lint` and `layering` each exit 0; 27 modules and 13 edges cruised with no violations.
- **T0.7 ADRs written (2026-08-12).** [0013](../adr/0013-evok-3x-sole-compatibility-target.md)–[0023](../adr/0023-generated-address-tables-primary-safeguard.md):
  the eleven settled-but-undocumented decisions from the ADR README's "Awaiting write-up" table.
  Two were reread against ADR-0008 rather than transcribed — 0014 (library first, restated without
  `core`) and 0017 (nginx narrowed to the compat surface, since `api-nextgen` serves the SPA at its
  own `/`). None of the eleven had to be left unwritten. Only the licence row remains, and it belongs
  to T0.6.

## In progress

- **N0 — re-steer & scaffolding.** Remaining: **T0.6** repo hygiene and the licence choice, and
  **T0.8** `npm run verify`. T0.7 is done — ADRs 0013–0023, above. The licence ADR is T0.6's, because
  the choice between MIT and Apache-2.0 has not been made.
- **Four of the `pr` workflow's eight checks are still placeholders** — `format` and `changeset`
  until T0.6, `fixture-drift` until N1, and `coverage` runs but enforces nothing until there is
  something to cover. Each prints a warning annotation saying so.
- **Branch protection is not yet configured** — Tomas's to set. Until it is, T0.5's exit criteria
  are only half met: the workflows run, but nothing requires them to be green.

## Next

- **N1 — generated fixtures and simulator.** The map-corpus parser, generated address tables, the
  Modbus slave simulator, codec golden tables. Still the highest-leverage work in the project, and
  still ahead of every driver: it is the only substrate a driver can be tested against.

## Blocked / waiting on hardware

**The capture trip is scheduled for the week of 2026-08-10, and all three Patrons are confirmed
still stock.** Demoting the compat surface to N9 does **not** defer this — the transcripts are
unrecoverable once EVOK leaves those Patrons; they are simply consumed later. Runbook:
[`capture-trip.md`](capture-trip.md).

| Item | Waiting on |
|---|---|
| Golden transcript capture | **Human task, time-sensitive.** Must be recorded from stock EVOK 3.0.6 on L527/M527/S167 — **and the Gate, if it still runs stock EVOK**, since research/09 §2 makes the zero-local-I/O payload a named requirement — *before* anything replaces EVOK on those units. Unrecoverable afterwards. Runbook phases 1, 3, 4. |
| **Gate behaviour with no onboard driver** | Same trip, and newly load-bearing: `api-compat` requires **at most one** onboard driver, and zero is the Gate, which must serve an empty API rather than erroring. research/09 records that EVOK's own `readboards()` and `/rest/all` "degrade oddly" here, so the compat shape must be captured rather than inferred. |
| Stock `hw_definitions` + `autogen.yaml` + firmware versions | Same trip as the transcript capture. Runbook phase 1. |
| Stock `config.yaml` + `/var/lib/evok/alias.yaml` | Same trip. These are the migration tool's golden fixtures (ADR-0003). Runbook phase 1. |
| evok packaging metadata — `apt-cache show evok`, `dpkg -L evok`, systemd unit names, its nginx site file | Same trip. Decides the `Conflicts:`/`Depends:` list in ADR-0002 and how the `:80` site conflict is handled. **Do not `apt purge evok` before migrating** — purge destroys the fixtures above. Runbook phase 1. |
| `start_index` old-behaviour baseline | **Same trip, and easy to forget.** Finding 1.1's `test` disposition needs a transcript of stock EVOK mis-registering a deliberately split RO definition (two blocks of 7 with `start_index`) on the L527's section 3. Runbook phase 5. |
| Second Patron M527 as rig test host | **Purchase approved 2026-08-10, not yet ordered.** Blocks all tier-1 hardware tests. **Image it with Debian 12** — see open question 3. |
| xS51 extension | **Purchase approved 2026-08-10, not yet ordered.** AI/AO over RTU (float32 AI, raw-count AO, 6-mode enum on an extension) is otherwise only reachable via the local TCP path. |
| Tier-1 hardware tests | Rig not built. Needs the second Patron M527 as test host, wiring, `rig` service. Runs as a parallel track and gates no milestone (RP-7). |
| RS485 baud-encoding, DirectSwitch write path, unit-0 aggregate reads, register 1007 semantics | Verification on hardware. See [research/05](../research/05-evok-node-design-notes.md) §7.4. Partly answerable on the capture trip — runbook phase 6. |
| Neuron and Unipi 1.1 support | Hardware not yet purchased. Map-driven and simulator-verified until then. When a Neuron is bought, buy an **L203**. |

## Known permanent gaps

- **No purchasable Unipi device has >16 channels of one type in a single section**, so the
  *missing-bank-stride* half of the highest-severity bug class (silently driving the wrong relay) can
  never be verified on hardware. Mitigated by generated address tables plus a
  fatal-on-duplicate-registration assertion (RC-18). The `start_index` half **is** reproducible on the
  L527's section 3 via a deliberately split definition and the RO→DI loopback. See
  [research/10 §4](../research/10-test-kit.md) and
  [`bug-dispositions.md`](bug-dispositions.md) finding 1.1.

## Open questions

1. **G-7's `unipitcp` clause — Tomas's decision, and the one open item with a deadline.** G-7 refused
   to start when `unipitcp` was active, but local I/O *is* Modbus TCP to `unipitcp` on
   `127.0.0.1:502` ([raw-hardware-research §166](../research/appendix/raw-hardware-research.md), Unipi
   KB `en:sw:02-apis:02-modbus-tcp`), so `driver-onboard` requires it running. A dated correction in
   `GOALS.md` reads the clause as scoped to `evok` itself and the RS-485 ttys, which is what its stated
   reason — two processes cannot both own `/dev/ttyNS0` — actually supports. **Reverse that note if the
   original intent was different.** Decides whether `driver-onboard` has a transport at all; settle
   before N5.
2. ~~Which extension models are actually on hand~~ **Answered 2026-08-10: xS11 and xG18.** The xG18 is
   a bonus — 1-Wire over RTU is coverable today. No xS51, so AI/AO over RTU stays unverifiable until
   the approved order arrives.
3. ~~Which Debian generation each Patron runs~~ **Answered 2026-08-10: all three on Debian 13.** The
   Debian 12 identity path therefore has no test host. **Decision: image the incoming M527 #2 as
   Debian 12** — it arrives blank, so this costs nothing and destroys no fixtures. Reflashing an
   existing Patron would wipe stock EVOK and was rejected for that reason.
4. `node:sqlite` stability on the Node 24 minor we pin — available without a flag but a release
   candidate, not fully stable. Fallback is `better-sqlite3`, which needs armhf/arm64 prebuilds. See
   ADR-0005. Now `driver-store`'s problem rather than the daemon's.
5. **Two workspace dependency edges are deliberately undeclared**, because declaring one wrongly is
   what `dependency-cruiser` then enforces:
   - `client → api-nextgen`. The client targets that surface's public schema, which does not exist
     until N6. The alternative is a separate `schema-nextgen` package, so the client need not depend on
     a server package at all. Decide when the schema lands.
   - `ui → client`. Was open question 5b for `inspector`; unchanged by the rename, and still to be
     decided before `ui` starts after N6.
6. **`typescript` is pinned to `~6.0.3`, not the current `latest` (7.0.2).** `typescript-eslint@8.66.0`
   declares `typescript >=4.8.4 <6.1.0`, so T0.3's type-checked lint config — the load-bearing layering
   and no-`any` guard — cannot run on TS 7. The pin is a `~` range on purpose: `^6.0.3` would silently
   allow 6.1 and break lint. Revisit when `typescript-eslint` supports the native compiler.
7. **`data_point` is overloaded, and must not be allowed to converge.** It is a specific EVOK type
   (id 24, `<device_name>_<register_address>`, `datatype: null|float32`); our generic term for anything
   addressable is **endpoint** (ADR-0010).
8. Deferred by design, listed so they are not mistaken for oversights: trigger-engine fail-safe
   semantics, the admin-surface authentication mechanism, and the plugin isolation model — the last now
   narrowed by ADR-0012, which makes 1.0 single-threaded and leaves the boundary as the thing that
   keeps the options open. See [`GOALS.md`](../GOALS.md) §Open.
