# 12c-08 — Water

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `WaterValve` | open / close, timed opening, a safety cap, optional level | Water Valve `0x0042` |
| `IrrigationSystem` | runs zones one at a time, with a master valve and a pump | Irrigation System `0x0040`, zones as child Water Valves |
| `WaterLeakDetector` | leak or no leak | Water Leak Detector `0x0043` |

**For:**

- `WaterValve` — a valve on one output: an irrigation zone, a tank inlet, the descaler bypass (a 3-way valve whose "open" is the bypass), a heating circuit's thermal actuator outside the central heating system. The building's heating zones are the central heating driver's (12h), not `WaterValve`s.
- `IrrigationSystem` — a set of zones that must not run together, on one supply.
- `WaterLeakDetector` — a leak module on a DI, a Matter leak sensor.

**Not for:**

- Motorised ball valves on two outputs, 0–10 V valves: no template yet.
- Schedules, rain skip, seasonal adjust. A rule calls `run` — on `Clock`, with `RainSensor` or `Weather` as device options (12c-13 §1.1); the system runs what it is told.
- Tank levels and pumping: the rainwater driver (12i) and its home side (12c-11).
- Latching a leak alarm. The detector follows its source, as Matter's (research/matter/09 §5.2); what reacts is a rule's.
- Rain and freeze detectors: not yet types (research/matter/09 §1.4).

Apple Home shows no Water Valve and no Irrigation System (research/matter/09 §2). They are exposed as what they are anyway.

### 1.1. `WaterValve` behaviour

| Action | Effect |
|---|---|
| `open({ seconds?, level? })` | opens. `seconds` absent ⇒ `defaultOpenS`; `0` or no default ⇒ stays open until closed. `level` absent ⇒ 100 |
| `open` while open | the same opening: `seconds` replaces the remaining time, `level` the level |
| `close()` | closes; never refused |
| remaining reaches 0 | closes |
| one opening lasts `maxOpenS` | closes, `fault.timeout` true |
| daemon start | **closed**, always. Nothing is restored |

- **`maxOpenS` counts from the opening**, not from the last `open`: a rule that keeps re-opening cannot pass it. `seconds` beyond what is left of it is clamped. `fault.timeout` clears on the next `open`.
- **Always closed after a restart.** Matter leaves start-up to the maker and recommends restarting only while closed (research/matter/09 §1.1); an open valve with nobody counting is the worst case.
- `identify` is unbound — opening a valve to identify it wastes water, or worse.
- `fault.blocked` is bound only by a valve whose "open" is a demand on a supply — `valve-from-rainwater-supply` (12c-11 §3.2). No output template binds it.

### 1.2. `IrrigationSystem` behaviour

| Action | Effect |
|---|---|
| `run({ zones?, multiplierPct? })` | queues the zones, in the given order — absent ⇒ every zone, in role order. Each runs `seconds`, or its own `behavior.defaultOpenS` × `multiplierPct` / 100. A zone with neither is skipped. While running, the zones are appended |
| `pause` | the active zone closes; its remaining time is kept |
| `resume` | it opens again for the kept time |
| `next` | the active zone closes; the next one starts |
| `stop` | the active zone closes, the queue is dropped |
| a zone opened by anyone else | the active zone closes; the opened one becomes active. After it closes, the queue goes on from the next zone |
| the queue empties | master and pump off → `stopped` |
| daemon start | `stopped`, queue empty — every zone is closed (§1.1); master and pump off |

- **One zone at a time**, always. A second zone opening closes the first — whoever opened either.
- `running` while any zone is open or queued — Matter's "at least one of the composed water valves is open for any reason" (research/matter/09 §1.3.4).
- Calls that change nothing answer `ok`, as on a `TimerRelay` (12c-05 §1.1).
- A zone's own `maxOpenS` (§1.1) still applies; when it cuts a zone short, the next one starts.

### 1.3. `WaterLeakDetector` behaviour

Readings only, as every sensor (12c-04 §1.1). `leak` is `true` while water is detected. No state is saved; after a restart it reports what its source reports.

## 2. Fields

