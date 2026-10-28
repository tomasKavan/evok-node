# M3 — Design

Design every part of the system before development starts. Tasks run in the order listed.

**A design task is done when:** the document has no memo banner; it has no **Open:** item, or each one is deferred with a reason and the task that closes it; documents citing it are updated; `STATUS.md` is updated.

## Document map

Target numbering in `design/evok-node/` once M3 is done.

| Doc | Content | Today |
|---|---|---|
| 12a | Home driver | 12a |
| 12b | Home rules | 12b |
| 12c | Home main devices | new |
| 12d | Almanac driver | new |
| 12e | 2N access driver | new |
| 12f | ISM8i driver | new |
| 12g | MIM-B19N driver | new |
| 12h | Central heating driver | new |
| 12i | Rainwater driver | 12i |
| 13 | APIs — common to all, API plugins | 13 + 18 |
| 13a | Auth & ACL framework | new |
| 13b | Shell app (mobile/desktop) | new |
| 14 | REMOVED | Compat API |
| 15 | WS API | 15 Nextgen API |
| 16 | Inspector UI | 16 |
| 17 | Inspector UI plugins | 17 |
| 18 | Home API | 18 API plugins |
| 19 | Home UI | new |
| 20 | Matter bridge API | 16a |

## Tasks

### M3.1 — Scope: retire compat API, revise goals and non-goals, fix broken paths   `area/scope`
Drop EVOK API compatibility and the config migration tool. Rewrite goals and non-goals: evok-node is a PLC runtime with its own APIs, home automation, rules and UIs. Fix broken links across `docs/`, READMEs and fixtures.
**Done when:** no document claims EVOK compatibility or a migration path; 14 is REMOVED; link check finds only links to not-yet-created packages.
**Refs:** design README · root README · dev README · 01 §11 · basics/01 §3

### M3.2 — Home driver: finalize   `area/home`
Templates and devices — general rules, what is stored, what the UI cannot control. Tails for `local`/`matter` origins. Management split by API kind (inspector vs controller). Device options as JSON in method argument types. Final driver name. Matter mapping table.
**Done when:** 12a has no **Open:**; 20 (16a) holds the mapping table.
**Refs:** 12a §2–§5 · 05a §3.1 · 16a

### M3.3 — Home: main devices   `area/home`
Deep dive per device type. Per type: intro (what it is for, what not), fields, templates and
their workflow, Matter mapping (part of the mapping table), what a `SET` reports while the
device moves to its target. Matter research per type in `research/matter/`.
Types: `GenericSwitch`, `OnOffLight`, `DimmableLight`, `ColorTemperatureLight`,
`ExtendedColorLight`, `OnOffPlugInUnit`, `TimerRelay`, `WindowCovering`, `Closure`, `DoorLock`, `WaterValve`, `IrrigationSystem`, `ContactSensor`,
`WaterLeakDetector`, `TemperatureSensor`, `HumiditySensor`, `AirQualitySensor`,
`OccupancySensor`, `LightSensor`, `RoomAirConditioner`, `Thermostat`.
`Thermostat` and `RoomAirConditioner` in their own step, M3.3b.
Decided in their step: `Fan` (fit for heat recovery units), `Pump`.
One file per type group under `12c-Home-main-devices/`; 12c itself becomes their index as the last step.
**Done when:** 12c covers every listed type; 12a §2.2, 16a's mapping table and 12b agree
with it; `research/matter/` holds a note per type with a Matter counterpart.
**Refs:** 12a §2–§4a · 12b §2 · 16a · research/matter

### M3.3a — Rainwater driver and tank   `area/home`
`driver-rainwater`: the rainwater tanks, their valves and the garden pump — refills, transfer to the upper tank, cutoff, alarms — as raw endpoints shown and controlled in the Inspector. Plant in config, mode and settings in KV. Descaler bypass on another PLC over a WS link, a general driver-kit mechanism. Level sensor DS1603DA-3R as a shipped third-party definition. Home side: `RainwaterTank`, a supply valve as the irrigation master, the retention alarm as a `WaterLeakDetector`.
**Done when:** 12i and 12c-11 designed; 05a §3.8b, 07a §10.5 and 09 §7 agree; 12c-08 §3.3 has no Open; 12a §2.2 and 16a agree.
**Refs:** research/15 · 12c-08 · 12a §3, §3a · 05a §3.8a · 07 §4.1 · 07a §10 · 09 §7

