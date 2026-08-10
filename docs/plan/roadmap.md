# Roadmap

Milestones, in order. Detail lives in `milestones/M*.md`; rationale lives in
[`../research/`](../research/). Human tasks are marked — everything else is agent work.

M0–M6 is the entire scope of 1.0 as defined in [`../GOALS.md`](../GOALS.md): compatibility
complete, every bug disposition closed, nothing else. Post-1.0 direction is at the bottom of this
file and is **not** milestoned.

| | Milestone | Goal | Exit criteria |
|---|---|---|---|
| **M0** | Scaffolding | A repo an agent can work in safely | workspaces build; strict TS, eslint, dependency-cruiser and vitest green; CI runs tier 0 on PR; ADRs written |
| **M1** | Fixtures & simulator | The permanent substitute for unbuyable hardware | address tables generated for all 83 model×sections; simulator serves any model; codec golden tables pass; fixture-drift check enforced in CI |
| **M2** | Transport | Modbus that cannot silently return the wrong data | all eight wrapper guarantees implemented and tested; stale-frame-desync and TID-boundary tests pass; fault-injection matrix green |
| **M3** | Definitions & device model | The hardware map, correct by construction | base→overlay→site merge; all load-time validations; duplicate coil/circuit is fatal; device lifecycle and staleness in the model; **overlay format accommodates per-channel mode sets, per-model mode enums and unit-0 devices** (Edge's requirements, needed before the format ships) |
| **M4** | API surface | Byte-compatible with real clients | golden transcripts replay clean; all 22 requirements in research/07 covered; Node-RED and HA acceptance pass through nginx |
| **M5** | Operability | Answerable in one request instead of a forum thread | `doctor`, `/diagnostics`, `/metrics`; structured logs; supervised buses; continuous discovery |
| **M6** | Hardening & release | Trustworthy on real hardware over time | soak clean; hardware checklist closed; Debian 12 + 13 install tested; **`bug-dispositions.md` fully closed**; migration + rollback tested; docs smoothing pass; `0.1.0-beta` |

### Parallel human tracks

| Track | When | Blocks |
|---|---|---|
| **Golden transcript capture** | **now, before touching the Patrons** | M1 golden tests, M4 entirely |
| **evok packaging metadata capture** | same trip | the `Conflicts:`/dependency list in ADR-0002, migration fixtures in ADR-0003, nginx site handling |
| Rig build — wiring, test-host Patron prep | during M0–M2 | M2 hardware verification, all tier-1 tests |
| Hardware purchases (**second Patron M527 as rig test host**, xS51, Neuron L203, Unipi 1.1) | M527 before M2; the rest before M6 | the M527 blocks the rig and therefore every tier-1 test; the others block Neuron and Unipi 1.1 verification |

### Sequencing notes

**Transport before API.** Ordered by risk, not by architecture-diagram tidiness. Every
silent-wrong-data failure in the upstream corpus lives in the transport and addressing layers, and
those are the two things we cannot fully verify on hardware. They go first and get verified
hardest.

**M1 before M2** because the simulator and fault injection *are* how M2 gets tested. Building
transport first and testing it later is how upstream ended up shipping
`await asyncio.sleep(0.00005)  # TODO: THIS IS HOTFIX !!! REMOVE IT !!!`.

**Edge is a fast follow after 1.0**, but the overlay definition format in M3 must already
accommodate it — per-channel mode sets, **per-model mode enums** and unit-0 devices — or the first
minor release breaks the format. Now in M3's exit criteria. See
[research/05](../research/05-evok-node-design-notes.md) §8.3.

**Additional packages** (`client`, `inspector`) land after M4, since both consume the public API
and would otherwise be built against a moving target. `simulator` ships publicly from M1 — it is
useful to anyone integrating with Unipi hardware and costs us nothing extra.

---

## Post-1.0 direction

Committed direction, stated in [`../GOALS.md`](../GOALS.md). **Deliberately not milestoned and not
task-listed** — per rule 4 in [`README.md`](README.md), an agent does not turn these into work.
They are here so the sequencing above can be read against where the project is going.

| | Area | What it constrains *now* |
|---|---|---|
| Web SPA | full replacement for `evok-web-jq`: compact status, filter/sort/search, control, configuration, status on PLC layout drawings | the `inspector` package boundary; the shape of user data (groups, ordering, labels, layouts) in GOALS invariant 5 |
| Logs & debug | log access over the API, debug tooling in the SPA | structured logging in M5 must be queryable, not just writable |
| Introspection | processes, resource consumption, network status and configuration | GOALS invariant 2 — a privileged surface cannot share the compat surface's trust level |
| Plugins | non-Unipi devices reachable from the PLC: DALI, M-Bus | GOALS invariant 6 — core needs a leased, time-budgeted bus transaction API, not a second Modbus client |
| Trigger engine | lightweight rule machine, no visual editor, for pump control and lighting timers | declarative interlocks (research/05 §6.4) are its foundation and land in the device layer |
| Edge support | fast follow-up to 1.0, per research/05 §8.3 | the overlay definition format must accommodate per-channel mode sets, per-model mode enums and unit-0 devices **in M3**, or the first minor release breaks it |

**`inspector` spans the line.** It lands after M4 as a consumer of the public API (see the note
above), but the full SPA in the table is post-1.0. How much ships inside 1.0 is an open question in
[`../GOALS.md`](../GOALS.md) §Open; until it is answered, treat anything beyond a read-only status
view as post-1.0.

**Why these are listed but not scheduled.** Each one implies a decision that is expensive to
retrofit, and those decisions are already captured as invariants in `GOALS.md` and as ADRs. The
features themselves compete directly with the reliability goal, so they wait. The order above is
not a priority order; it will be set when 1.0 ships.
