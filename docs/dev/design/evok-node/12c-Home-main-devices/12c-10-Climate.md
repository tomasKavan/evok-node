# 12c-10 — Climate

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `Thermostat` | the controller of a room without an AC: mode, setpoints, preset, a heating zone | Thermostat `0x0301` |
| `RoomAirConditioner` | the controller of a room with an AC: the same fields, plus the AC unit, a source policy and boost | Room Air Conditioner `0x0072` |

**For:** one device per room — the room's only thermostat. A room with an AC is a `RoomAirConditioner`, a room without one a `Thermostat`. Both share one set of thermostat fields (§2), as Room Air Conditioner carries Matter's Thermostat cluster (research/matter/11 §1.2).

**Not for:**

- Schedules. A rule or the almanac (12d) sets `preset`; the device runs what it is told, as `IrrigationSystem` (12c-08 §1.2).
- Valves, mixers, duty cycles, the flow guard. They are the central-heating driver's (12h); a room only sends a request to its zone (§3.3).
- A second AC in one room — Open (§6).

### 1.1. Shared behaviour

| Action / situation | Effect |
|---|---|
| `mode` SET | only a value in `behavior.supportedModes`; another answers `bad-payload` (`RejectedPayload`, 05a §3.5) |
| `setpoint` SET | clamped to `behavior.limits`. When `heat` comes closer than `deadbandK` to `cool`, the other one moves — Matter's rule (research/matter/11 §1.1.3). Starts an override |
| `raiseLower({ mode, deltaK })` | the user's tweak: the same as a `setpoint` SET of the current values ± `deltaK` |
| override | a manual setpoint. Ends on the next `preset` SET, after `overrideMin`, or on `resume()` |
| `preset` SET | applies the preset's setpoints from the settings; drops the override. Absent ⇒ no preset, the setpoints stay |
| hydronic loop | PI on the room error → `request { mode: 'heat', level }` to the zone. Parameters per `emitter`: radiator Xp 5 K / Tn 150 min, floor 5 K / 240 min (research/matter/11 §4.1). The request is re-sent every 5 min as a heartbeat |
| `mode: off` | zone request `off`. Below `frostC` the room heats anyway, up to `frostC` + 1 K |
| sensor lost | zone request `baseline` — the valves as with equitherm alone (12h); `temperature` absent |
| zone not `available`, or unreachable | `available.hydronic` with the reason (`summer`, `fault`, `unreachable`); the loop pauses |
| window open | after `window.delayS`, the hydronic source stops only when `window.blockHydronic` (default `false`) |
| daemon start | `mode`, `setpoint`, `preset` and `policy` restored from `ctx.state` (12a §3); the override is dropped |

A room in `baseline` degrades to what the house does today without valves (research/matter/11 §5).

### 1.2. `RoomAirConditioner` on top

| Action / situation | Effect |
|---|---|
| `onOff` false | the whole room is off — AC and hydronic — except frost protection. Matter's dead front (research/matter/11 §1.2) |
| `mode` `fan`, `dry` | the AC alone; no heating demand. Listed only when the unit supports it |
| source order | `policy.heat`: `hydronic` or `ac` — that source only. `auto` — AC first while the 3 h outdoor average ≥ `acAboveC` (1 K hysteresis), hydronic first below it; absent `acAboveC` ⇒ hydronic first |
| stage 2 | the second source starts only after `setpoint − T > stage2.offsetK` for `stage2.afterMin` without a break; not while a window is open, nor for `afterWindowMin` after it closes. Stops at the setpoint. `running.heatStage2` while it runs |
| cooling | AC only. Allowed while the 24 h outdoor average ≥ `coolLockoutC`; never while the zone is running |
| AC heating | not while the 24 h outdoor average ≥ `heatLockoutC` |
| short cycles | the AC runs at least `minOnMin` and rests at least `minOffMin` |
| window open | after `window.delayS`, the AC stops when `window.blockAc` (default `true`) |
| `boost` SET `{ active: true }` | the AC skips stage 2 and the policy order, runs the unit's fast mode — or fan high with the setpoint at its limit; hydronic `level` 100 when heating. Ends after `boostMin` or at the setpoint. Window and lockouts still apply |
| AC setpoint | the unit controls on its own sensor, so its setpoint is compensated (§1.3) |
| room sensor lost | the unit's sensor takes over, uncompensated; `behavior.temperatureSource` = `ac` |
| AC changed on its remote or app | `localChange` gets the time. Setting `onLocalChange`: `follow` — the change becomes an override; `pause` — the room leaves the AC alone for `pauseH`; `revert` — the room writes its own values back |

Example — `policy { heat: 'auto', acAboveC: 5 }`, outdoor average 8 °C, setpoint 21 °C, room 19 °C:

