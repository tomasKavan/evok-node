# 12c — Home main devices

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo. Content is written below this memo,
> section by section; the memo is removed when M3.3 closes.
>
> **Last step of M3.3:** replace this memo with the index of `12c-Home-main-devices/` and §1 common
> conventions.

**Files** — one per type group, in [`12c-Home-main-devices/`](12c-Home-main-devices/):

| File | Types |
|---|---|
| [`12c-01-Lights.md`](12c-Home-main-devices/12c-01-Lights.md) | `OnOffLight`, `DimmableLight`, `ColorTemperatureLight`, `ExtendedColorLight` |
| [`12c-02-Plug-in-units.md`](12c-Home-main-devices/12c-02-Plug-in-units.md) | `OnOffPlugInUnit` |
| [`12c-03-Generic-switch.md`](12c-Home-main-devices/12c-03-Generic-switch.md) | `GenericSwitch` |
| [`12c-04-Sensors.md`](12c-Home-main-devices/12c-04-Sensors.md) | `ContactSensor`, `OccupancySensor`, `TemperatureSensor`, `HumiditySensor`, `LightSensor`, `AirQualitySensor` |
| [`12c-05-Timer-relay.md`](12c-Home-main-devices/12c-05-Timer-relay.md) | `TimerRelay` |
| [`12c-06-Window-covering.md`](12c-Home-main-devices/12c-06-Window-covering.md) | `WindowCovering` |
| [`12c-07-Closures.md`](12c-Home-main-devices/12c-07-Closures.md) | `Closure` |
| [`12c-08-Water.md`](12c-Home-main-devices/12c-08-Water.md) | `WaterValve`, `IrrigationSystem`, `WaterLeakDetector` |
| [`12c-09-Door-lock.md`](12c-Home-main-devices/12c-09-Door-lock.md) | `DoorLock` |
| [`12c-10-Climate.md`](12c-Home-main-devices/12c-10-Climate.md) | `Thermostat`, `RoomAirConditioner` |
| [`12c-11-Rainwater-tank.md`](12c-Home-main-devices/12c-11-Rainwater-tank.md) | `RainwaterTank` |
| [`12c-12-Ventilation.md`](12c-Home-main-devices/12c-12-Ventilation.md) | `Fan`, `VentilationUnit` |

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
| §2.2 prose | the `lastEvent` press sequences, how `move` works, the `Timer` paragraph (moved: 12c-05) | the general rules: no `'@'`, one round trip, every reading/channel `subscribe: true`, staleness folds into `reachable`, no stub fields |
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
| `GenericSwitch` | Generic Switch | momentary only; one template, `switch-from-di` |
| `OnOffLight` | On/Off Light | |
| `DimmableLight` | Dimmable Light | |
| `ColorTemperatureLight` | Color Temperature Light | |
| `ExtendedColorLight` | Extended Color Light | one template, `tunable-rgbw-4dali` |
| `OnOffPlugInUnit` | On/Off Plug-in Unit | |
| `TimerRelay` | — | virtual, no roles; rules start it and react to it; `onFor` stays on lights and plug-in units |
| `WindowCovering` | Window Covering | 0.01 % closed, as Matter; optional tilt; templates `cover-from-relays`, `cover-from-klf`; wind protection built in |
| `Closure` | Closure | one type for windows, garage doors, gates (`kind` → Matter tags); templates `closure-from-klf`, `closure-from-uap` (Hörmann UAP1-HCP: pulses for open/close/stop, end contacts, optional travel contact); bundle `velux-klf` with `cover-from-klf`; access kinds (`garageDoor`, `gate`, `door`) not on Matter yet. Open: proof for `open` → M3.6 |
| `DoorLock` | Door Lock | released for a time, locks by itself, door contact; `lastOperation` with the acting user; `lock-from-relay`, `lock-from-2n`; not on Matter yet. Open: proof and principal (M3.6), 2N roles (M3.6a) |
| `WaterValve` | Water Valve | Matter-shaped `open`/`close`, timed, `maxOpenS`, always closed after a restart; templates `valve-from-output`, `thermal-valve-from-output` (level as a duty cycle); not shown by Apple Home |
| `IrrigationSystem` | Irrigation System | zones are `WaterValve`s, one at a time; master valve, pump; no schedules. With a rainwater driver the master is its supply valve (12c-11 §3.2) |
| `ContactSensor` | Contact Sensor | one template, `contact-from-di` |
| `WaterLeakDetector` | Water Leak Detector | one template, `leak-from-di`; no latch |
| `TemperatureSensor` | Temperature Sensor | `unipi.temp` (1-Wire, xG18, IAQ) or `unipi.ai` (Pt1000, linear) |
| `HumiditySensor` | Humidity Sensor | `unipi.humidity` or `unipi.ai` |
| `AirQualitySensor` | Air Quality Sensor | level derived from CO₂ / VOC index; optional `co2`, `pm25`, `vocIndex`, `temperature`, `humidity`; IAQ as a bundle (`iaq-unipi`) |
| `OccupancySensor` | Occupancy Sensor | one template, `occupancy-from-di`; `HoldTime` read-only — Open, M3.13 |
| `LightSensor` | Light Sensor | `unipi.lux` or `unipi.ai` |
| `RoomAirConditioner` | Room Air Conditioner | the controller of a room with an AC: thermostat fields + the unit, `policy` (AC first above an outdoor breakpoint), stage 2, lockouts, window, `boost`, compensated AC setpoint; `room-ac-from-mimb19n` from driver-mimb19n (12c-10) |
| `Thermostat` | Thermostat | the controller of a room without an AC: the shared thermostat fields, a 12h zone over a `RemoteLink`; template `thermostat` (12c-10) |
| `RainwaterTank` | — | overview and simple control of the rainwater driver (12i); templates `tank-from-rainwater`, `valve-from-rainwater-supply` (`WaterValve`, irrigation master), `leak-from-rainwater-alarm` (`WaterLeakDetector`, retention alarm), bundle `rainwater` — all shipped with that driver |
| `Fan` | Fan | on/off, low/medium/high, %; templates `fan-from-relay`, `fan-from-relays` (one tap at a time), `fan-from-ao` (12c-12) |
| `VentilationUnit` | Fan | a heat recovery unit: `Fan` fields + auto (demand control on rooms' CO₂), boost, away, night ventilation, temperatures, filter, fault; `ventilation-from-airgenio` from driver-airgenio (12j). Open: Fan vs Air Purifier → M3.13 (12c-12 §6) |

**Deferred:** `Pump` — a relay pump is an `OnOffPlugInUnit`.

**Inputs:** 12a §2–§4a · 12b §2 · 16a · research/matter · source drivers' `DeviceType`s (08, 09, 10, 12)