### M3.3b — Home: thermostat   `area/home`
`Thermostat`: one per room, the room's controller — setpoint, actual temperature (a `TemperatureSensor` role), source policy (hydronic, AC, order, outdoor breakpoint), override, presets, Matter mapping. It runs the room loop and sends requests to its sources: a heating request (`mode`, `level` %) to a central-heating zone (12h), power/mode/compensated setpoint to an AC indoor unit (12g). Cooling lockout. `SamsungAc` device for the AC specialities (fan, swing, WindFree, quiet/fast/eco, filter, errors). Open: whether `RoomAirConditioner` stays a home type; on which PLC the thermostat runs, as zones live on the boiler-room PLC and a remote import carries home devices only (12a §4b).
**Done when:** 12c has its file (12c-10); the request contract to 12g and 12h is fixed; 12a §2.2 and 16a agree with it.
**Refs:** research/matter/11 · 12a §3, §4b · 12c-04 · 12c-08 · 16a

### M3.3c — MIM-B19N driver   `area/samsung`
`driver-mimb19n`: Samsung MIM-B19N over Modbus RTU, raw devices per indoor unit and outdoor unit. Configuration and state it holds, indoor-unit list, write pacing, setup of custom NASA registers, local-change detection (remote, SmartThings), remote lock. AI mode: research gap first.
**Done when:** 12g designed; the kinds serve M3.3b's request contract.
**Refs:** research/matter/11 §6 · 07 · 07b · 05a

### M3.3d — ISM8i driver   `area/heating`
`driver-ism8i`: Wolf ISM8i over TCP — the driver is the server; acknowledgements, read-all on connect, watchdog for the silent drop, writes. Raw kinds for boiler, direct circuit and mixer circuits 1–3.
**Done when:** 12f designed.
**Refs:** research/matter/11 §7 · 05a

### M3.3e — Central heating driver   `area/heating`
`driver-central-heating`: the building's heating as one system, on the boiler-room PLC. Circuits (mixers 1–5, 1–3 through 12f) and zones (rooms → valves on Unipi outputs). Answers zone requests from thermostats: valve duty cycle, exercise, flow guard (one circuit open or a bypass), summer and availability, setpoint correction on mixers 1–3, fallback to open valves when requests stop. Knows no room temperature. How 12c-08's `thermal-valve-from-output` relates to it.
**Done when:** 12h designed; M3.3b's zone contract matches it.
**Refs:** research/matter/11 §5, §7 · research/matter/09 §4.3 · 12c-08 · 12f · 08 · 09

### M3.4 — Almanac driver   `area/almanac`
Calendar, weather forecast, sun position. Data sources, offline behaviour. Respective home devices. A wind DeviceType — gusts in m/s with the time they apply to — for `WindowCovering`'s `wind` role (12c-06 §3.4). A rain forecast for the rainwater driver's early transfer (12i §11).
**Done when:** 12d designed; new device types added to 12c; 12i §11 has no Open.
**Refs:** 05a · 12a · 12b · 12i

### M3.5 — APIs: common contract and API plugins   `area/api`
What every API must do, whatever it speaks. API as plugin, the same mechanism as drivers. Absorbs 18 API plugins.
**Done when:** 13 designed; 18's content moved into 13.
**Refs:** 13 · 18 · 01 §9 · 02 §4–§5 · 03

### M3.6 — Auth & ACL framework   `area/auth`
A library APIs use, not an API. Upstream identity provider (authentik). Users, roles, keys, devices, client credentials (PLC to PLC). Authentication: SSO, password, PIN, biometrics; local vs full. Assurance levels and how an API reacts (PIN for a lock): a method marked as needing proof, and the call's principal reaching a template (12c-09 §1.2). The same proof for an access closure's `open` (`garageDoor`, `gate`, `door`; `close` free), and whether a virtual `DoorLock` gates it (12c-07 §6). Then Matter exposure of `DoorLock` and access closures (12c-09 §4, 12c-07 §4). Local DB as a new driver kind. Example flows, including mobile apps and biometrics.
**Done when:** 13a designed; research doc for the identity provider exists.
**Refs:** 13 · 15 · 06 §5a · 12a §4b · 12c-07 §6 · 12c-09 §1.2

### M3.6a — 2N access driver   `area/2n`
A driver for 2N Access Unit 2.0 / IP Verso 2.0 over the HTTP API: switches, door state, I/O, events over `log/subscribe`/`log/pull`, `grantaccess` for a user. API account and secrets via 13a. Map from the identity provider's users to 2N users; the 2N's users come from the identity provider through Access Commander — the driver never writes the 2N directory. DeviceTypes for `lock-from-2n`'s roles.
**Done when:** 12e designed; 12c-09 §3.2 has no Open.
**Refs:** research/matter/08 §4 · 12c-09 §3.2 · 13a · 05a