```
t0        AC heats — first source; zone idle
t0+45 min still below 19.5 °C → zone request 'heat' — stage 2, running.heatStage2
t0+70 min 21.0 °C → stage 2 off, the AC modulates
```

At an outdoor average of 2 °C the order is reversed: the zone first, the AC as stage 2.

### 1.3. Room sensor and AC sensor

| | Rule |
|---|---|
| Room temperature | the `sensor` role, averaged → `temperature` (Matter `LocalTemperature`) |
| The unit's own reading | for compensation, diagnostics and fallback only |
| Compensation | PI on the room error `e = setpoint − T`: `acSetpoint = round(setpoint + kp·e + ki·∫e)` to the unit's step; the offset clamped to ±`maxK`, the result to the unit's range. `∫e` is halved when `e` changes sign and clamped. Written only when it changes, and at most every `minPeriodMin` (research/matter/11 §4.5) |
| No `sensor` role | the unit controls on its own sensor, no compensation |

The unit's sensor sits at the unit, and its error changes with mode and fan speed; a fixed offset can't follow that, a PI does.

## 2. Fields

```ts
// @evok-node/driver-home
const Celsius    = Codecs.float32({ min: -273.15, unit: '°C' });       // as 12c-04
const Percent    = Codecs.uint8({ min: 0, max: 100, unit: '%' });     // as 12c-08
const SystemMode = Codecs.string({ enumValues: ['off', 'heat', 'cool', 'auto', 'fan', 'dry'] });
const Preset     = Codecs.string({ enumValues: ['occupied', 'unoccupied', 'sleep', 'wake', 'vacation'] });   // Matter's scenarios
const Reason     = Codecs.string({ enumValues: ['summer', 'lockout', 'window', 'fault', 'unreachable', 'defrost', 'modeConflict'] });   // the last two: the AC's outdoor unit (12g §6.1)
const Avail      = Codecs.struct({ ok: Codecs.bool(), reason: Codecs.optional(Reason) });

const ThermostatBehavior = Codecs.struct({   // settings a consumer must see (12a §2.3) — 16a reports them
  supportedModes:    Codecs.array(SystemMode),
  deadbandK:         Codecs.float32({ min: 0, max: 12.7, unit: 'K' }),
  limits:            Codecs.struct({ heatMin: Celsius, heatMax: Celsius,
                                     coolMin: Codecs.optional(Celsius), coolMax: Codecs.optional(Celsius) }),
  temperatureSource: Codecs.string({ enumValues: ['sensor', 'ac', 'none'] }),
  boostMin:          Codecs.optional(Codecs.uint16({ min: 1, unit: 'min' })),   // RoomAirConditioner only
});

export const ThermostatFields = {
  temperature:        reading(Codecs.optional(Celsius), { subscribe: true }),        // absent ⇒ no sensor value
  outdoorTemperature: optional(reading(Celsius, { subscribe: true })),               // with an `outdoor` source
  mode:               channel(SystemMode, { subscribe: true }),
  setpoint:           channel(Codecs.struct({ heat: Celsius, cool: Codecs.optional(Celsius) }), { subscribe: true }),   // cool only with a cooling source
  preset:             channel(Codecs.optional(Preset), { subscribe: true }),
  override:           reading(Codecs.optional(Codecs.struct({ until: Codecs.optional(Codecs.timestamp()) })), { subscribe: true }),   // absent ⇒ following the preset
  running:            reading(Codecs.struct({ heat: Codecs.bool(), heatStage2: Codecs.bool(), cool: Codecs.bool(),
                                              fan: Codecs.bool(), hydronicLevel: Percent }), { subscribe: true }),
  available:          reading(Codecs.struct({ hydronic: Codecs.optional(Avail), ac: Codecs.optional(Avail) }), { subscribe: true }),   // per source the device has
  behavior:           reading(ThermostatBehavior, { subscribe: true }),
  raiseLower:         method('mutates', Codecs.void, Codecs.struct({
                        mode:   Codecs.string({ enumValues: ['heat', 'cool', 'both'] }),
                        deltaK: Codecs.float32({ min: -5, max: 5, unit: 'K' }) })),
  resume:             method('mutates', Codecs.void),                                 // drops the override
};

export const Thermostat = device('home.Thermostat', {
  ...CommonFields,
  ...ThermostatFields,
});

export const RoomAirConditioner = device('home.RoomAirConditioner', {
  ...CommonFields,
  ...ThermostatFields,
  onOff:         channel(Codecs.bool(), { subscribe: true }),
  policy:        optional(channel(Codecs.struct({
                   heat:     Codecs.string({ enumValues: ['auto', 'hydronic', 'ac'] }),
                   acAboveC: Codecs.optional(Celsius) }), { subscribe: true })),       // with a `heating` source
  boost:         channel(Codecs.struct({ active: Codecs.bool(), until: Codecs.optional(Codecs.timestamp()) }), { subscribe: true }),
  fanMode:       optional(channel(Codecs.string({ enumValues: ['auto', 'low', 'medium', 'high'] }), { subscribe: true })),
  swing:         optional(channel(Codecs.struct({ upDown: Codecs.bool(), leftRight: Codecs.optional(Codecs.bool()) }), { subscribe: true })),
  special:       optional(channel(Codecs.string({ enumValues: ['none', 'quiet', 'eco', 'sleep', 'windFree'] }), { subscribe: true })),
  keypadLockout: optional(channel(Codecs.bool(), { subscribe: true })),                // the unit's own remote locked
  filter:        optional(reading(Codecs.struct({ alarm: Codecs.bool() }), { subscribe: true })),
  clearFilter:   optional(method('mutates', Codecs.void)),
  fault:         reading(Codecs.optional(Codecs.struct({ code: Codecs.string() })), { subscribe: true }),   // the unit's code; absent ⇒ none
  localChange:   reading(Codecs.optional(Codecs.timestamp()), { subscribe: true }),     // last change not made through evok-node
});
```

