# M3 — Design

Design the core of the system before core implementation ([M4](../roadmap.md)) starts. The rest of the design is [M5](M5-design.md). Tasks run in the order listed.

**A design task is done when:** the document has no memo banner; it has no **Open:** item, or each one is deferred with a reason and the task that closes it; documents citing it are updated; `STATUS.md` is updated.

## Document map

Target numbering in `design/kapsle/`, M5's docs included. Renumbered in M3.14.

| Doc | Content | Today |
|---|---|---|
| 02a | Main driver and bootstrap | new |
| 02b | Plugins — general rules | new |
| 03a | Values and schemas | new |
| 12a | Home driver | 12a |
| 12b | Home rules | 12b |
| 12c | Home main devices | new |
| 12d | Almanac driver | new |
| 12e | 2N access driver | new |
| 12f | ISM8i driver | new |
| 12g | MIM-B19N driver | new |
| 12h | Central heating driver | new |
| 12i | Rainwater driver | 12i |
| 12j | AirGENIO driver | 12j |
| 13 | APIs — common to all, API plugins | 13 |
| 13a | Auth & ACL framework | new |
| 13b | Shell app (mobile/desktop) | new |
| 13c | Localization — the `l10n` WS extension | new |
| 14 | REMOVED | Compat API |
| 15 | WS API | 15 |
| 16 | Inspector UI | 16 |
| 17 | Inspector UI plugins | 17 |
| 18 | Home API | 18 |
| 19 | Home UI | new |
| 20 | Matter bridge API | 16a |

## Tasks

### M3.1 — Scope: retire compat API, revise goals and non-goals, fix broken paths   `area/scope`
Drop EVOK API compatibility and the config migration tool. Rewrite goals and non-goals: kapsle is a PLC runtime with its own APIs, home automation, rules and UIs. Fix broken links across `docs/`, READMEs and fixtures.
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
`OccupancySensor`, `LightSensor`, `RoomAirConditioner`, `Thermostat`, `Fan`, `VentilationUnit`.
`Thermostat` and `RoomAirConditioner` in their own step, M3.3b; `Fan` and `VentilationUnit` in M3.3f.
`Pump` deferred: a relay pump is an `OnOffPlugInUnit`.
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

### M3.3d — ISM8i library `wolf-ism8`   `area/heating`
The ISM8i protocol as a library of its own, in its own repository `tomasKavan/wolf-ism8` (created before development): codec with stream reassembly, KNX datapoint types, the datapoint table, a session over any byte stream (ACKs, read-all once, keepalive and silence, checked and rate-limited writes), a TCP server, the web-page info helper.
**Done when:** design/libs 01 designed.
**Refs:** research/19 · design/libs README

### M3.3da — ISM8i driver   `area/heating`
`driver-ism8i`: kapsle's side of the ISM8i, on `wolf-ism8`'s server — config, raw kinds for boiler, system, direct circuit, mixer circuits and modules 1–3, write mapping, liveness to `reachable`.
**Done when:** 12f designed.
**Refs:** design/libs 01 · research/19 · 05a

### M3.3e — Central heating driver   `area/heating`
`driver-central-heating`: the building's heating as one system, on the boiler-room PLC. Circuits (mixers 1–5, 1–3 through 12f) and zones (rooms → valves on Unipi outputs). Answers zone requests from thermostats: valve duty cycle, exercise, flow guard (one circuit open or a bypass), summer and availability, setpoint correction on mixers 1–3, fallback to open valves when requests stop. Knows no room temperature. How 12c-08's `thermal-valve-from-output` relates to it. Holds the desired state per circuit and writes through 12f only on a difference — a whole 0.5 K step with hysteresis, at most every 30 min per circuit (12f §5.2).
**Done when:** 12h designed; M3.3b's zone contract matches it.
**Refs:** research/matter/11 §5, §7 · research/matter/09 §4.3 · 12c-08 · 12f · 08 · 09

