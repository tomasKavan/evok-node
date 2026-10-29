# 12c-12 — Ventilation

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `Fan` | on/off, a mode (low, medium, high), a speed in % | Fan `0x002B` |
| `VentilationUnit` | a heat recovery unit: the `Fan` fields plus auto (demand control), boost, away, night ventilation, temperatures, filter, fault | Fan `0x002B` |

**For:**

- `Fan`: a fan on Unipi outputs — a bath or kitchen exhaust fan on a relay, a three-speed fan on relays, an EC fan on a 0–10 V output.
- `VentilationUnit`: a whole-dwelling heat recovery unit behind its own driver — the 2VV unit through driver-airgenio (12j). The `Fan` part is what a user touches every day; the rest is beyond Matter, as `RoomAirConditioner`'s `policy` and `boost` are (12c-10).

**Not for:**

- Schedules. A rule (12b) or the almanac (12d) sets `mode`, `away` or `onOff`; the device runs what it is told.
- A fan that runs on after a light: a `TimerRelay` in a rule (12c-05).
- Auto on a `Fan` — a bath fan on humidity is a rule.
- The unit's service side: fire mode, bypass, frost protection, the supply-air setpoint, calibration. They are the unit driver's, in the Inspector (12j §4).

### 1.1. Shared behaviour

| Action | Effect |
|---|---|
| `onOff` SET false | off; `mode` and `percent` are kept |
| `onOff` SET true | on at the kept `mode` and `percent` |
| `mode` SET `low` / `medium` / `high` | `percent` = that level from `behavior.levels`; switches on |
| `percent` SET 0 | `onOff` false; `mode` and the last `percent` are kept |
| `percent` SET p > 0 | clamped to `behavior.minPct`–100, rounded to `behavior.stepPct`; `mode` = the nearest level (below); switches on |
| a mode not in `behavior.modes` | `bad-payload` (`RejectedPayload`, 05a §3.5) |
| daemon start | the template restores `{ onOff, mode, percent }` from `ctx.state` (12a §3) and applies `startUp` (§3) |

**Nearest level.** The bounds are the midpoints between configured levels. With levels low 30, medium 60, high 100:

```
percent  10 → clamped to minPct 20 → mode low
percent  45 → low      (≤ 45, the midpoint of 30 and 60)
percent  50 → medium
percent  85 → high     (> 80, the midpoint of 60 and 100)
mode medium → percent 60
```

`percentCurrent` is what the fan runs: 0 when off. It may differ from `percent` while a unit ramps, in boost and in auto.

### 1.2. `VentilationUnit` on top

What the unit runs, highest first:

| State | The unit runs |
|---|---|
| `onOff` false | standby |
| `boost.active` | the unit's boost — its own boost flow |
| `away` true | `behavior.awayPct` |
| `mode` `auto` | the demand control's level (§1.3) |
| `mode` low / medium / high, or a `percent` | that `percent` |

| Action / situation | Effect |
|---|---|
| `boost` SET `{ active: true }` | boost now, `until` = now + `behavior.boostMin`. Again while active: restarts the time |
| `boost` SET `{ active: false }` | ends it; the state below applies again |
| `boost` ends by itself, or is started at the unit's panel | follows the unit; `until` absent for a boost started there |
| `away` SET | on or off; independent of `mode`, which is kept |
| `nightVentilation` SET `{ enabled }` | allows or blocks the unit's own night ventilation; `active` is the unit's report. While active the unit runs supply air only, without heat recovery (research/16 §4.5) |
| `resetFilter()` | the unit's filter counter restarts |
| change at the unit's panel or app | `localChange` gets the time. Setting `onLocalChange`: `follow` — taken as a SET of the same field (a level becomes `percent` and `mode` by §1.1, leaving `auto`); `revert` — the device's own values are written back |
| unit fault that stops it | `fault` set; `percentCurrent` 0 |

Example — levels 30 / 60 / 100, `awayPct` 20, `boostMin` 30:

```
07:00  mode auto, CO₂ 900 ppm        → unit at 60 %
07:30  boost SET active              → unit boost, until 08:00
08:00  boost ends                    → back to auto, 50 %
08:15  away SET true                 → 20 %
17:30  away SET false                → auto again
22:00  rule: mode low                → 30 %
```

