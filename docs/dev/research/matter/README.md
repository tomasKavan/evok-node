# Matter research

**Research, not design.** Facts about Matter device types that home `DeviceType`s (12a, 12c) map to. Evidence tags as in [`../README.md`](../README.md): [V], [V-src], [I], [GAP].

Spec baseline: **Matter 1.5** (released 2025-11-20). A type added later than 1.0 says so.

## 1. Files

One file per device group, numbered as they are written. Each covers: how the spec defines the device (clusters, mandatory/optional features), how it should behave, real devices on the market and known experiences, Apple Home support.

| File | Contents |
|---|---|
| [`01-lights.md`](01-lights.md) | On/Off, Dimmable, Color Temperature, Extended Color Light |
| [`02-plug-in-units.md`](02-plug-in-units.md) | On/Off Plug-in Unit, Mounted On/Off Control; dimmable variants for comparison |
| [`03-generic-switch.md`](03-generic-switch.md) | Generic Switch, Switch cluster: features, event sequences, timing, matter.js, controllers, multi-button tags |
| [`04-sensors.md`](04-sensors.md) | Contact, Light, Occupancy, Temperature, Humidity, Air Quality Sensor: encodings, occupancy hold time, concentration clusters, multi-sensor composition, Apple Home limits; Unipi sources (DI, AI, 1-Wire, xG18, IAQ) |
| [`05-timer-relay.md`](05-timer-relay.md) | No Matter timer device type; countdown elements in other clusters and their reporting; controllers (Apple, Google, Home Assistant `timer`); timer-relay functions in PLCs, KNX, DIN-rail relays, Node-RED, Shelly; behaviour across a restart; EVOK's software timed output |
| [`06-window-covering.md`](06-window-covering.md) | Window Covering: lift/tilt features, positions (0 = open), commands, status and safety bits, 1.5 closures; controllers; time-based covers on two relays (travel, tilt, overrun, reverse pause, reference, drift) in KNX, Loxone, Shelly, ESPHome; wind thresholds, hysteresis, fail-safe, forecast vs anemometer |
| [`07-garage-door.md`](07-garage-door.md) | Garage door: no type before 1.5; Closure `0x0230` with tag `GarageDoor`, Closure Control states, timed `MoveTo`, 1.7 Access feature; Closure Panel / Closure Dimension; gating open by latch or a Door Lock child; controllers and the Window Covering fallback; Hörmann UAP1-HCP on SupraMatic 4 (inputs, K01–K03, menu 30, drive safety); state from end contacts; ESPHome, Loxone, HomeKit; UL 325, EN 12453, open vs close access |
| [`08-door-lock.md`](08-door-lock.md) | Door Lock: features (`USR`, `PIN`, `COTA`, `DPS`, `UBOLT`), unlock vs unbolt vs unlatch, remote PIN and lockout, events, users and credentials, auto-relock, matter.js `DoorLockServer`; controllers (Google needs a PIN for remote unlock, Apple has no unlatch); relay-driven locks (strikes fail-secure/fail-safe, motor locks, pulse vs hold); 2N Access Unit 2.0 / IP Verso 2.0 HTTP API (switches, door, `log/pull` events, access points, directory, Access Commander) |
| [`09-water.md`](09-water.md) | Water Valve, Valve Configuration and Control (durations, level, faults), Irrigation System (1.5), Water Leak Detector, Rain, Freeze, Boolean State Configuration; controllers; solenoid and thermal actuators, irrigation sequencing, heating PWM and valve protection, tank filling, 3-way valves; leak modules on a DI, leak alarms |
| [`10-roof-window.md`](10-roof-window.md) | VELUX roof window and its cover behind a KLF 150 on Unipi RO/DI: inputs (pulse vs hold, both = stop), 2 s success output, timing, rain sensor, moves evok-node can't see; Matter Closure with `Window` + `Roof` tags, Closure Panel for %; window–cover interlock |
| [`11-thermostat.md`](11-thermostat.md) | Thermostat, Room Air Conditioner, Fan Control: features, deadband, presets, AC attributes, 1.6–1.7 additions; controllers and products (ACs ship as Thermostat); one room with several sources — KNX stages, Loxone, dual fuel, Home Assistant, AC setpoint compensation, overrides; weather-compensated heating with room valves; Samsung WindFree Avant 2 over MIM-B19N; Wolf ISM8i datapoints |

