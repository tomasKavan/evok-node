# M5 — Design II

Design the parts M3 left out of the core. Tasks run in the order listed.

**A design task is done when:** the document has no memo banner; it has no **Open:** item, or each one is deferred with a reason and the task that closes it; documents citing it are updated; `STATUS.md` is updated.

Target numbering is [M3's document map](M3-design.md#document-map).

## Tasks

### M5.1 — 2N access driver   `area/2n`
A driver for 2N Access Unit 2.0 / IP Verso 2.0 over the HTTP API: switches, door state, I/O, events over `log/subscribe`/`log/pull`, `grantaccess` for a user. API account and secrets via 13a. Map from the identity provider's users to 2N users; the 2N's users come from the identity provider through Access Commander — the driver never writes the 2N directory. DeviceTypes for `lock-from-2n`'s roles.
PINs: the identity provider drives Access Commander's directory, the clear PIN readable only by its LDAP account (13a) — and a PIN uniqueness check that leaks nothing, with generated PINs (13a §16).
**Done when:** 12e designed; 12c-09 §3.2 has no Open.
**Refs:** research/matter/08 §4 · 12c-09 §3.2 · 13a · 05a

### M5.2 — Shell app (mobile/desktop)   `area/shell-app`
What it is and how it's used. Multi-user, multi-PLC, multi-app: what an app (inspector, Home UI) must provide to load in the shell. Platforms, framework. Authorization via 13a, biometrics. Push notifications, Matter BLE pairing. Route choice — LAN by mDNS, else the canonical name — discovery of advertised nodes and enrolment by the node key (13a).
**Done when:** 13b designed; framework research doc exists.
**Refs:** 13a · 16 · 19

### M5.3 — Inspector UI: plugins   `area/ui`
Main plugins on M3.9's contract: unipi system, unipi local, unipi extension, DALI (with commissioning workflow), Home config and control.
**Done when:** 17 holds the main plugins.
**Refs:** 16 · 17 · 08 · 09 · 11 · 12 · 12a

### M5.4 — Home API   `area/api`
On `ws-kit` (13 §2); understands only the home driver. Relays the subset of management 12a §5 lists. Storage for WS clients' own data in ws-kit, for both the WS API and the Home API (13 §6).
**Done when:** 18 designed; 13 §6 has no Open.
**Refs:** 15 · 12a · 12b · 13a

### M5.5 — Home UI   `area/ui`
Structure, logic, typical users, wireframes, mobile vs desktop vs kiosk, frameworks, design guide. UX is the priority. Grouping (rooms, topics). Limited set of controls, all defined. Rule definition. Matter pairing.
**Done when:** 19 designed, wireframes committed.
**Refs:** 18 · 12a §6 · 12b · 12c · 13b

### M5.6 — Matter bridge API   `area/api`
Exposes home devices as Matter bridged devices. Exposure of `DoorLock` and `AccessClosure` with their proof (12c-09 §4, 12c-07 §4, research/auth/07 D23).
**Done when:** 20 designed (from 16a).
**Refs:** 16a · 12a · 12c · 13

### M5.7 — Testing: 1-Wire and DALI simulators   `area/testing`
On M3.17's Modbus simulator: 1-Wire buses, DALI buses.
**Done when:** `design/simulator` 02 and a DALI file designed.
**Refs:** design/simulator · 10 · 12

### M5.8 — Test rig: hardware design and wiring   `area/rig`
**Done when:** schematic and wiring committed under `design/test-rig`.
**Refs:** design/test-rig · research/09

### M5.9 — Test rig: master unit controller and testing software   `area/rig`
**Done when:** `design/test-rig` controller and software designed.
**Refs:** design/test-rig · basics/03 §1.3

### M5.10 — Test rig: test definition   `area/rig`
Includes the performance baseline (idle CPU, scan timing, API latency) — no capture from stock EVOK.
**Done when:** test definition format, initial test set and baseline designed.
**Refs:** design/test-rig · basics/03 §2