### M3.3f — AirGENIO driver and ventilation   `area/ventilation`
`driver-airgenio`: a 2VV heat recovery unit with AirGENIO COMFORT control over Modbus RTU, through a Raw Relay Driver — raw devices `airgenio.unit`, `.service`, `.info`; polling, writes, external changes, the unit's timer and clock, service settings and software reset, commissioning. Home side: `Fan` for fans on Unipi outputs and `VentilationUnit` with demand control on the rooms' CO₂, boost, away, night ventilation; Matter as Fan.
**Done when:** 12j and 12c-12 designed; 12a §2.2, 12a §3, 16a and 12c-02 agree.
**Refs:** research/16 · research/matter/12 · 07 §4, §6, §7 · 07a §4, §8 · 12a §3 · 12c-10

### M3.4 — Almanac driver   `area/almanac`
Calendar, clock, sun position, light %, weather forecast, warnings, air. Data sources, offline behaviour. One master per site, replicas on the other PLCs. Home devices `Calendar`, `Clock`, `Sun`, `WindSensor`, `RainSensor`, `Weather`; schedules are rules on `Clock`. A wind DeviceType for `WindowCovering`'s `wind` role (12c-06 §3.4). A rain forecast for the rainwater driver's early transfer (12i §11).
**Done when:** 12d and 12c-13 designed; 12c-06 §3.4 and 12i §11 have no Open; 12c-05, 12c-08 and 12c-10 point schedules to rules on `Clock`; 12a §2.2 and 16a agree.
**Refs:** research/17 · 05a · 12a · 12b · 12i · 12c-06

### M3.5 — APIs: common contract and API plugins   `area/api`
What every api must do, whatever it speaks, and how a new one is written. Terms: API module, API plugin, WS extension, relay and mapping apis. State: translation state rebuilt, protocol identity state in `api.<id>`. The gate: auth and ACL in the api; `actor` and `proof` annotations for a driver that needs the user. Consuming drivers: `links()`/`onLink`, introspection, driver loss and return as a client sees it. Errors relayed or mapped. Listening without a declaration. Placement. `ws-kit` as the base of the WS API and the Home API. Writing an api, with MQTT as the example. Absorbs 18 API plugins.
**Done when:** 13 designed; 18 holds the Home API memo; 01 §8, 03 §4, 05a §3.1/§3.1a/§4, 12c-09 §1.2 and M3.6, M3.8, M5.4 agree.
**Refs:** 13 · 18 · 01 §2, §8, §9 · 02 §4–§5 · 03 · 05a §3.1a, §4b · 06 §5a · 12c-09 §1.2 · 16a

### M3.6 — Auth & ACL framework   `area/auth`
A library APIs use, not an API. Upstream identity provider (authentik). Users, roles, keys, devices, client credentials (PLC to PLC). Authentication: SSO, password, PIN, biometrics; local vs full. Assurance levels and how an API reacts (PIN for a lock): what 13's `proof` asks of a caller and how a WS extension fills `actor` (13 §5, 12c-09 §1.2). The same proof for an access closure's `open` (`AccessClosure`, 12c-07). `driver-auth` with its own SQLite file. Matter exposure of `DoorLock` and access closures moved to M5.6. Example flows, including mobile apps and biometrics.
**Done when:** 13a designed; research doc for the identity provider exists.
**Refs:** 13 · 15 · 06 §5a · 12a §4b, §6 · 12c-07 §6 · 12c-09 §1.2

### M3.7a — Main driver, dynamic config and bootstrap   `area/main`
Configuration written from the Inspector; a static-only configuration stays possible. The static and the dynamic file merged by instance id; static instances are read-only; `drivers: ['*']`. The `main` driver: one per system, in a worker, with a control channel to `main` — config, instances, plugins; validate, apply, revisions, rollback, restart, reload. Secrets marked `sensitive`, kept in a secrets file, read back as refs. The bootstrap api sets up the first WS API and then redirects to it. Values and schemas in their own chapter, used for config too: `ValueType` replaces zod; `checkValue`, `rules`, `helpMd`. What the SPA does when the api serving it reloads. Backup as an admin procedure, stated for developers to write the user docs from. Plugin install: shape only.
**Done when:** 02a and 03a designed; 01, 02, 03 §8, 04 §3, 05a, 08 §2, 13 and the 15 and 16 memos agree; `TypedCodec`/`Codecs` renamed to `ValueType`/`Values` everywhere; 02a states the backup procedure.
**Refs:** 01 §2–§4 · 02 · 03 §8–§11 · 04 §3, §7 · 03a · 05a §3.1 · 06 §5a · 08 §2 · 13 · 15 · 16

