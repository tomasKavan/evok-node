# 12c — Home main devices

One section per home `DeviceType`: fields, built-in templates, Matter mapping, what it reports while it moves. 12a holds what every type shares (`CommonFields`, the template mechanism, the Matter binding rule); 16a holds the device-level mapping table. This file is the index of [`12c-Home-main-devices/`](12c-Home-main-devices/) and the conventions the types share.

## Index

| File | Types | Templates |
|---|---|---|
| [`12c-01-Lights.md`](12c-Home-main-devices/12c-01-Lights.md) | `OnOffLight`, `DimmableLight`, `ColorTemperatureLight`, `ExtendedColorLight` | `onoff-from-output`, `onoff-from-dali`, `dimmable-from-dali`, `dimmable-from-ao`, `tunable-white-2dali`, `tunable-rgbw-4dali` |
| [`12c-02-Plug-in-units.md`](12c-Home-main-devices/12c-02-Plug-in-units.md) | `OnOffPlugInUnit` | `plug-from-output` |
| [`12c-03-Generic-switch.md`](12c-Home-main-devices/12c-03-Generic-switch.md) | `GenericSwitch` | `switch-from-di` |
| [`12c-04-Sensors.md`](12c-Home-main-devices/12c-04-Sensors.md) | `ContactSensor`, `OccupancySensor`, `TemperatureSensor`, `HumiditySensor`, `LightSensor`, `AirQualitySensor` | `contact-from-di`, `occupancy-from-di`, `light-from-sensor`, `light-from-ai`, `temperature-from-sensor`, `temperature-from-ai`, `humidity-from-sensor`, `humidity-from-ai`, `air-quality-from-iaq`; bundle `iaq-unipi` |
| [`12c-05-Timer-relay.md`](12c-Home-main-devices/12c-05-Timer-relay.md) | `TimerRelay` | `timer` (no roles) |
| [`12c-06-Window-covering.md`](12c-Home-main-devices/12c-06-Window-covering.md) | `WindowCovering` | `cover-from-relays`, `cover-from-klf` |
| [`12c-07-Closures.md`](12c-Home-main-devices/12c-07-Closures.md) | `Closure` | `closure-from-klf`, `closure-from-uap`; bundle `velux-klf` |
| [`12c-08-Water.md`](12c-Home-main-devices/12c-08-Water.md) | `WaterValve`, `IrrigationSystem`, `WaterLeakDetector` | `valve-from-output`, `thermal-valve-from-output`, `irrigation`, `leak-from-di` |
| [`12c-09-Door-lock.md`](12c-Home-main-devices/12c-09-Door-lock.md) | `DoorLock` | `lock-from-relay`, `lock-from-2n` |
| [`12c-10-Climate.md`](12c-Home-main-devices/12c-10-Climate.md) | `Thermostat`, `RoomAirConditioner` | `thermostat`; `room-ac-from-mimb19n` (driver-mimb19n) |
| [`12c-11-Rainwater-tank.md`](12c-Home-main-devices/12c-11-Rainwater-tank.md) | `RainwaterTank` | `tank-from-rainwater`, `valve-from-rainwater-supply`, `leak-from-rainwater-alarm`; bundle `rainwater` — all driver-rainwater |
| [`12c-12-Ventilation.md`](12c-Home-main-devices/12c-12-Ventilation.md) | `Fan`, `VentilationUnit` | `fan-from-relay`, `fan-from-relays`, `fan-from-ao`; `ventilation-from-airgenio` (driver-airgenio) |
| [`12c-13-Almanac.md`](12c-Home-main-devices/12c-13-Almanac.md) | `Calendar`, `Clock`, `Sun`, `WindSensor`, `RainSensor`, `Weather` | `*-from-almanac`, `temperature-from-almanac`, `humidity-from-almanac`; bundle `almanac` — all driver-almanac |

Templates for these types shipped in other drivers' docs: `temperature-from-mimb19n-outdoor` (12g §6.2) and `temperature-from-ism8i-outdoor` (12f §6), both `TemperatureSensor`. A template without a driver named is `@evok-node/driver-home`'s.

**Deferred:** `Pump` — a relay pump is an `OnOffPlugInUnit`.

### Shape of a type file

| § | Holds |
|---|---|
| 1 Scope | what the device is for and what it is not; its behaviour per call |
| 2 Fields | `device(...)` in TS, units, ranges |
| 3 Templates | kind, roles, settings, and what it does on each source change and each `SET`/call |
| 4 Matter | field ↔ attribute/command/event, value conversion — the per-type part of the mapping table (16a, `driver-home/matter-map`). A type with none says so |
| 5 Moving and target | what `GET`/subscribe report while the device moves to its target |
| 6 Open | only when something is open |

### Deferred Opens