```ts
// @evok-node/driver-home
const Percent = Codecs.uint8({ min: 0, max: 100, unit: '%' });
const Seconds = Codecs.uint32({ unit: 's' });

const ValveState = Codecs.struct({
  current: Codecs.optional(Codecs.string({ enumValues: ['closed', 'open', 'transitioning'] })),   // absent ⇒ unknown
  target:  Codecs.string({ enumValues: ['closed', 'open'] }),
});

const ValveBehavior = Codecs.struct({        // settings a consumer must see (12a §2.3) — 16a reports them
  defaultOpenS: Codecs.optional(Codecs.uint32({ min: 1, unit: 's' })),   // absent ⇒ an open without seconds stays open
  maxOpenS:     Codecs.optional(Codecs.uint32({ min: 1, unit: 's' })),   // absent ⇒ no cap
});

export const WaterValve = device('home.WaterValve', {
  ...CommonFields,
  state:      reading(ValveState, { subscribe: true }),
  level:      optional(reading(Codecs.struct({ current: Percent, target: Percent }), { subscribe: true })),   // thermal template only; 0 when closed
  remainingS: reading(Seconds, { subscribe: true }),                 // 0 ⇒ closed or untimed; emits once a second while timed
  fault:      reading(Codecs.struct({ timeout: Codecs.bool(),
                blocked: Codecs.optional(Codecs.bool()) }), { subscribe: true }),   // blocked: open, but its supply delivers nothing — 12c-11 §3.2 only
  behavior:   reading(ValveBehavior, { subscribe: true }),
  open:       method('mutates', Codecs.void, Codecs.struct({
                seconds: Codecs.optional(Codecs.uint32({ unit: 's' })),   // 0 ⇒ stays open
                level:   Codecs.optional(Codecs.uint8({ min: 1, max: 100, unit: '%' })) })),   // ignored without `level`
  close:      method('mutates', Codecs.void),
});

const Zone = Codecs.string();                // the tail of one of the system's zones (12a §4.1)

export const IrrigationSystem = device('home.IrrigationSystem', {
  ...CommonFields,
  state:      reading(Codecs.string({ enumValues: ['stopped', 'running', 'paused'] }), { subscribe: true }),
  activeZone: reading(Codecs.optional(Zone), { subscribe: true }),            // absent ⇒ none open (stopped, paused, between zones)
  queue:      reading(Codecs.array(Codecs.struct({ zone: Zone, seconds: Seconds })), { subscribe: true }),   // after the active one
  remainingS: reading(Seconds, { subscribe: true }),                         // the active zone's; frozen while paused
  run:        method('mutates', Codecs.void, Codecs.struct({
                zones:         Codecs.optional(Codecs.array(Codecs.struct({ zone: Zone, seconds: Codecs.optional(Codecs.uint32({ min: 1, unit: 's' })) }))),
                multiplierPct: Codecs.uint16({ min: 1, max: 250, default: 100, unit: '%' }) }),
              { errorKinds: ['unknownZone'] }),
  pause:      method('mutates', Codecs.void),
  resume:     method('mutates', Codecs.void),
  next:       method('mutates', Codecs.void),
  stop:       method('mutates', Codecs.void),
});

export const WaterLeakDetector = device('home.WaterLeakDetector', {
  ...CommonFields,
  leak:          reading(Codecs.bool(), { subscribe: true }),                                    // true = leak, as Matter
  sensorFault:   optional(reading(Codecs.bool(), { subscribe: true })),
  alarm:         optional(reading(Codecs.struct({ active: Codecs.bool(), suppressed: Codecs.bool() }), { subscribe: true })),   // matter origin only
  suppressAlarm: optional(method('mutates', Codecs.void)),                                       // matter origin, with Matter's AlarmSuppress
});
```

- `run` with a zone that is not one of the system's answers `domain-error` `unknownZone`; nothing is queued.
- The 3-way descaler bypass is a `WaterValve` with a name that says so: open = bypass. No type of its own.
- `identify` is unbound on all three.

## 3. Templates

| Template | DeviceType | Roles |
|---|---|---|
| `valve-from-output` (§3.1) | `WaterValve` | `output`: `unipi.ro` \| `unipi.do`, 1 |
| `thermal-valve-from-output` (§3.2) | `WaterValve` | `output`: `unipi.ro` \| `unipi.do`, 1 |
| `irrigation` (§3.3) | `IrrigationSystem` | `zones`: `home.WaterValve`, 1–30 · `master`: `unipi.ro` \| `home.WaterValve`, 0–1 · `pump`: `unipi.ro`, 0–1 |
| `leak-from-di` (§3.4) | `WaterLeakDetector` | `input`: `unipi.di`, 1 · `fault`: `unipi.di`, 0–1 |

Rules every valve template follows:

