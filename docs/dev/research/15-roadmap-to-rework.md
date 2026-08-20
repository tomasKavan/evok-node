# Roadmap

Milestones, in order. Detail lives in `milestones/N*.md`; rationale lives in
[`../research/`](../research/). Human tasks are marked — everything else is agent work.

N0–N10 is the entire scope of 1.0 as defined in [`../GOALS.md`](../GOALS.md): compatibility
complete, every bug disposition closed, nothing else. Post-1.0 direction is at the bottom of this
file and is **not** milestoned.

**Restructured 2026-08-12** from the seven milestones M0–M6, per ADR-0001. Same scope and same
definition of 1.0 — a different build order, with more and smaller milestones (RP-5). The old
identifiers survive in the `Was` column because `bug-dispositions.md` and the research notes cite
them. Rationale: [research/12](../research/12-modularisation.md).

| | Milestone | Was | Goal | Exit criteria |
|---|---|---|---|---|
| **N0** | Re-steer & scaffolding | M0 | A repo an agent can work in safely, in the shape ADR-0001 settled | thirteen workspaces build; strict TS, eslint, dependency-cruiser and vitest green; CI runs tier 0 on PR; the ADR set written and consolidated to thirteen |
| **N1** | Fixtures & simulator | M1 | The permanent substitute for unbuyable hardware | address tables generated for all 83 model×sections; simulator serves any model; codec golden tables pass; fixture-drift check enforced in CI |
| **N2** | Messaging & main | — | A daemon that spawns, supervises and reloads, with nothing to drive yet | envelope schemas round-trip (ADR-0001); config parse with resource-exclusivity validation; boot-fatal / reload-non-fatal asymmetry tested (RC-32); spawn, supervise and reload verified against a **stub driver** |
| **N3** | Transport | M2 | Modbus that cannot silently return the wrong data | all eight wrapper guarantees implemented and tested; stale-frame-desync and TID-boundary tests pass; fault-injection matrix green |
| **N4** | Definitions & device model | M3 | The hardware map, correct by construction | **the definition corpus transcribed** from the register maps plus EVOK's shipped definitions, hand-reviewed (ADR-0014); loader for our format — id resolution, `custom/` root, `minFirmware` variant selection, handshake identity and census checks; all load-time validations; duplicate coil/circuit is fatal; device lifecycle and staleness; **format accommodates per-channel mode sets, per-model mode enums and unit-0 devices** (Edge's requirements, needed before the format ships) |
| **N5** | First driver | — | One driver, complete and introspectable, with no API above it | `driver-kit` + `driver-onboard` against the simulator; introspection schema settled; RC-27 (query path never blocks) and RC-29 (`effect` mandatory) hold; **nextgen envelope drafted and its expressiveness checked** (T5.x) |
| **N6** | Nextgen API | — | A public surface that new drivers extend without touching it | WS then HTTP; hardens N5's draft and adds no driver-specific shape (RC-30); reserved route prefixes chosen once, since `ui` is served at `/`; backpressure and keepalive correct here first |
| **N7** | Extensions driver | — | The second driver, which is what proves the first one's abstraction | `driver-extension` over RTU + nextgen support; **`driver-kit`'s boundary revisited** now a second implementation exists; per-driver quarantine and t3.5 pacing on real wire |
| **N8** | 1-Wire driver | — | The non-Modbus driver, and the one with real discovery | `driver-onewire` over owserver; discovery interval and topology-change capability; device-level and reading-level addressing both served |
| **N9** | Compat surface | M4 | Byte-compatible with real clients | golden transcripts replay clean; all 22 requirements in research/07 covered; projection table derived from introspection (ADR-0003) and injective; at most one onboard driver, zero being the Gate; Node-RED and HA acceptance pass through nginx |
| **N10** | Operability, hardening & release | M5 + M6 | Trustworthy on real hardware over time | `doctor`, `/diagnostics`, `/metrics`, structured logs, supervised buses; soak clean; hardware checklist closed; Debian 12 + 13 install tested; **`bug-dispositions.md` fully closed**; migration + rollback tested; docs smoothing pass; `0.1.0-beta` |

### Parallel human tracks

| Track | When | Blocks |
|---|---|---|
| **Golden transcript capture** | **now, before touching the Patrons** | N1 golden tests, N9 entirely |
| **evok packaging metadata capture** | same trip | the `Conflicts:`/dependency list in ADR-0006, migration fixtures in ADR-0006, nginx site handling |
| Rig build — wiring, test-host Patron prep | during N0–N3 | N3 hardware verification, all tier-1 tests |
| Hardware purchases (**second Patron M527 as rig test host**, xS51, Neuron L203, Unipi 1.1) | M527 before N3; the rest before N10 | the M527 blocks the rig and therefore every tier-1 test; the others block Neuron and Unipi 1.1 verification |

