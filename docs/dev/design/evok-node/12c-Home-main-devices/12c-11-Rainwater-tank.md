# 12c-11 — Rainwater tank

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `RainwaterTank` | the rainwater system at a glance: levels, what it does, alarms; mode and a few calls | none — 16a ignores it |

The system itself is the rainwater driver (12i). This file is its home side: one home type and three templates, all shipped with that driver.

| Template | DeviceType | For |
|---|---|---|
| `tank-from-rainwater` (§3.1) | `RainwaterTank` | the overview in the Home UI |
| `valve-from-rainwater-supply` (§3.2) | `WaterValve` (12c-08) | the irrigation system's master: opening it asks for water |
| `leak-from-rainwater-alarm` (§3.3) | `WaterLeakDetector` (12c-08) | the retention alarm in the Home UI and on Matter |
| bundle `rainwater` (§3.4) | all three | created in one step from the driver's `control` |

`home.RainwaterTank` is declared in `driver-home`, as every home type. The templates and the bundle are in `@evok-node/driver-rainwater/home` (12a §3).

**For:** a user who wants to see the tanks and, rarely, to stop the system, refill now or acknowledge a failed refill.

**Not for:**

- Valve-by-valve control, `manual` mode, settings: the Inspector, on the rainwater driver (12i §3, §7).
- Alarms other than the retention one as detectors: `refillFailed`, `cutoff`, `sensor` and `bypass` show on the tank only.

### 1.1. `RainwaterTank` behaviour

| Call | Effect |
|---|---|
| `SET mode` `auto` / `off` | forwarded to the driver's `control.mode` |
| `SET mode` `manual` | refused, `bad-payload` — the Inspector's only. `mode` still reads `manual` when the Inspector set it |
| `refill()`, `fillUpper()` | forwarded; `notAuto`, `notPossible` passed through (12i §4) |
| `stop()`, `ack()` | forwarded |

Nothing is saved here: every value is the driver's.

## 2. Fields

```ts
// @evok-node/driver-home
const TankLevel = Codecs.struct({
  percent: Codecs.optional(Codecs.float32({ min: 0, max: 100, unit: '%' })),   // absent ⇒ unknown
  litres:  Codecs.optional(Codecs.uint32({ unit: 'l' })),
  capacityL: Codecs.uint32({ unit: 'l' }),
});

export const RainwaterTank = device('home.RainwaterTank', {
  ...CommonFields,
  mode:      channel(Codecs.string({ enumValues: ['auto', 'manual', 'off'] }),
               { subscribe: true, set: Codecs.string({ enumValues: ['auto', 'off'] }) }),
  activity:  reading(Codecs.string({ enumValues: ['idle', 'refilling', 'transferring'] }), { subscribe: true }),
  lower:     reading(TankLevel, { subscribe: true }),
  upper:     optional(reading(TankLevel, { subscribe: true })),
  retention: optional(reading(TankLevel, { subscribe: true })),
  supply:    reading(Codecs.struct({ demand: Codecs.bool(), available: Codecs.bool() }), { subscribe: true }),
  alarms:    reading(Codecs.struct({ retentionHigh: Codecs.bool(), refillFailed: Codecs.bool(), cutoff: Codecs.bool(),
               sensor: Codecs.bool(), bypass: Codecs.bool() }), { subscribe: true }),
  refill:    method('mutates', Codecs.void, Codecs.void, { errorKinds: ['notAuto', 'notPossible'] }),
  fillUpper: method('mutates', Codecs.void, Codecs.void, { errorKinds: ['notAuto', 'notPossible'] }),
  stop:      method('mutates', Codecs.void),
  ack:       method('mutates', Codecs.void),
});
```

- `activity` simplifies the driver's `process`: `refillFromUpper` and `refillFromMains` ⇒ `refilling`; `fillUpper` ⇒ `transferring`.
- A held upper level (12i §6.3) is shown as its last value; the Home UI does not mark it.
- `identify` is unbound.

## 3. Templates