## 2. Apple Home support

Apple publishes no complete list; this one is collected per type. "no" means Apple Home refuses to add it ("device not supported").

| Matter device type | Since | Apple Home | Source |
|---|---|---|---|
| On/Off Light `0x0100`, Dimmable Light `0x0101`, Color Temperature Light `0x010C`, Extended Color Light `0x010D` | 1.0 | yes [V] | S2 |
| On/Off Plug-in Unit `0x010A`, Dimmable Plug-in Unit `0x010B` | 1.0 | yes [V] | S2 |
| Mounted On/Off Control `0x010F`, Mounted Dimmable Load Control `0x0110` | 1.4 | [GAP] — not in S2's list; spec recommends also listing the Plug-in Unit type | S2 |
| Generic Switch `0x000F` | 1.0 | yes, momentary only [V] | S2 |
| Contact, Light, Occupancy, Temperature, Humidity Sensor; Air Quality Sensor `0x002C` | 1.0 / 1.2 | yes [V]; limits per reading and endpoint shape — [`04-sensors.md`](04-sensors.md) §6, §8 | S2 |
| Door Lock `0x000A`, Window Covering `0x0202` | 1.0 | yes [V] | S2 |
| Closure `0x0230` (garage door, gate, …) | 1.5 | [GAP] — not found; SmartThings works, Home Assistant not yet ([`07-garage-door.md`](07-garage-door.md) §2) | — |
| Thermostat `0x0301`, Heating/Cooling Unit `0x0300` | 1.0 | yes [V] | S2 |
| Fan `0x002B`, Air Purifier `0x002D` | 1.2 | yes [V] | S2 |
| Water Leak Detector `0x0043` | 1.3 | yes, iOS 18.4 [V] | S3 |
| Room Air Conditioner `0x0072` | 1.0 | renders in 2026, but sends Cool instead of Auto [V]; not in S2's list ([`11-thermostat.md`](11-thermostat.md) §2) | S2, S7 |
| Heat Pump `0x0309` | 1.4 | [GAP] — not in S2's list; no product seen ([11 §3](11-thermostat.md)) | — |
| Water Valve `0x0042` | 1.3 | no [V] — workaround seen: On/Off Plug-in Unit; bridging doesn't help | S1, S6 |
| Irrigation System `0x0040` | 1.5 | [GAP] — not in S2's list | — |
| Rain Sensor `0x0044`, Water Freeze Detector `0x0041` | 1.3 | [GAP] — not in S2's list | — |
| Pump `0x0303` | 1.0 | no [V] | S3 |
| Soil Sensor | 1.5 | no [V] | S1 |

Irrigation System `0x0040` (1.5) is composed of Water Valve zone endpoints; a master valve is not an endpoint ([09 §1.3](09-water.md)) [V].

## 3. Sources

- S1 — Apple developer forum, "Apple Home rejects Matter device types 0x0042 (Water Valve) and Soil Sensor": https://developer.apple.com/forums/thread/844622
- S2 — connectedhomeip `docs/guides/darwin.md`, supported device types (says it may be out of date): https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/docs/guides/darwin.md
- S3 — Matter Alpha, iOS 18.4 adds smoke, CO and water leak sensors; no pressure, flow sensors or pumps: https://www.matteralpha.com/manufacturer-news/ios-18-4-expands-matter-support-with-smoke-co-and-water-leak-sensors
- S4 — CSA, Matter 1.5 announcement: https://csa-iot.org/newsroom/matter-1-5-introduces-cameras-closures-and-enhanced-energy-management-capabilities/
- S5 — matter-smarthome.de, device types by Matter version: https://matter-smarthome.de/en/development/these-device-types-are-available-in-the-matter-standard/
- S6 — Apple developer forum, "Home app rejects Matter device type 0x0042 (Water Valve) as 'not supported'" (Sep 2026): https://developer.apple.com/forums/thread/844646
- S7 — Apple developer forum, "Apple Home sends Cool instead of Auto for Matter Room AC device type (works correctly as Thermostat)": https://developer.apple.com/forums/thread/851099