**Demoting compat does not defer the capture trip.** It is the tempting inference and it is wrong:
the transcripts are unrecoverable once EVOK leaves those Patrons, and moving the compat surface to N9
changes only when they are *consumed*.

### Sequencing notes

**Transport before API.** Ordered by risk, not by architecture-diagram tidiness. Every
silent-wrong-data failure in the upstream corpus lives in the transport and addressing layers, and
those are the two things we cannot fully verify on hardware. They go first and get verified
hardest.

**N1 before N3** because the simulator and fault injection *are* how transport gets tested. Building
transport first and testing it later is how upstream ended up shipping
`await asyncio.sleep(0.00005)  # TODO: THIS IS HOTFIX !!! REMOVE IT !!!`. N1 also stays ahead of
**every driver**: there is no hardware to test a driver against, so the generated address tables and
the simulator are the only substrate. The rig cannot substitute — it is purchase-blocked and runs as a
parallel track (RP-7).

**N2 before N3, against intuition.** `main` is testable against a stub driver, and doing it that way
forces the driver contract to be *designed* rather than inherited from whatever `driver-onboard`
happens to expose first.

**The compat surface goes last, and this is a change.** It used to be M4, ahead of operability. Only
7 of the 29 findings depend on it, and several of those seven — WebSocket backpressure, keepalive and
close semantics, write-returns-post-write-value — are surface-agnostic mechanisms that get built
correctly in N6, leaving the compat versions as projections of already-correct machinery. What
protects the model from being shaped by EVOK is architectural (G-3, RC-24), not the ordering; the
ordering is the second line. ADR-0001.

**Edge is a fast follow after 1.0**, but the definition format in N4 must already
accommodate it — per-channel mode sets, **per-model mode enums** and unit-0 devices — or the first
minor release breaks the format. In N4's exit criteria, and checked again by T5.x against the nextgen
envelope. See [research/05](../research/05-evok-node-design-notes.md) §8.3.

**Additional packages** (`client`, `ui`) land after N6, since both consume the public API and would
otherwise be built against a moving target. `ui` is served by `api-nextgen` at `/`, which is why N6
must choose its reserved route prefixes once. `simulator` ships publicly from N1 — it is useful to
anyone integrating with Unipi hardware and costs us nothing extra.

---

## Post-1.0 direction

Committed direction, stated in [`../GOALS.md`](../GOALS.md). **Deliberately not milestoned and not
task-listed** — per RP-4, an agent does not turn these into work.
They are here so the sequencing above can be read against where the project is going.

| | Area | What it constrains *now* |
|---|---|---|
| Web SPA | full replacement for `evok-web-jq`: compact status, filter/sort/search, control, configuration, status on PLC layout drawings | the `ui` package boundary; the shape of user data (groups, ordering, labels, layouts) in G-5 |
| Logs & debug | log access over the API, debug tooling in the SPA | structured logging in N10 must be queryable, not just writable; logs are a driver endpoint whose shape is a stream, not a reading |
| System introspection | processes, resource consumption, network status and configuration | G-2 — a privileged surface cannot share the compat surface's trust level. Arrives as `driver-system`, a driver whose transport is the filesystem and process-exec (ADR-0001) |
| Plugins | non-Unipi devices reachable from the PLC: DALI, M-Bus | G-6 — a leased, time-budgeted bus transaction through the owning driver, never a second Modbus client. ADR-0001's manifest loading and RC-30 are what make a plugin driver possible without an API release |
| Trigger engine | lightweight rule machine, no visual editor, for pump control and lighting timers | declarative interlocks (research/05 §6.4) are its foundation and land in the device layer |
| Edge support | fast follow-up to 1.0, per research/05 §8.3 | the definition format must accommodate per-channel mode sets, per-model mode enums and unit-0 devices **in N4**, or the first minor release breaks it (ADR-0014's format does) |

**`ui` spans the line.** It lands after N6 as a consumer of the public API (see the note above), but
the full SPA in the table is post-1.0. How much ships inside 1.0 is an open question in
[`../GOALS.md`](../GOALS.md) §Open; until it is answered, treat anything beyond a read-only status
view as post-1.0. Note the shipped SPA is single-instance by construction — G-4's aggregation case is
either client-side user data or a separately deployed SPA with `ui: false`.

**Why these are listed but not scheduled.** Each one implies a decision that is expensive to
retrofit, and those decisions are already captured as invariants in `GOALS.md` and as ADRs. The
features themselves compete directly with the reliability goal, so they wait. The order above is
not a priority order; it will be set when 1.0 ships.