### M3.7b — Plugins: general rules   `area/plugins`
Every plugin kind in the system in one place — drivers, apis, WS extensions, device types, templates, rule kinds, UI plugins — and the rules they share: manifest, descriptor, config, links, versions. Nested plugin config — a plugin's config inside a module's config (DALI `ctrl`, a WS api's extensions) — and how `validate` and the forms see it. Plugin packages managed from the Inspector: install, update, remove. Then each plugin kind's doc is refined against these rules.
**Done when:** 02b designed; the docs of each plugin kind agree with it; the nested-config Open in STATUS is closed.
**Refs:** 01 §10 · 02 §4 · 02a · 03 §8 · 03a · 05a · 12 · 12a · 13 §2 · 15

### M3.8 — WS API   `area/api`
Renamed from nextgen. Relays internal messaging. `ws-kit` (13 §2): sessions, hello, relay, fan-out, WS extensions (the contract in 15). The Home API is built on it too. Auth and ACL as WS extensions using 13a, reacting to `actor` and `proof` (13 §5). The hello advertises `kapsleVersion` (12a §4b). Session language (`hello.lang`, `Accept-Language`, `setLang`) and resolving `LocalizedText` at the edge (03a §4, 04 §7) as the `l10n` WS extension, in 13c. Message size, for a `.tgz` uploaded to `installPackage` (02b §12).
**Done when:** 15 and 13c designed; 15 renamed; `api-nextgen` renamed in docs.
**Refs:** 03 · 04 §7 · 03a §4 · 13 · 13a · 15

### M3.9 — Inspector UI: basics and plugin contract   `area/ui`
Structure, logic, wireframes, mobile vs desktop, frameworks, design guide. Basic controls for raw driver-kit devices. Logs. Generic forms from annotated schemas and `$refs` (03a §4, 05a §3.10); a ref filter that depends on another field of the same form (DALI bus → gear). The plugin contract: the `inspector-panel` kind and how the SPA loads it (02b §5.2). Plugin management view (02a §2.5); who uses a plugin outside config (02b §12). A standalone SPA — loading in the shell app is M5.2. The main plugins are M5.3.
**Done when:** 16 designed, wireframes committed; 17 holds the plugin contract.
**Refs:** 15 · 02a §2.5 · 02b · 05a · 04 · 11

### M3.14 — Documentation revision   `area/docs`
Numbering and reorganisation per the map above, M5's docs included — before code cites sections. Memo text removed from every doc designed in M3. Links, forward references. Brevity, examples, binding definitions. AGENTS.md: the Tester role.
**Done when:** link check is clean; no forward reference without a target; no memo text left in docs designed in M3; AGENTS.md Tester role defined.
**Refs:** dev README §4 · AGENTS.md

### M3.15 — Packages & dependencies   `area/packages`
Revisit package definitions and bootstrapping. What is exposed, in which package, and who uses it. Adjust dependency-cruiser. Plugin package bootstrapping (02b §12): the host's `@kapsle/*` seen from a plugin generation, `npm` on the PLC, the daemon's install path.
**Done when:** basics/01 package list matches every design doc; `WORKSPACE_DEPS` covers every designed package.
**Refs:** basics/01 · 01 §11 · 02b §9, §12 · `.dependency-cruiser.cjs`

### M3.16 — Testing: unit test review   `area/testing`
**Done when:** basics/03 tier 1 rules match the final design.
**Refs:** basics/03

### M3.17 — Testing: Modbus simulator   `area/testing`
The Modbus simulator: Unipi board and extensions from the register-map corpus, RS-485 line behaviour, fidelity policy, stub drivers and apis. 1-Wire and DALI are M5.7.
**Done when:** `design/simulator` README, 01 and 03 designed.
**Refs:** design/simulator · 07 · 07a · 07b

### M3.21 — Development plan   `area/plan`
Plan M4 — core implementation: which packages, in which order, each with its tests.
**Done when:** `milestones/M4-*.md` exists; M4 is `planned` in `roadmap.md`.
**Refs:** this file · `STATUS.md`
