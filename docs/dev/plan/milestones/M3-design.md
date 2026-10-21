# M3 — Design

Design every part of the system before development starts. Tasks run in the order listed.

**A design task is done when:** the document has no memo banner; it has no **Open:** item, or each one is deferred with a reason and the task that closes it; documents citing it are updated; `STATUS.md` is updated.

## Document map

Target numbering in `design/evok-node/` once M3 is done.

| Doc | Content | Today |
|---|---|---|
| 12a | HA composite driver | 12a |
| 12b | HA composite rules | 12b |
| 12c | HA composite main devices | new |
| 12d | Almanac driver | new |
| 13 | APIs — common to all, API plugins | 13 + 18 |
| 13a | Auth & ACL framework | new |
| 13b | Shell app (mobile/desktop) | new |
| 14 | REMOVED | Compat API |
| 15 | WS API | 15 Nextgen API |
| 16 | Inspector UI | 16 |
| 17 | Inspector UI plugins | 17 |
| 18 | HA composite API | 18 API plugins |
| 19 | HA control UI | new |
| 20 | Matter bridge API | 16a |

## Tasks

### M3.1 — Scope: retire compat API, revise goals and non-goals, fix broken paths   `area/scope`
Drop EVOK API compatibility and the config migration tool. Rewrite goals and non-goals: evok-node is a PLC runtime with its own APIs, home automation, rules and UIs. Fix broken links across `docs/`, READMEs and fixtures.
**Done when:** no document claims EVOK compatibility or a migration path; 14 is REMOVED; link check finds only links to not-yet-created packages.
**Refs:** design README · root README · dev README · 01 §11 · basics/01 §3

### M3.2 — HA composite driver: finalize   `area/hacomposite`
Templates and devices — general rules, what is stored, what the UI cannot control. Tails for `local`/`matter` origins. Management split by API kind (inspector vs controller). Device options as JSON in method argument types. Final driver name. Matter mapping table.
**Done when:** 12a has no **Open:**; 20 (16a) holds the mapping table.
**Refs:** 12a §2–§5 · 05a §3.1 · 16a

### M3.3 — HA composite: main devices   `area/hacomposite`
Deep dive per device type: switch, light (on/off, dimmable, COB), window cover, lock, AQ sensor, temperature sensor, occupancy sensor, light sensor, AC unit. Fields, templates, Matter counterpart.
**Done when:** 12c covers every listed type; 12a §2.2 and the 20 mapping table agree with it.
**Refs:** 12a §2–§3 · 16a

### M3.4 — Almanac driver   `area/almanac`
Calendar, weather forecast, sun position. Data sources, offline behaviour. Respective HA composite devices.
**Done when:** 12d designed; new device types added to 12c.
**Refs:** 05a · 12a · 12b

### M3.5 — APIs: common contract and API plugins   `area/api`
What every API must do, whatever it speaks. API as plugin, the same mechanism as drivers. Absorbs 18 API plugins.
**Done when:** 13 designed; 18's content moved into 13.
**Refs:** 13 · 18 · 01 §9 · 02 §4–§5 · 03

### M3.6 — Auth & ACL framework   `area/auth`
A library APIs use, not an API. Upstream identity provider (authentik). Users, roles, keys, devices, client credentials (PLC to PLC). Authentication: SSO, password, PIN, biometrics; local vs full. Assurance levels and how an API reacts (PIN for a lock). Local DB as a new driver kind. Example flows, including mobile apps and biometrics.
**Done when:** 13a designed; research doc for the identity provider exists.
**Refs:** 13 · 15 · 06 §5a · 12a §4b

### M3.7 — Shell app (mobile/desktop)   `area/shell-app`
What it is and how it's used. Multi-user, multi-PLC, multi-app: what an app (inspector, HA control) must provide to load in the shell. Platforms, framework. Authorization via 13a, biometrics. Push notifications, Matter BLE pairing.
**Done when:** 13b designed; framework research doc exists.
**Refs:** 13a · 16 · 19

### M3.8 — WS API   `area/api`
Renamed from nextgen. Relays internal messaging; per-connection and per-request plugins. Other APIs built on top of it. Authorization through a plugin using 13a.
**Done when:** 15 designed and renamed; `api-nextgen` renamed in docs.
**Refs:** 03 · 13 · 13a · 15

### M3.9 — Inspector UI: basics   `area/ui`
Structure, logic, wireframes, mobile vs desktop, frameworks, design guide. Basic controls for raw driver-kit devices. Logs.
**Done when:** 16 designed, wireframes committed.
**Refs:** 15 · 05a · 04 · 11

### M3.10 — Inspector UI: plugins   `area/ui`
Plugin approach. Main plugins: unipi system, unipi local, unipi extension, DALI (with commissioning workflow), HA composite config and control.
**Done when:** 17 designed.
**Refs:** 16 · 08 · 09 · 11 · 12 · 12a

### M3.11 — HA composite API   `area/api`
Subset of the WS API; understands only the HA composite driver.
**Done when:** 18 designed.
**Refs:** 15 · 12a · 12b · 13a

### M3.12 — HA control UI   `area/ui`
Structure, logic, typical users, wireframes, mobile vs desktop vs kiosk, frameworks, design guide. UX is the priority. Grouping (rooms, topics). Limited set of controls, all defined. Rule definition. Matter pairing.
**Done when:** 19 designed, wireframes committed.
**Refs:** 18 · 12a §6 · 12b · 12c · 13b

### M3.13 — Matter bridge API   `area/api`
Exposes HA composite devices as Matter bridged devices.
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
**Done when:** test definition format and initial test set designed.
**Refs:** design/test-rig · basics/03 §2

### M3.21 — Development plan   `area/plan`
Define M4 and later.
**Done when:** `roadmap.md` lists M4+; each has a milestone file.
**Refs:** this file · `STATUS.md`