- **`normallyOpen`** inverts the output: open = output off. The default, `false`, is an NC valve — closed without power, as most solenoid valves and thermal actuators (research/matter/09 §4.1, §4.3).
- **Daemon start:** the output is set to closed before the device answers anything (§1.1).
- An output changed elsewhere is re-derived: `state` follows it. An opening started that way is untimed, `maxOpenS` still applies.
- A `unipi.do` in `pwm` mode marks the device stale (12a §4.2), as 12c-02 §3.
- A write that throws `SourceUnreachable` answers `unreachable`; the timers stop (12a §3).
- Countdowns are one-shot deadlines on the `Clock` (04 §4.1), as `onFor` (12c-02 §3).

### 3.1. `valve-from-output`

A solenoid valve or a spring-return 3-way valve on one relay or DO.

| Setting | Default | Note |
|---|---|---|
| `normallyOpen` | `false` | |
| `travelS` | 0 | `transitioning` this long after each change. A 3-way ball valve: ~8 s (research/matter/09 §4.5) |
| `defaultOpenS` | absent | → `behavior` |
| `maxOpenS` | absent | → `behavior`. Set it for irrigation zones and tank inlets |

`level` is unbound.

### 3.2. `thermal-valve-from-output`

A thermal actuator on a heating circuit. It is slow (~3 min to open), so a `level` is a duty cycle on its output (research/matter/09 §4.3).

| Setting | Default | Note |
|---|---|---|
| `normallyOpen` | `false` | |
| `travelS` | 180 | |
| `periodS` | 600 | duty-cycle period (MDT default) |
| `minPulseS` | 30 | an on or off phase shorter than this is skipped: the output stays as it is for the period |
| `exerciseEveryDays` | 7 | 0 = never |
| `exerciseS` | 300 | |
| `defaultOpenS`, `maxOpenS` | absent | → `behavior` |

- **Duty cycle.** Level 100 ⇒ output on. Below it, each period: on for `level × periodS / 100`, then off. A new level applies from the next period; an `open` from closed starts a period at once.
- **Exercise.** A valve that has not opened for `exerciseEveryDays` opens fully for `exerciseS` and closes — an ordinary timed `open`, reported as one. Days count only while the daemon runs: the template saves `{ closedForS }` through `ctx.state` at the debounce's pace (12a §3), as `TimerRelay` does (12c-05 §3).
- The `output` role's hint (12a §2.4): "A relay wears out under a duty cycle — about 2 years at a 10-minute period. Prefer a digital output and a 24 V DC actuator." (research/matter/09 §4.3).
- `Thermostat` (its own step) drives this valve's `level`; it never switches the output itself.

### 3.3. `irrigation`

Zones are `WaterValve`s — this driver's own devices as sources (12a §3).

| Setting | Default | Note |
|---|---|---|
| `masterLeadS` | 2 | master open before the first zone |
| `pumpLagS` | 2 | pump on after a zone opens, off before it closes |
| `betweenS` | 0 | pause between two zones; the master stays open, the pump is off |

One zone's run:

```
master off?  master on, wait masterLeadS
zone.open({ seconds })              // the zone's own timer closes it — a backstop if this system stops
+pumpLagS             pump on       // only when seconds > 2 × pumpLagS
+seconds − pumpLagS   pump off
+seconds              zone closed (its own timer) → wait betweenS → next zone
queue empty           master off → stopped
```

- `pause`, `next`, `stop`, a zone opened elsewhere: pump off, then the active zone `close()`.
- **Zone opened elsewhere** — the Home UI, Matter, a rule: the system sees it on the zone's `state`, closes the active zone, opens the master if it is off and starts the pump after `pumpLagS`. Its master opens after the zone here, not before.
- **Master** as `unipi.ro`: switched on and off. As `home.WaterValve`: `open({ seconds: 0 })` and `close()`; its own `maxOpenS` may close it mid-run — the admin's to set high enough. 16a never makes the master a zone (§4).
- **Pump** as `unipi.ro`: on and off as above.
- A zone in the role order is a 1-based index; it becomes the zone's Matter tag (§4).
- Nothing is saved (§1.2).

**Rainwater supply.** With a rainwater driver (12i), the master is its supply valve — a `WaterValve` from `valve-from-rainwater-supply` (12c-11 §3.2): opening it is the system's demand for water, and the driver holds back its own use of the pump meanwhile. The pump role stays empty: the garden pump is the rainwater driver's.

### 3.4. `leak-from-di`

A leak module whose output switches a DI's supply (research/matter/09 §5.1).

| Setting | Default | Note |
|---|---|---|
| `invert` | `false` | `true` when wired to the module's NC contact: a cut wire or a dead module then reads as a leak |
| `delayMs` | 1000 | a change must hold this long before `leak` follows (Finder 72.11: 1 s). Both edges |
| `faultInvert` | `false` | for `fault` |