- `supportedModes`: `Thermostat` — `off`, `heat`. `RoomAirConditioner` — `off` plus what the unit supports; `auto` only with a heating and a cooling source. The UI offers only these.
- `special` accepts only the values the unit supports, `windFree` only while cooling; another answers `bad-payload`. There is no `fast`: boost is the one way to ask for it.
- `setpoint.cool` is absent without a cooling source; a SET with it answers `bad-payload`.
- `identify` is unbound.

## 3. Templates

| Template | DeviceType | Roles | Shipped by |
|---|---|---|---|
| `thermostat` (§3.1) | `Thermostat` | `sensor`: `home.TemperatureSensor`, 1–3 · `heating`: the 12h zone, 1 · `window`: `home.ContactSensor`, 0–8, `reachable: false` · `outdoor`: `home.TemperatureSensor`, 0–1, `reachable: false` | driver-home |
| `room-ac-from-mimb19n` (§3.2) | `RoomAirConditioner` | `unit`: `mimb19n.indoorUnit` (12g §3), 1 · `sensor`: `home.TemperatureSensor`, 0–3, `reachable: false` · `heating`: the 12h zone, 0–1, `reachable: false` · `window`, `outdoor` as above | driver-mimb19n (12a §3) |

- **One room controller.** Both templates run the same module of driver-home: the loops, the source order, stage 2, lockouts, window, boost and compensation (§1). A template adds only its sources. Another AC brand is another `room-ac-from-…` template on the same module.
- **`reachable`** (12a §4.2): a `Thermostat` needs its sensor and its zone — without either it can't control. A `RoomAirConditioner` needs only its unit; the rest is handled as §1 says.
- Several `sensor` sources are averaged; one lost is left out, all lost is "sensor lost". Any `window` source open is open.

### 3.1. `thermostat`

| Setting | Default | Note |
|---|---|---|
| `emitter` | `radiator` | `radiator` \| `floor` — PI parameters (§1.1) |
| `frostC` | 7 | |
| `deadbandK` | 2.0 | Matter's default (research/matter/11 §1.1.2) |
| `limits` | heat 5–30 °C | |
| `presets` | occupied 21, unoccupied 18, sleep 19, wake 21, vacation 16 | heat setpoints, °C; `cool` per preset with a cooling source |
| `overrideMin` | 0 | 0 ⇒ until the next `preset` SET or `resume` |
| `window` | `{ blockHydronic: false, delayS: 30 }` | Siemens' 30 s delay (research/matter/11 §4.1) |

### 3.2. `room-ac-from-mimb19n`

Settings of §3.1 (`window` adds `blockAc: true`), plus:

| Setting | Default | Note |
|---|---|---|
| `policy` | `{ heat: 'auto' }` | the start value of the `policy` field |
| `stage2` | `{ offsetK: 1.5, afterMin: 45 }` | KNX ~2 K, Loxone 60 min (research/matter/11 §4.1–4.3) |
| `afterWindowMin` | 15 | |
| `coolLockoutC` | 15 | Loxone (research/matter/11 §4.2) |
| `heatLockoutC` | 18 | Loxone |
| `minOnMin`, `minOffMin` | 10, 10 | ecobee min off 600 s |
| `compensation` | `{ kp: 0.3, ki: 0.05, maxK: 3, minPeriodMin: 10 }` | Versatile Thermostat "medium" (research/matter/11 §4.5) |
| `onLocalChange` | `follow` | `follow` \| `pause` \| `revert` |
| `pauseH` | 2 | |
| `boostMin` | 30 | |

