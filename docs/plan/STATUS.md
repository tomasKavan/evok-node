# Status

**Updated:** 2026-08-16 · **Phase:** development documentation · **Version:** unreleased

## Where we are

**Everything done so far except the repo scaffolding is research, and there is no plan right now.**
Reset on 2026-08-16, deliberately. The research is genuinely useful and none of it was thrown away;
what was thrown away is its false authority — a roadmap, a milestone breakdown and a set of ADRs that
read as decided when the design underneath them had not been written down anywhere.

The order from here: **development documentation → new plan → code.** No implementation work starts
against the old plan.

What moved, all of it on 2026-08-16:

| Was | Now |
|---|---|
| `docs/adr/*` — 14 ADRs | [`research/to_revision/`](../research/to_revision/README.md), **suspended**. Immutability lock lifted; nothing binding may cite one until the set is re-locked |
| `plan/hw-definition-format.md` | [research/13](../research/13-config-and-hw-definition-format.md) |
| `plan/bug-dispositions.md` | [research/14](../research/14-bug-dispositions.md) |
| `plan/roadmap.md` — N0–N10 | [research/15](../research/15-roadmap-to-rework.md), superseded, kept for its sequencing arguments |
| `plan/milestones/`, `plan/capture-trip.md`, `tools/capture/` | **Deleted.** Clean slate; the capture work is re-planned from scratch later in the process |
| Derived notes inside `docs/modbus-reg-map/` | [`research/modbus-reg-map-notes/`](../research/modbus-reg-map-notes/README.md). That tree is now Unipi ground truth and mechanical extracts only |

Rules changed shape too: `RC-N` became **`RCD-N`** and was cut back to generic TypeScript rules,
project-specific rules moved to [`rules/packages/`](../rules/packages/README.md) as **`RPG-*`**, and
`RP-N` became **`RPL-N`**. `RC` numbers were regenerated, not re-prefixed — see the renames note in
[`CLAUDE.md`](../../CLAUDE.md).

`GOALS.md` still holds, with two changes: *What 1.0 is* now reads **TBD** until the documentation pass
settles it, and the Invariants section is marked for review and relocation.

The workspace skeleton is **untouched and still valid**: thirteen packages, building, linting and
cruising clean. **No implementation code exists yet**; every package's entrypoint is a placeholder
export.

## Done

- Research: EVOK 3.x API surface, Unipi hardware model, config and hw-definition formats,
  upstream bug archaeology (29 condensed findings, ~90 raw), client compatibility matrix, latency
  budget, test-kit design, register-map corpus imported and indexed.
- **Goals consolidated (2026-08-10).** [`GOALS.md`](../GOALS.md) is authoritative: the goal, the
  measurable form of it, the invariants, the drop-in guarantee, non-goals.
- **T0.1–T0.5 (2026-08-10).** npm workspaces, a shared strict TS base with the six T0.2 flags,
  vitest in workspace mode with coverage floors wired and switched off, `pr` and `main` CI workflows
  with actions pinned by SHA, eslint with the type-checked config, and `dependency-cruiser` carrying
  the layering DAG.
- **Re-steer worked out (2026-08-12).** Drivers / APIs / `main`, driver-qualified addressing,
  introspection as the source of compat's table, single-threaded. Reasoning in full in
  [research/12](../research/12-modularisation.md); the four ADRs that recorded it are now
  [under revision](../research/to_revision/README.md). The conclusions largely stand — they are just
  no longer *settled* until the documentation pass says so.
- **Skeleton reworked (2026-08-12).** Thirteen packages: `core`, `server`, `protocol` and
  `inspector` removed; `messaging`, `main`, `driver-kit`, `driver-onboard`, `driver-extension`,
  `api-nextgen`, `api-compat` and `ui` added. Root `tsconfig.json` references, the
  `dependency-cruiser` DAG, vitest projects and coverage floors all follow. `npm run build`, `test`,
  `lint` and `layering` each exit 0; 27 modules and 13 edges cruised with no violations.
- **ADRs written and consolidated (2026-08-12/13).** Eleven settled-but-undocumented decisions were
  written up, the set was consolidated from 23 files to 13, and a fourteenth was added on 2026-08-13. All
  of it is now [under revision](../research/to_revision/README.md) — the writing was not wasted, but
  it turned out to be reasoning in search of a design document rather than a substitute for one.
- **Docs reset (2026-08-16).** See *Where we are*.

## In progress

- **Development documentation.** Written from the research above, with the ADRs and
  [research/12](../research/12-modularisation.md) as the main inputs, and settled by discussion as it
  goes. It defines the ADR set that gets re-locked, and *What 1.0 is*.
- **Left over from scaffolding:** the licence choice (MIT or Apache-2.0 — undecided), repo hygiene,
  and `npm run verify`. Independent of the documentation pass and can land at any time.
- **Four of the `pr` workflow's eight checks are still placeholders** — `format` and `changeset`
  until repo hygiene lands, `fixture-drift` until there are fixtures, and `coverage` runs but enforces
  nothing until there is something to cover. Each prints a warning annotation saying so.
- **Branch protection is not yet configured** — Tomas's to set. Until it is, the workflows run but
  nothing requires them to be green.

## Next

1. Finish the development documentation.
2. Re-lock the ADR set against it, and lift *TBD* from *What 1.0 is*.
3. Derive a new plan and milestones from that.
4. Adjust the repo scaffolding if the documentation calls for it.
5. Start building.

Nothing below step 3 is scheduled, and no milestone numbers should be invented before it (RPL-4).

## Blocked / waiting on hardware

Unchanged by the reset, because hardware does not care about our documents. **All three Patrons are
confirmed still stock**, and the golden transcripts are unrecoverable once EVOK leaves them — the
capture work is time-sensitive regardless of where it lands in the new plan. The old runbook was
deleted with the rest of the plan; a new one is written when the plan calls for it, from the list
below.

