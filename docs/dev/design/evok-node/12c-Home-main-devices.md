# 12c — Home main devices

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo. Content is written below this memo,
> section by section; the memo is removed when M3.3 closes.

**Job:** one section per home `DeviceType`: fields, built-in templates and Matter mapping, in full.
12a holds what every type shares; this file holds what one type adds.

**Not here — stays in 12a / 16a:** `CommonFields`, `exposed`/`controllable`, tags (12a §2.1);
the template mechanism and multi-source roles (12a §3); the general Matter binding rule — a `SET`
stores the target, error mapping (12a §4a); the device-level mapping table (16a).

**Moves here from 12a** (12a keeps a link, never a copy). Each part moves when its type's section
is written, so 12a never points at an empty section:

| From | What moves | What stays in 12a |
|---|---|---|
| §2.2 table | the "Fields beyond `CommonFields`" column | the list of types (kind → 12c section); the Matter counterpart is in 16a |
| §2.2 code | `SwitchState`, `GenericSwitch`, `DimmableLight`, the shared `onOffField`/`levelField`/`moveField`/`stopField` | — |
| §2.2 prose | the `lastEvent` press sequences, how `move` works, the `Timer` paragraph | the general rules: no `'@'`, one round trip, every reading/channel `subscribe: true`, staleness folds into `reachable`, no stub fields |
| §2.3 | — | the whole rule; `multiPressMax` stays as its example |
| §3 | the list of built-in templates per type, the `switch-from-di` and `dimmable-from-dali` workflows | the template mechanism; roles in its examples stay as one-line illustrations |
| §4a | — | the general binding rule; "only a field that moves on its own changes step by step" |

**§1 Common conventions** — only what several types share and 12a doesn't say: units and
resolution vs Matter (0.01 °C, Percent100ths, log lux), the moving-device pattern
`{current, target, motion}`, `unknown` in enums.

**Section shape, per type:**

| Sub | Holds |
|---|---|
| Intro | what the device is for, and what it is not |
| Fields | `device(...)` in TS, units, ranges |
| Templates | built-in ones: kind, roles, settings, and the workflow — what it does on each source change and each `SET`/call |
| Matter | field ↔ attribute/command/event, value conversion. Part of the mapping table (16a, `driver-home/matter-map`). A type with none says so |
| Moving/target | what `GET`/subscribe report while the device moves to its target (Matter `CurrentLevel` and its like) |

**Types and what is known to be open:**

| DeviceType | Matter | Known now |
|---|---|---|
| `GenericSwitch` | Generic Switch | Apple Home: momentary only |
| `OnOffLight` | On/Off Light | |
| `DimmableLight` | Dimmable Light | |
| `ColorTemperatureLight` | Color Temperature Light | |
| `ExtendedColorLight` | Extended Color Light | no templates — `matter` origin only |
| `OnOffPlugInUnit` | On/Off Plug-in Unit | a relay load that isn't a light: socket, pump, fan |
| `TimerRelay` | — | today `Timer` (12a §2.2). Name, and separate device vs `onFor` on outputs, decided here |
| `WindowCovering` | Window Covering | % direction (Matter: 0 = open); tilt for venetian blinds; position from travel time on two relays |
| `DoorLock` | Door Lock | PIN and assurance level → 13a (M3.6) |
| `WaterValve` | Water Valve | irrigation zones; Matter auto-close (`OpenDuration`); not supported by Apple Home |
| `ContactSensor` | Contact Sensor | |
| `WaterLeakDetector` | Water Leak Detector | |
| `TemperatureSensor` | Temperature Sensor | |
| `HumiditySensor` | Humidity Sensor | |
| `AirQualitySensor` | Air Quality Sensor | enum only, or concentrations (CO₂, PM2.5, TVOC) too |
| `OccupancySensor` | Occupancy Sensor | |
| `LightSensor` | Light Sensor | |
| `RoomAirConditioner` | Room Air Conditioner | one `setpoint` vs Matter's heat/cool setpoints; source: extension-driver device or a new Modbus driver; Apple Home support unverified |

**Decided in their own section:** `Thermostat` — what it adds over `TemperatureSensor` +
`WaterValve`; `Fan` — fit for heat recovery units; `Pump` — deferred, a relay pump is an
`OnOffPlugInUnit`.

**Not a type:** irrigation — `WaterValve` zones + rules (12b) + almanac (12d).

**Inputs:** 12a §2–§4a · 12b §2 · 16a · research/matter · source drivers' `DeviceType`s (08, 09, 10, 12)