What the unit supports (modes, fan, swing, specials, setpoint range and step) comes from its `features` (12g §2); the field mapping is 12g §6.1.

### 3.3. The zone on another PLC

The zone is the central-heating driver's, on the boiler-room PLC; the room device runs on the flat's PLC with its sensors and its AC (12g over 07's `modbus-remote`). Its `heating` source is `{ url, address }` and is reached over a `RemoteLink` (05a §3.8b, 12a §3). The contract, matched by 12h:

```ts
// the 12h zone, as the room sees it
request:   channel<{ mode: 'off' | 'heat' | 'baseline', level: Percent }>   // re-sent every 5 min
available: reading<{ heat: boolean, reason?: 'summer' | 'fault' | 'circuitOff' }>
running:   reading<boolean>
```

- Link down ⇒ writes answer `unreachable` ⇒ `available.hydronic` `{ ok: false, reason: 'unreachable' }`.
- When requests stop coming, the zone falls back to `baseline` on its own side (12h).

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). `Thermostat` → Thermostat `0x0301`; `RoomAirConditioner` → Room Air Conditioner `0x0072`, to be tested with the controllers (§6).

| Matter | Home |
|---|---|
| `LocalTemperature` | `temperature`; null when absent |
| `OutdoorTemperature` | `outdoorTemperature` |
| `OccupiedHeatingSetpoint`, `OccupiedCoolingSetpoint` | `setpoint.heat`, `setpoint.cool` |
| `MinSetpointDeadBand` | `behavior.deadbandK` × 10 |
| `Abs…SetpointLimit`, `Min/Max…SetpointLimit` | `behavior.limits` |
| `SystemMode` | `mode`: Off, Heat, Cool, Auto, FanOnly (`fan`), Dry (`dry`) |
| FeatureMap | `HEAT`; `COOL` with `cool` in `supportedModes`; `AUTO` with `auto`; `PRES` |
| `ControlSequenceOfOperation` | HeatingOnly without cooling, else CoolingAndHeating |
| `ThermostatRunningState` | Heat, Cool, Fan, HeatStage2 from `running` |
| `ThermostatRunningMode` | Heat or Cool from `running`, else Off |
| `SetpointRaiseLower(Mode, Amount)` | `raiseLower({ mode, deltaK: Amount / 10 })` |
| `PresetTypes`, `Presets` | one built-in preset per `Preset` value, setpoints from the settings |
| `ActivePresetHandle`, `SetActivePresetRequest` | `preset` |
| `TemperatureSetpointHold`, `SetpointHoldExpiryTimestamp` | On while `override`; `override.until` |
| `RemoteSensing` | `LocalTemperature` bit while `temperatureSource` is `sensor` |
| On/Off (RAC) | `onOff` |
| Fan Control `FanMode`, `RockSetting` (RAC) | `fanMode`, `swing` |
| Thermostat UI Configuration `KeypadLockout` | `keypadLockout`: 0 or 1 |
| `ACErrorCode` | bits from `fault`, where the template knows the code's meaning |

- Not on Matter: `policy`, `available`, `boost`, `special`, `running.hydronicLevel`, `localChange`, `resume`, `filter`, `clearFilter`.
- Writes to `Presets`, the limits and `MinSetpointDeadBand` are refused by 16a: settings change through `manage` only (12a §2.3).
- `matter` origin (12a §4a): an endpoint of `0x0301` maps to `Thermostat`; one of `0x0072`, or of `0x0301` with On/Off and Fan Control — as ACs ship (research/matter/11 §3) — to `RoomAirConditioner`. Only the Matter fields bind; no `policy`, no `boost`.

## 5. Moving and target

A `mode`, `setpoint` or `preset` SET answers at once with the value taken — clamped, the deadband applied. Nothing moves towards it on the device: the room's progress is `temperature` and `running`.

## 6. Open

- **A second AC in one room.** Deferred.
- **Preset setpoints** — user-editable through the Home API and UI, or admin settings only. → M3.11, M3.12.
- **Matter writes** to `Presets`, limits and deadband through the device. → M3.13, with 12c-04 §4's Open.
- **Outdoor temperature from 12h** (the ISM8i's) as an `outdoor` source kind. → M3.3e. A room with an AC can use `temperature-from-mimb19n-outdoor` (12g §6.2).
- **`0x0072` with the controllers** — Apple sends Cool instead of Auto (research/matter/11 §2); fall back to `0x0301` with On/Off and Fan Control if it fails. → M3.13.