### 1.3. Demand control (`auto`)

Runs in driver-home, the same module for every `VentilationUnit` template; a template adds only its unit. The unit's own DCV is not used (12j §1).

| | Rule |
|---|---|
| Input | the highest `co2` of the reachable `air` sources (`home.AirQualitySensor`, 12c-04) — the worst room decides |
| Level | linear from `auto.lowPpm` → `auto.minPct` to `auto.highPpm` → `auto.maxPct`, clamped, rounded to `behavior.stepPct` |
| Changes | written only when the new level differs by at least `stepPct`, and at most every `auto.periodS` |
| No `air` source reachable | `auto.fallbackPct`; `demand` absent |
| `auto` in `behavior.modes` | only with at least one `air` source |

Example — `lowPpm` 600, `highPpm` 1200, `minPct` 30, `maxPct` 100, step 10:

```
CO₂  550 → 30 %      CO₂  900 → 65 → 70 %      CO₂ 1400 → 100 %
```

## 2. Fields

```ts
// @evok-node/driver-home
const Percent = Codecs.uint8({ min: 0, max: 100, unit: '%' });      // as 12c-10
const Celsius = Codecs.float32({ min: -273.15, unit: '°C' });       // as 12c-04
const FanMode = Codecs.string({ enumValues: ['low', 'medium', 'high', 'auto'] });

const FanBehavior = Codecs.struct({        // settings a consumer must see (12a §2.3)
  modes:   Codecs.array(FanMode, { min: 1 }),
  levels:  Codecs.struct({ low: Codecs.optional(Percent), medium: Codecs.optional(Percent), high: Percent }),
  minPct:  Percent,                         // lowest speed above 0
  stepPct: Percent,                         // 1 = any value
  startUp: Codecs.string({ enumValues: ['off', 'on', 'previous'] }),
});

export const FanFields = {
  onOff:          channel(Codecs.bool(), { subscribe: true }),
  mode:           channel(FanMode, { subscribe: true }),                                     // kept while off
  percent:        channel(Codecs.optional(Percent), { subscribe: true, set: Percent }),       // absent in auto
  percentCurrent: reading(Percent, { subscribe: true }),                                      // 0 when off
};

export const Fan = device('home.Fan', {
  ...CommonFields,
  ...FanFields,
  behavior: reading(FanBehavior, { subscribe: true }),
});

const VentilationBehavior = Codecs.struct({
  modes: Codecs.array(FanMode, { min: 1 }),
  levels: Codecs.struct({ low: Codecs.optional(Percent), medium: Codecs.optional(Percent), high: Percent }),
  minPct: Percent,
  stepPct: Percent,
  startUp: Codecs.string({ enumValues: ['off', 'on', 'previous'] }),
  awayPct: Percent,
  boostMin: Codecs.uint8({ min: 1, max: 60, unit: 'min' }),
});

export const VentilationUnit = device('home.VentilationUnit', {
  ...CommonFields,
  ...FanFields,
  behavior:         reading(VentilationBehavior, { subscribe: true }),
  boost:            channel(Codecs.struct({ active: Codecs.bool(), until: Codecs.optional(Codecs.timestamp()) }),
                      { subscribe: true, set: Codecs.struct({ active: Codecs.bool() }) }),
  away:             channel(Codecs.bool(), { subscribe: true }),
  nightVentilation: optional(channel(Codecs.struct({ enabled: Codecs.bool(), active: Codecs.bool() }),
                      { subscribe: true, set: Codecs.struct({ enabled: Codecs.bool() }) })),
  temperatures:     reading(Codecs.struct({ outdoor: Codecs.optional(Celsius), supply: Codecs.optional(Celsius),
                      extract: Codecs.optional(Celsius), exhaust: Codecs.optional(Celsius) }), { subscribe: true }),
  filter:           optional(reading(Codecs.struct({ conditionPct: Codecs.optional(Percent),
                      change: Codecs.string({ enumValues: ['ok', 'warning', 'critical'] }) }), { subscribe: true })),
  resetFilter:      optional(method('mutates', Codecs.void)),
  fault:            reading(Codecs.optional(Codecs.struct({ code: Codecs.string() })), { subscribe: true }),   // absent ⇒ none
  localChange:      reading(Codecs.optional(Codecs.timestamp()), { subscribe: true }),                         // last change not made through evok-node
  demand:           optional(reading(Codecs.optional(Codecs.struct({ co2: Codecs.float32({ min: 0, unit: 'ppm' }) })),
                      { subscribe: true })),                                                                    // with `air` sources; absent ⇒ none reachable
});
```