| Item | Waiting on |
|---|---|
| Golden transcript capture | **Human task, time-sensitive.** Must be recorded from stock EVOK 3.0.6 on L527/M527/S167 — **and the Gate, if it still runs stock EVOK**, since research/09 §2 makes the zero-local-I/O payload a named requirement — *before* anything replaces EVOK on those units. Unrecoverable afterwards. |
| **Gate behaviour with no onboard driver** | Same trip, and newly load-bearing: `api-compat` requires **at most one** onboard driver, and zero is the Gate, which must serve an empty API rather than erroring. research/09 records that EVOK's own `readboards()` and `/rest/all` "degrade oddly" here, so the compat shape must be captured rather than inferred. |
| Stock `hw_definitions` + `autogen.yaml` + firmware versions | Same trip as the transcript capture. **Now blocking, not merely useful:** the shipped `hw_definitions` are the only source of the AI/AO **mode enumerations** for CSV-only families, and G-3 makes those mandatory — so our board `00` definition cannot be written until this is captured. Edge and Unipi 1.1 are unaffected; their XLSX `Description` sheets carry the enums. |
| Register 1004 (Hardware ID) per unit | Same trip. Seeds `identifies.hardwareId` in our definitions; a model without it falls back to the census check, which is normal rather than incomplete. |
| Which `run.d` directory exists, and what owns it | Same trip, cheap: `ls -ld /usr/lib/unipi/run.d /opt/unipi/os-configurator/run.d` plus `dpkg -S`. Upstream documents the first, Debian 12 shows the second. Our `postinst` installs into whichever exists. |
| Stock `config.yaml` + `/var/lib/evok/alias.yaml` | Same trip. These are the migration tool's golden fixtures. |
| evok packaging metadata — systemd unit names and its nginx site file | Same trip. **Mostly answered 2026-08-13** on a live Patron: `evok` declares `Depends: python3` only, `apt-get -s remove --auto-remove evok` takes `evok`, `evok-web`, `nginx`, `nginx-common`, and `evok-unipi-data` survives. So `Depends:` needs **`nginx`**, not `unipi-kernel-modules`, and no Unipi data package at all — correcting what we had assumed. What remains is the unit names and the `:80` site conflict. **Do not `apt purge evok` before migrating** — purge destroys the fixtures above. |
| `start_index` old-behaviour baseline | **Same trip, and easy to forget.** Finding 1.1's `test` disposition needs a transcript of stock EVOK mis-registering a deliberately split RO definition (two blocks of 7 with `start_index`) on the L527's section 3. |
| Second Patron M527 as rig test host | **Purchase approved 2026-08-10, not yet ordered.** Blocks all tier-1 hardware tests. **Image it with Debian 12** — see open question 3. |
| xS51 extension | **Purchase approved 2026-08-10, not yet ordered.** AI/AO over RTU (float32 AI, raw-count AO, 6-mode enum on an extension) is otherwise only reachable via the local TCP path. |
| Tier-1 hardware tests | Rig not built. Needs the second Patron M527 as test host, wiring, `rig` service. Runs as a parallel track and gates nothing (RPL-7). |
| RS485 baud-encoding, DirectSwitch write path, unit-0 aggregate reads, register 1007 semantics | Verification on hardware. See [research/05](../research/05-evok-node-design-notes.md) §7.4. Partly answerable on the capture trip. |
| Neuron and Unipi 1.1 support | Hardware not yet purchased. Map-driven and simulator-verified until then. When a Neuron is bought, buy an **L203**. |

## Known permanent gaps

- **No purchasable Unipi device has >16 channels of one type in a single section**, so the
  *missing-bank-stride* half of the highest-severity bug class (silently driving the wrong relay) can
  never be verified on hardware. Mitigated by generated address tables plus the
  fatal-on-duplicate-registration assertion (RPG-DRV-3). The `start_index` half **is** reproducible on the
  L527's section 3 via a deliberately split definition and the RO→DI loopback. See
  [research/10 §4](../research/10-test-kit.md) and
  [research/14](../research/14-bug-dispositions.md) finding 1.1.

## Open questions

1. ~~G-7's `unipitcp` clause~~ **Closed 2026-08-16.** G-7 is scoped to `evok` itself and the RS-485
   ttys; `unipitcp` is not a conflict, because local I/O *is* Modbus TCP to it. Stated plainly in
   `GOALS.md` now, with the correction note removed.
2. ~~Which extension models are actually on hand~~ **Answered 2026-08-10: xS11 and xG18.** The xG18 is
   a bonus — 1-Wire over RTU is coverable today. No xS51, so AI/AO over RTU stays unverifiable until
   the approved order arrives.
3. ~~Which Debian generation each Patron runs~~ **Answered 2026-08-10: all three on Debian 13.** The
   Debian 12 identity path therefore has no test host. **Decision: image the incoming M527 #2 as
   Debian 12** — it arrives blank, so this costs nothing and destroys no fixtures. Reflashing an
   existing Patron would wipe stock EVOK and was rejected for that reason.
4. `node:sqlite` stability on the Node 24 minor we pin — available without a flag but a release
   candidate, not fully stable. Fallback is `better-sqlite3`, which needs armhf/arm64 prebuilds. Now
   `driver-store`'s problem rather than the daemon's.
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
   addressable is **endpoint**.
8. Deferred by design, listed so they are not mistaken for oversights: trigger-engine fail-safe
   semantics, the admin-surface authentication mechanism, and the plugin isolation model — the last now
   narrowed by 1.0 being single-threaded, which leaves the message boundary as the thing that
   keeps the options open. See [`GOALS.md`](../GOALS.md) §Open.