### M3.7 — Shell app (mobile/desktop)   `area/shell-app`
What it is and how it's used. Multi-user, multi-PLC, multi-app: what an app (inspector, Home UI) must provide to load in the shell. Platforms, framework. Authorization via 13a, biometrics. Push notifications, Matter BLE pairing.
**Done when:** 13b designed; framework research doc exists.
**Refs:** 13a · 16 · 19

### M3.8 — WS API   `area/api`
Renamed from nextgen. Relays internal messaging; per-connection and per-request plugins. Other APIs built on top of it. Authorization through a plugin using 13a. The hello advertises `evokNodeVersion` (12a §4b). Session language (`hello.lang`, `Accept-Language`, `setLang`) and the localization engine resolving `LocalizedText` at the edge (05a §3.1a).
**Done when:** 15 designed and renamed; `api-nextgen` renamed in docs.
**Refs:** 03 · 13 · 13a · 15

### M3.9 — Inspector UI: basics   `area/ui`
Structure, logic, wireframes, mobile vs desktop, frameworks, design guide. Basic controls for raw driver-kit devices. Logs. Generic forms from annotated schemas and `$refs` (05a §3.1a, §3.10); a ref filter that depends on another field of the same form (DALI bus → gear).
**Done when:** 16 designed, wireframes committed.
**Refs:** 15 · 05a · 04 · 11

### M3.10 — Inspector UI: plugins   `area/ui`
Plugin approach. Main plugins: unipi system, unipi local, unipi extension, DALI (with commissioning workflow), Home config and control.
**Done when:** 17 designed.
**Refs:** 16 · 08 · 09 · 11 · 12 · 12a

### M3.11 — Home API   `area/api`
Subset of the WS API; understands only the home driver. Relays the subset of management 12a §5 lists.
**Done when:** 18 designed.
**Refs:** 15 · 12a · 12b · 13a

### M3.12 — Home UI   `area/ui`
Structure, logic, typical users, wireframes, mobile vs desktop vs kiosk, frameworks, design guide. UX is the priority. Grouping (rooms, topics). Limited set of controls, all defined. Rule definition. Matter pairing.
**Done when:** 19 designed, wireframes committed.
**Refs:** 18 · 12a §6 · 12b · 12c · 13b

### M3.13 — Matter bridge API   `area/api`
Exposes home devices as Matter bridged devices.
**Done when:** 20 designed (from 16a).
**Refs:** 16a · 12a · 12c · 13

### M3.14 — Documentation revision   `area/docs`
Numbering and reorganisation per the map above. Links, forward references. Brevity, examples, binding definitions.
**Done when:** link check is clean; no forward reference without a target; AGENTS.md roles defined.
**Refs:** dev README §4 · AGENTS.md

### M3.15 — Packages & dependencies   `area/packages`
Revisit package definitions and bootstrapping. What is exposed, in which package, and who uses it. Adjust dependency-cruiser.
**Done when:** basics/01 package list matches every design doc; `WORKSPACE_DEPS` covers every designed package.
**Refs:** basics/01 · 01 §11 · `.dependency-cruiser.cjs`

### M3.16 — Testing: unit test review   `area/testing`
**Done when:** basics/03 tier 1 rules match the final design.
**Refs:** basics/03

### M3.17 — Testing: simulators   `area/testing`
Simulators for all driver transports: Modbus (Unipi board and extensions), DALI.
**Done when:** `design/simulator` designed.
**Refs:** design/simulator · 07 · 07b · 12

### M3.18 — Test rig: hardware design and wiring   `area/rig`
**Done when:** schematic and wiring committed under `design/test-rig`.
**Refs:** design/test-rig · research/09

### M3.19 — Test rig: master unit controller and testing software   `area/rig`
**Done when:** `design/test-rig` controller and software designed.
**Refs:** design/test-rig · basics/03 §1.3

### M3.20 — Test rig: test definition   `area/rig`
Includes the performance baseline (idle CPU, scan timing, API latency) — no capture from stock EVOK.
**Done when:** test definition format, initial test set and baseline designed.
**Refs:** design/test-rig · basics/03 §2

### M3.21 — Development plan   `area/plan`
Define M4 and later.
**Done when:** `roadmap.md` lists M4+; each has a milestone file.
**Refs:** this file · `STATUS.md`