| Template | DeviceType | Roles |
|---|---|---|
| `tank-from-rainwater` | `RainwaterTank` | `control`: `rainwater.control`, 1 · `lower`: `rainwater.tank`, 1 · `upper`: `rainwater.tank`, 0–1 · `retention`: `rainwater.tank`, 0–1 · `supply`: `rainwater.supply`, 1 |
| `valve-from-rainwater-supply` | `WaterValve` | `supply`: `rainwater.supply`, 1 |
| `leak-from-rainwater-alarm` | `WaterLeakDetector` | `alarm`: `rainwater.alarm`, 1 · `fault`: `rainwater.alarm`, 0–1 |

No settings beyond those named below. Nothing saved (12a §3).

### 3.1. `tank-from-rainwater`

- Each field follows its source: `mode`, `activity` and `alarms` from `control`; levels from each tank's `@` and `capacity`; `supply` from `supply`.
- `SET mode` and the calls forward to `control`; a `SourceUnreachable` answers `unreachable` (12a §3).

### 3.2. `valve-from-rainwater-supply`

A `WaterValve` whose "open" is a demand for water. Fields and behaviour as 12c-08 §1.1 — timed opening, `maxOpenS`, closed after a restart.

| Setting | Default | Note |
|---|---|---|
| `defaultOpenS` | absent | → `behavior` |
| `maxOpenS` | absent | → `behavior` |

| Event | Effect |
|---|---|
| `open(…)` | `supply.demand` ← true |
| `close()`, timer ends, `maxOpenS` | `supply.demand` ← false |
| `state.current` | `open` while demand and `available`; `closed` otherwise. Never `transitioning` |
| `fault.blocked` | demand and not `available` — the cutoff, `off` mode, the pump not reachable |
| daemon start | `supply.demand` ← false |
| `demand` set elsewhere | re-derived, as an output changed elsewhere (12c-08 §3) |

As the master of an `IrrigationSystem` (12c-08 §3.3), the system opens it before the first zone and closes it after the last; the rainwater driver then holds back its transfer to the upper tank (12i §5.2). A blocked supply does not stop the irrigation: its zones run without water.

### 3.3. `leak-from-rainwater-alarm`

- `leak` = `alarm`'s `active`, at once — no delay, the driver's alarm is already settled.
- `sensorFault` = `fault`'s `active`; unbound role ⇒ `sensorFault` unbound.
- `alarm`, `suppressAlarm` unbound, as `leak-from-di` (12c-08 §3.4).

Used for `alarm.retentionHigh` with `alarm.sensor` as `fault`.

### 3.4. Bundle `rainwater`

| Anchor | Members |
|---|---|
| `rainwater.control`, 1 | `tank` (`tank-from-rainwater`) · `supply` (`valve-from-rainwater-supply`) · `retentionAlarm` (`leak-from-rainwater-alarm`) |

`resolve` reads the anchor's `parts` (12i §4) — never parsing a tail:

```
anchor  rain:control   parts { lower: 'lower', upper: 'upper', retention: 'retention', supply: 'supply',
                               alarms: { retentionHigh: 'alarm.retentionHigh', sensor: 'alarm.sensor', … } }
  → tank            { control: ['rain:control'], lower: ['rain:lower'], upper: ['rain:upper'],
                      retention: ['rain:retention'], supply: ['rain:supply'] }
  → supply          { supply: ['rain:supply'] }
  → retentionAlarm  { alarm: ['rain:alarm.retentionHigh'], fault: ['rain:alarm.sensor'] }   // null without a retention tank
```

## 4. Matter

- **`RainwaterTank`:** none; 16a ignores it.
- **The supply valve** is a `WaterValve` (12c-08 §4); `fault.blocked` is `ValveFault.Blocked`.
- **The retention alarm** is a `WaterLeakDetector` (12c-08 §4): an exposed one reaches Matter controllers, and their notifications.

## 5. Moving and target

| Device | Field | Reports |
|---|---|---|
| `RainwaterTank` | levels | as the driver emits them — smoothed, with its deadband (12i §6.2) |
| | `mode`, `activity`, `alarms`, `supply` | at every change |
| supply `WaterValve` | `state.target` | at once, on every call |
| | `state.current` | `open` once the driver reports `demand` back and `available`; `closed` at once on close |
