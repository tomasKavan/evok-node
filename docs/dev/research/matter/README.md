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
| [`04-sensors.md`](04-sensors.md) | Contact, Light, Occupancy, Temperature, Humidity, Air Quality Sensor: encodings, occupancy hold time, concentration clusters, multi-sensor composition, Apple Home limits |

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
| Thermostat `0x0301`, Heating/Cooling Unit `0x0300` | 1.0 | yes [V] | S2 |
| Fan `0x002B`, Air Purifier `0x002D` | 1.2 | yes [V] | S2 |
| Water Leak Detector `0x0043` | 1.3 | yes, iOS 18.4 [V] | S3 |
| Room Air Conditioner `0x0072` | 1.0 | [GAP] — not in S2's list, which may be outdated | S2 |
| Water Valve `0x0042` | 1.3 | no [V] — workaround seen: On/Off Plug-in Unit | S1 |
| Pump `0x0303` | 1.0 | no [V] | S3 |
| Soil Sensor | 1.5 | no [V] | S1 |

Irrigation has no device type of its own [V]: Water Valve zones plus Soil Sensor (S4).

## 3. Sources

- S1 — Apple developer forum, "Apple Home rejects Matter device types 0x0042 (Water Valve) and Soil Sensor": https://developer.apple.com/forums/thread/844622
- S2 — connectedhomeip `docs/guides/darwin.md`, supported device types (says it may be out of date): https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/docs/guides/darwin.md
- S3 — Matter Alpha, iOS 18.4 adds smoke, CO and water leak sensors; no pressure, flow sensors or pumps: https://www.matteralpha.com/manufacturer-news/ios-18-4-expands-matter-support-with-smoke-co-and-water-leak-sensors
- S4 — CSA, Matter 1.5 announcement: https://csa-iot.org/newsroom/matter-1-5-introduces-cameras-closures-and-enhanced-energy-management-capabilities/
- S5 — matter-smarthome.de, device types by Matter version: https://matter-smarthome.de/en/development/these-device-types-are-available-in-the-matter-standard/