| Where | What | Closed by |
|---|---|---|
| 12c-04 §4 | Matter-writable attributes (`HoldTime`, a light's `behavior`, `DefaultOpenDuration`) through the device | M3.13 |
| 12c-07 §6 | proof for an access closure's `open`; gating by a `DoorLock` | M3.6 |
| 12c-09 §1.2, §3.2 | how a method needs proof and the principal reaches a template; 2N roles and user map | M3.6, M3.6a |
| 12c-10 §6 | preset setpoints editable by users; Matter writes; `0x0072` with controllers | M3.11, M3.12, M3.13 |
| 12c-12 §6 | Fan vs Air Purifier for `VentilationUnit` | M3.13 |
| 12c-13 §6 | built-in time rule kinds; a hardware `WindSensor` template | when first needed |

## 1. Common conventions

What several types share and 12a doesn't say. A type file states only where it departs.

### 1.1. Units

- **Natural units in the codec**, the unit in its `unit` annotation; 16a converts to Matter's encoding (exact rules: 12c-04 §4).

  | Value | Home field | Matter (16a converts) |
  |---|---|---|
  | temperature | `float32` °C | `int16` 0.01 °C |
  | illuminance | `float32` lx | `uint16` 10 000 × log₁₀(lx) + 1 |
  | humidity | `float32` % | `uint16` 0.01 % |

- **Kept in Matter's own units** where a conversion would only lose precision or invert a direction: a cover's or closure's position as `uint16` 0.01 % **closed** (0 = open, 10000 = closed), a light's `level` 1–254, colour temperature in mireds.
- **Percent:** a measured % is `float32` (`humidity`, a tank's `percent`); a commanded or computed % is `uint8` (a fan's `percent`, a valve's `level`, `hydronicLevel`).
- **The unit goes in the name** when the name doesn't already say it: `remainingMs`, `holdTimeS`, `defaultOpenS`, `boostMin`, `deadbandK`, `capacityL`, `acAboveC`. Durations in s where Matter has s (`onFor`, a valve's `open`), in ms where timing is the device's point (`TimerRelay`, `DoorLock.releaseMs`, fades).

### 1.2. Unknown

- **A value that may not be known is `optional`: absent ⇒ unknown** — `lift.current` after a restart, `WaterValve.state.current`, `Thermostat.temperature`.
- **`'unknown'` is an enum value** only for the main state of a device a UI shows as such: `airQuality`, `Closure.position.state`, `DoorLock.state` and `door`.
- A source's own staleness is never a field: it folds into `reachable` (12a §4.2).

### 1.3. Moving to a target

```ts
{ current?: T,          // where it is; absent ⇒ unknown
  target: T,            // where it goes; set at once by the SET or call (12a §4a)
  motion?: 'stopped' | 'opening' | 'closing' }
```

| Part | Reports |
|---|---|
| `target` | at once, on every SET or call |
| `current` | once a second while moving, and at the stop |
| `motion` | at every start and stop |

- Used by `WindowCovering.lift`/`tilt`, `Closure.position` (with `state` beside it), `WaterValve.state`/`level` (no `motion`). 16a reports Matter's current attributes at most once a second.
- Where Matter splits setting and current into two attributes, the fields follow Matter: `Fan.percent` / `percentCurrent`.
- A device that doesn't move answers a SET with the value taken — clamped, rounded, the deadband applied — and reports progress elsewhere (`Thermostat.temperature`, `running`).

### 1.4. Events as values

```ts
{ ...payload, seq: uint32 /* +1 per event */, at: timestamp }
```

- One value per event, so two identical events are two values: `GenericSwitch.switch.lastEvent`, `TimerRelay.elapsed`, `DoorLock.lastOperation`, `DoorLock.alarm`.
- A gap in `seq` means a subscription coalesced events away (03 §6.3). No value until the first event.

### 1.5. Countdowns

`onForRemaining`, `remainingS`, `remainingMs`: 0 ⇒ not running; frozen while paused; emit on every call that changes them and once a second while running — enough for a UI countdown.

### 1.6. Settings a consumer sees

Settings are edited through `manage` only (12a §2.3). Those a consumer must see are one `behavior` reading per type — `features` on `GenericSwitch`, `sensing` on `OccupancySensor`. Never writable through the device.

### 1.7. Recurring fields

| Field | Means |
|---|---|
| `optional(...)` | bound only when the origin has it — a template's role, a Matter endpoint's optional cluster (12a §4.1) |
| `fault` | absent (or `false`) ⇒ none; otherwise the reason or the unit's code |
| `localChange` | timestamp of the last change not made through evok-node — a unit's own panel or remote |
| `errorKinds` | a call's domain refusals, listed on the method (`protected`, `interlock`, `blocked`, …) |

### 1.8. `identify`

Bound by lights only: the light blinks itself (12c-01 §2). Every other type leaves it unbound — moving a cover, a door or a load to identify it is unsafe, and blinking a sensor or a fan is useless.