- `levels` has a value for each of `low`, `medium`, `high` in `modes`; `levels.high` is always 100 on a relay fan.
- `temperatures.outdoor` is outdoor air before the unit, `supply` into the dwelling, `extract` from it, `exhaust` out after the exchanger.
- `identify` is unbound: blinking a fan is useless and a unit can't do it.

## 3. Templates

| Template | DeviceType | Roles | Shipped by |
|---|---|---|---|
| `fan-from-relay` (§3.1) | `Fan` | `output`: `unipi.ro` \| `unipi.do`, 1 | driver-home |
| `fan-from-relays` (§3.2) | `Fan` | `speeds`: `unipi.ro` \| `unipi.do`, 2–3, low to high | driver-home |
| `fan-from-ao` (§3.3) | `Fan` | `output`: `unipi.ao`, 1 · `power`: `unipi.ro` \| `unipi.do`, 0–1 | driver-home |
| `ventilation-from-airgenio` (§3.4) | `VentilationUnit` | `unit`: `airgenio.unit`, 1 · `air`: `home.AirQualitySensor`, 0–8, `reachable: false` | driver-airgenio (12a §3) |

Rules every `Fan` template follows:

- **State** (12a §3): saves `{ onOff, mode, percent }` through `ctx.state`.
- **`startUp`** is a setting, applied at daemon start from the saved state: `off`, `on` (at the saved `mode` and `percent`), `previous`. No saved state ⇒ off.
- **Its own echoes** are ignored; an output changed elsewhere is re-derived and emitted, as 12c-01 §3.1.
- `percentCurrent` = `percent` while on — a relay or an AO fan has no speed feedback.

### 3.1. `fan-from-relay`

One fan, one speed. `modes` `['high']`, `levels.high` 100; any `percent` > 0 is 100.

| Setting | Default |
|---|---|
| `startUp` | `previous` |

### 3.2. `fan-from-relays`

A fan with motor taps, one relay per speed. Two taps on at once can burn the motor: **at most one output is on**.

| Setting | Default | Note |
|---|---|---|
| `levels` | 2 relays: low 50, high 100 · 3 relays: low 33, medium 66, high 100 | `modes` follow the relay count |
| `switchMs` | 500 | between one tap off and the next on |
| `startUp` | `previous` | |

- A speed change: every output off, `switchMs`, the new one on.
- `percent` goes to the nearest level's relay (§1.1).
- An output switched on elsewhere: every other output off at once; the device follows the one left on. Two found on together: all off, a warning logged.

### 3.3. `fan-from-ao`

An EC fan with a 0–10 V input, optionally with a relay for its mains.

| Setting | Default | Note |
|---|---|---|
| `minVolts`, `maxVolts` | 2.0, 10.0 | `minPct` → `minVolts`, 100 % → `maxVolts`, linear |
| `minPct`, `stepPct` | 20, 1 | |
| `levels` | low 30, medium 60, high 100 | |
| `startUp` | `previous` | |

- Off: 0 V, then `power` off. On: `power` on, then the voltage.
- The AO must be in `voltage10` mode; another mode marks the device stale (12a §4.2), as `plug-from-output` with a PWM output (12c-02 §3).

### 3.4. `ventilation-from-airgenio`

A 2VV unit through driver-airgenio (12j). Shipped in `@evok-node/driver-airgenio/home`; it imports `VentilationUnit` from driver-home.

| Setting | Default | Note |
|---|---|---|
| `levels` | low 30, medium 60, high 100 | |
| `awayPct` | 20 | |
| `boostMin` | 30 | 1–60; the unit's own boost time is set to 60 at commissioning (12j §8) |
| `auto` | `{ lowPpm: 600, highPpm: 1200, minPct: 30, maxPct: 100, periodS: 120, fallbackPct: 60 }` | §1.3 |
| `onLocalChange` | `follow` | `follow` \| `revert` |
| `startUp` | `previous` | |