- `leak = input XOR invert`, after `delayMs`. With `delayMs` 0, missed pulses are replayed as in 12c-04 §3.1; with a delay, a pulse shorter than it is dropped.
- `fault`: `sensorFault = fault XOR faultInvert`, at once. Unbound role ⇒ `sensorFault` unbound.
- A stale source ⇒ `markStale(true)` (12c-04 §3.1).
- `alarm` and `suppressAlarm` are unbound.

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`).

**`WaterValve`** — Valve Configuration and Control; feature `LVL` when `level` is bound; never `TS` (research/matter/09 §1.2).

| Matter | Home |
|---|---|
| `Open(OpenDuration, TargetLevel)` | `open({ seconds, level })`: `OpenDuration` absent ⇒ `seconds` absent; null ⇒ `seconds: 0` |
| `Close` | `close` |
| `CurrentState` | `state.current`; null when absent |
| `TargetState` | `state.target` while `current` is `transitioning`; else null |
| `OpenDuration` | the current opening's seconds; null when closed or untimed |
| `RemainingDuration` | `remainingS`; null when 0 |
| `DefaultOpenDuration` | `behavior.defaultOpenS`, null when absent. Writes refused — `manage` only (12c-04 §4 Open, M3.13) |
| `CurrentLevel`, `TargetLevel` | `level.current`, `level.target` — `LVL` only |
| `ValveFault` | `GeneralFault` = `fault.timeout`; `Blocked` = `fault.blocked` |
| event `ValveStateChanged` | when `state.current` reaches `open` or `closed` |

- No Flow Measurement: no source has one.
- `matter` origin (12a §4a): an endpoint of `0x0042` maps to `WaterValve`; `LVL` binds `level`. `TS`'s `AutoCloseTime` is not mapped.

**`IrrigationSystem`** — the parent endpoint of its zones (16a, composed bridged devices): Irrigation System `0x0040` with Operational State.

| Matter | Home |
|---|---|
| `OperationalState` | `stopped` → Stopped, `running` → Running, `paused` → Paused |
| `OperationalStateList` | Stopped, Running, Paused, Error |
| `OperationalError` | always `NoError` — nothing here fails on its own |
| `PhaseList`, `CurrentPhase` | null |
| `CountdownTime` | `remainingS`; null when stopped |
| `Start`, `Stop` | `run({})`, `stop` |
| `Pause`, `Resume` | `pause`, `resume`; outside a compatible state answered `CommandInvalidInState`, as Matter requires |
| event `OperationCompletion` | when `running` → `stopped` with the queue run out; `CompletionErrorCode` 0 |

- Each **zone** is a child Water Valve, mapped as above, with `TagList`: Common Location `Zone` (`0x0006`/`0x04`) + Common Number of its index (`0x0007`/index) — hence at most 30 zones (research/matter/09 §1.3.2).
- **Master and pump** are never children. A master that is a `WaterValve` is bridged on its own, flat, when exposed (research/matter/09 §1.3.3).
- `matter` origin: not imported — no such product found (research/matter/09 §1.3.7). Its Water Valve endpoints import as `WaterValve`s.

**`WaterLeakDetector`** — Boolean State; Boolean State Configuration when `sensorFault` is bound.

| Matter | Home |
|---|---|
| Boolean State `StateValue` | `leak` |
| event `StateChange` | on every change of `leak` — mandatory on this device type (research/matter/09 §1.4) |
| Boolean State Configuration `SensorFault` | `GeneralFault` = `sensorFault`; no features |

- `alarm` and `suppressAlarm` are not projected.
- `matter` origin: an endpoint of `0x0043` maps to `WaterLeakDetector`. Its Boolean State Configuration, when present: `SensorFault.GeneralFault` → `sensorFault`; `AlarmsActive` ≠ 0 → `alarm.active`, `AlarmsSuppressed` ≠ 0 → `alarm.suppressed` (features `VIS`/`AUD`); `SuppressAlarm` → `suppressAlarm`, with each active alarm (`SPRS`). Sensitivity and `EnableDisableAlarm` are not mapped.

## 5. Moving and target

| Device | Field | Reports |
|---|---|---|
| `WaterValve` | `state.target`, `level.target` | at once, on every call (12a §4a) |
| | `state.current` | `transitioning` at once, the target after `travelS`; the target at once with `travelS` 0 |
| | `level.current` | the target after `travelS` |
| | `remainingS` | once a second while timed |
| `IrrigationSystem` | `state`, `activeZone`, `queue` | at every change |
| | `remainingS` | once a second while a timed zone runs |
| `WaterLeakDetector` | — | nothing moves |