`behavior.minPct` and `stepPct` come from the unit's `limits` (‰ ÷ 10, defaults 20 and 10). `modes` are low, medium, high, plus auto with an `air` source.

| Home | `unit` (12j §4) |
|---|---|
| `onOff` | `power` |
| what the unit runs (§1.2) | `level` = percent × 10; in boost `boost` true instead |
| `boost` end after `boostMin` | `boost` false; the unit ending it first (`boost` false by itself) ends it here too |
| `percentCurrent` | `fans.supply` ÷ 10; 0 while `state.on` is false |
| `nightVentilation` | `enabled` ↔ `freeCooling`; `active` ← `state.freeCooling` |
| `temperatures` | `temps.outdoor`, `.supply`, `.extract`, `.exhaust` |
| `filter.conditionPct` | 100 − 100 × `filter.hours` ÷ `filter.maxHours`, floored at 0 |
| `filter.change` | `critical` with `filter.due` or `filter.error`; `warning` with `filter.warning` or `conditionPct` ≤ 10; else `ok` |
| `resetFilter()` | `resetFilter()` |
| `fault` | `supplyFan` or `extractFan` first, then the first of `faults.active`; `fire` while `state.fire` |
| `localChange` | `externalChange.at` |

- **`reachable`** (12a §4.2): needs `unit`. A stale `unit` reading (12j §3) ⇒ `markStale(true)`.
- **State**: saves `{ onOff, mode, percent, away }`. At daemon start, once `unit` is reachable, the saved state is written per `startUp`. `boost` is not saved: a restart ends it. `nightVentilation` is the unit's own and is not written at start.
- **The unit in DCV mode** (`state.manual` false): `level` writes answer `notManual` (12j §5.2); the device is marked stale until the unit is back in manual mode.
- `unit.nobody` is not used: `away` is this template's own level, so its meaning doesn't depend on the unit's nonoccupied logic (research/16 §4.3).

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). `Fan` and `VentilationUnit` → Fan `0x002B` with On/Off and Fan Control.

| Matter | Home |
|---|---|
| On/Off `OnOff` | `onOff` |
| `FanMode` | Off while `onOff` false; else `mode` (`auto` → Auto) |
| `FanMode` write | Off → `onOff` false; Low, Medium, High, Auto → `mode` SET |
| `FanModeSequence` | from `behavior.modes`, below |
| FeatureMap | `AUT` with `auto` in `modes`; no `SPD`, `RCK`, `WND`, `STEP`, `DIR` |
| `PercentSetting` | 0 while off; else null in auto, else `percent` |
| `PercentSetting` write | 0 → `onOff` false; p → `percent` SET; null ignored |
| `PercentCurrent` | `percentCurrent` |

| `behavior.modes` | `FanModeSequence` |
|---|---|
| low, medium, high | OffLowMedHigh (0) |
| low, high | OffLowHigh (1) |
| low, medium, high, auto | OffLowMedHighAuto (2) |
| low, high, auto | OffLowHighAuto (3) |
| high, auto | OffHighAuto (4) |
| high | OffHigh (5) |

Another set of modes is refused when the template's settings are saved: Matter has no sequence for it.

- `FanMode` reads Off while `onOff` is false. Matter keeps `FanMode` under On/Off (research/matter/12 §1.3), but some controllers read only `FanMode`. The kept mode comes back with On.
- Not on Matter: `boost`, `away`, `nightVentilation`, `temperatures`, `filter`, `resetFilter`, `fault`, `localChange`, `demand`, `behavior` beyond the sequence. `VentilationUnit` gets no child endpoints.
- `matter` origin (12a §4a): an endpoint of `0x002B` maps to `Fan`, with `modes` from its `FanModeSequence`. No endpoint maps to `VentilationUnit`.

## 5. Moving and target

A `mode` or `percent` SET answers at once with the value taken — clamped, rounded (12a §4a). `percentCurrent` follows what the fan runs: at once for a relay or AO fan, after the unit's ramp and the next poll for a unit. `boost.until` is fixed at the SET.

## 6. Open

- **Fan vs Air Purifier for `VentilationUnit`.** Fan matches Matter's meaning better; Air Purifier `0x002D` would carry the filter (research/matter/12 §5). Test how Apple Home and Google Home show both. → M3.13.
