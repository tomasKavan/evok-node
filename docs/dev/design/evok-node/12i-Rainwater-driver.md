# 12i — Rainwater driver

## 1. Scope

Package: `packages/driver-rainwater` (`@evok-node/driver-rainwater`). Config `type: rainwater`. Kinds `rainwater.*`.

Runs a rainwater system: up to three tanks, their valves and the garden pump — refills, the transfer to an upper tank, the pump's cutoff, alarms. It is plant technology, not a user-facing device: its endpoints are raw driver-kit devices (05a), shown and controlled in the Inspector UI (16). The Home UI sees it through `RainwaterTank`, a supply valve and an alarm detector (12c-11).

```
rain ──► lower tank ──overflow──► retention tank ──sludge pump (own floats)──► sewer
          │  ▲  ▲
          │  │  └── mains valve ◄── descaler bypass (other PLC) ◄── mains
     fill │  │ drain (gravity)
     valve▼  │
          upper tank

garden pump in the lower tank ──► fill valve, irrigation zones, garden taps   (its own pressure switch)
```

| Part | Here | Example (drawing 3.3.2.5) |
|---|---|---|
| lower tank | required: level, low and high float | 6 m³, WL.009.02, FS.009.01, FS.009.02 |
| upper tank | optional: level, fill and drain valves | 4 m³, WL.009.01, EV.009.05, EV.009.06 |
| retention tank | optional: level, high float | 4 m³, WL.009.03, FS.009.03 |
| mains valve | optional | EV.103.01 |
| descaler bypass | optional, needs the mains valve; on another PLC | — |
| garden pump | required: its power | an RO's NO contact |

The driver owns no transport. Its sources are other drivers' devices, reached as `RemoteDevice`s (05a §3.8a); the bypass over a `RemoteLink` (05a §3.8b). Its mode, settings and the mains lock live in its KV namespace (06).

**Not for:**

- The sludge pump: it runs on its own floats and reports nothing.
- Irrigation zones and taps: zones are `WaterValve`s (12c-08); the pump serves them on its pressure switch. The irrigation system asks for water through `supply` (§4).
- Schedules and weather: the almanac (12d), §11.

**Must not depend on:** any api, `main`, another driver. The home templates (12c-11 §3) are in the `@evok-node/driver-rainwater/home` subpath, which imports `driver-home`'s types (12a §3); the driver itself never does.

## 2. Configuration — the plant

Static facts only: what the tanks are and which outputs and inputs drive them. Everything tunable is in KV (§3).

```ts
type Float = Address | { readonly address: Address; readonly invert: true };   // unipi.di; true = the float is up
type LevelSource =
  | Address                                                                          // dyp.ds1603da (07a §10.5) — mm above the bottom
  | { readonly address: Address; readonly mA: [number, number]; readonly mm: [number, number] };   // unipi.ai in a current mode — linear

interface Tank {
  readonly capacityL: number;   // litres at fullMm
  readonly fullMm: number;      // water height at 100 %
  readonly level: LevelSource;
}

interface RainwaterConfig {
  readonly pump: Address;                                                              // unipi.ro | unipi.do — the pump's power
  readonly lower: Tank & { readonly lowFloat?: Float; readonly highFloat?: Float };
  readonly upper?: Tank & { readonly fill: Address; readonly drain: Address };         // unipi.ro | unipi.do
  readonly retention?: Tank & { readonly highFloat?: Float };
  readonly mains?: Address;                                                            // unipi.ro | unipi.do
  readonly bypass?: { readonly url: string; readonly address: Address };               // RemoteLink (05a §3.8b); unipi.ro | unipi.do there
}
```

```yaml
drivers:
  rain:
    type: rainwater
    pump:  PLC:2.unipi.ro.01
    lower:
      capacityL: 6000
      fullMm: 1500
      level: RS2:2.dyp.ds1603da.01
      lowFloat:  PLC:2.unipi.di.04
      highFloat: PLC:2.unipi.di.05
    upper:
      capacityL: 4000
      fullMm: 1400
      level: { address: PLC:1.unipi.ai.01, mA: [4, 20], mm: [0, 2000] }   # from the sensor's label
      fill:  PLC:2.unipi.ro.02     # EV.009.05
      drain: PLC:2.unipi.ro.03     # EV.009.06
    retention:
      capacityL: 4000
      fullMm: 1500
      level: RS2:3.dyp.ds1603da.01
      highFloat: PLC:2.unipi.di.07
    mains: PLC:3.unipi.ro.01       # EV.103.01
    bypass: { url: wss://house-plc/api, address: ONB:2.unipi.ro.04 }
```

Fatal at `configure()`: `bypass` without `mains`; a `fullMm` above 2000 with a `dyp.ds1603da` level (its range, research/15 §1.1). A source of the wrong kind is not fatal: that part is not `reachable` until it matches (§6.4).

## 3. Settings — KV

Tunable at runtime from the Inspector, which renders the form from the annotations (05a §3.1a). One `SET` of `control.settings` (§4) persists them in KV before it answers, then they apply (06 §7). Nothing in KV ⇒ the defaults.

```ts
// @evok-node/driver-rainwater
const Pct = (d: number, label: string, hint?: string) => Codecs.float32({ min: 0, max: 100, unit: '%', default: d, label, hint });
const S   = (d: number, label: string, hint?: string) => Codecs.uint32({ unit: 's', default: d, label, hint });

const Settings = Codecs.struct({
  lowPct:            Pct(10, 'Low level', 'used when the low float is not configured or not reachable'),
  highPct:           Pct(90, 'High level', 'used when the high float is not configured or not reachable'),
  refillPct:         Pct(33, 'Refill amount', 'added to the lower tank when it is low'),
  transferPct:       Pct(50, 'Transfer amount', 'taken from the lower tank to the upper one when it is high'),
  upperEmptyPct:     Pct(5,  'Upper tank empty'),
  upperFullPct:      Pct(95, 'Upper tank full'),
  cutoffPct:         Pct(5,  'Pump cutoff', 'the pump loses power at or below this level of the lower tank'),
  resumePct:         Pct(10, 'Pump resume', 'above cutoff'),
  retentionAlarmPct: Pct(66, 'Retention alarm'),
  mainsMaxS:         S(1200, 'Mains refill limit', 'mains open longer than this ⇒ closed and locked until acknowledged'),
  bypassLeadS:       S(30, 'Bypass lead', 'bypass on this long before the mains valve opens'),
  bypassLagS:        S(5,  'Bypass lag', 'bypass off this long after the mains valve closes'),
  settleS:           S(10, 'Upper level settle', 'after the drain closes, before the upper level is read'),
  smoothingS:        S(30, 'Smoothing window'),
  deadbandMm:        Codecs.uint16({ unit: 'mm', default: 10, label: 'Level deadband' }),
});
```

- A `SET` that breaks an order answers `domain-error` `invalidSettings`, nothing saved: `cutoffPct < resumePct ≤ lowPct < highPct`, `upperEmptyPct < upperFullPct`.
- A value saved that no longer decodes (after an upgrade) ⇒ the defaults, and a warning logged.
- A new value applies at once; a running process keeps the target it computed at its start (§5.1).

## 4. Endpoints

Bound once at `attach()` (05a §3.8); the table never changes. A part not configured is not bound — no `upper` without `upper:`, no `valve.bypass` without `bypass:`.

| Tail | Kind | What |
|---|---|---|
| `control` | `rainwater.control` | mode, process, settings, calls, alarm summary, parts |
| `lower`, `upper`, `retention` | `rainwater.tank` | level and floats |
| `pump` | `rainwater.pump` | the pump's power, cutoff |
| `valve.fill`, `valve.drain`, `valve.mains`, `valve.bypass` | `rainwater.valve` | one valve |
| `supply` | `rainwater.supply` | the irrigation system's demand — fixed, always bound |
| `alarm.retentionHigh`, `alarm.refillFailed`, `alarm.cutoff`, `alarm.sensor`, `alarm.bypass` | `rainwater.alarm` | one alarm each; `retentionHigh` with a retention tank, `refillFailed` with mains, `bypass` with a bypass |

```ts
// @evok-node/driver-rainwater
const Mm = Codecs.uint16({ unit: 'mm' });
const Level = Codecs.struct({
  mm:      Codecs.optional(Mm),                                         // absent ⇒ no valid value (§6.4)
  percent: Codecs.optional(Codecs.float32({ min: 0, max: 100, unit: '%' })),
  litres:  Codecs.optional(Codecs.uint32({ unit: 'l' })),
  held:    Codecs.bool(),                                               // upper only: not measured now (§6.3)
});
const Mode    = Codecs.string({ enumValues: ['auto', 'manual', 'off'] });
const Process = Codecs.string({ enumValues: ['idle', 'refillFromUpper', 'refillFromMains', 'fillUpper'] });
const Alarms  = Codecs.struct({ retentionHigh: Codecs.bool(), refillFailed: Codecs.bool(), cutoff: Codecs.bool(),
                                sensor: Codecs.bool(), bypass: Codecs.bool() });
const Tail    = Codecs.string();
const Parts   = Codecs.struct({                                         // this driver's own tails — for the home bundle (12c-11 §3.4); absent ⇒ not configured
  lower: Tail, upper: Codecs.optional(Tail), retention: Codecs.optional(Tail), supply: Tail,
  alarms: Codecs.struct({ retentionHigh: Codecs.optional(Tail), refillFailed: Codecs.optional(Tail), cutoff: Tail,
                          sensor: Tail, bypass: Codecs.optional(Tail) }),
});

export const Control = device('rainwater.control', {
  mode:      channel(Mode, { subscribe: true }),
  process:   reading(Process, { subscribe: true }),
  target:    reading(Codecs.optional(Codecs.struct({ tank: Codecs.string({ enumValues: ['lower', 'upper'] }),
               percent: Codecs.float32({ unit: '%' }) })), { subscribe: true }),   // the running process's stop level
  settings:  channel(Settings, { subscribe: true }),
  alarms:    reading(Alarms, { subscribe: true }),
  parts:     reading(Parts),
  refill:    method('mutates', Codecs.void, Codecs.void, { errorKinds: ['notAuto', 'notPossible'] }),
  fillUpper: method('mutates', Codecs.void, Codecs.void, { errorKinds: ['notAuto', 'notPossible'] }),
  stop:      method('mutates', Codecs.void),
  ack:       method('mutates', Codecs.void),
});

export const Tank = device('rainwater.tank', {
  '@':      reading(Level, { subscribe: true }),                        // smoothed (§6.2)
  raw:      reading(Codecs.optional(Mm), { subscribe: true }),          // every source value, converted, not smoothed
  low:      optional(reading(Codecs.bool(), { subscribe: true })),      // the low float: true = the tank is low
  high:     optional(reading(Codecs.bool(), { subscribe: true })),      // the high float: true = the tank is high
  capacity: reading(Codecs.struct({ litres: Codecs.uint32({ unit: 'l' }), fullMm: Mm })),   // from config
});

export const Valve = device('rainwater.valve', {
  '@':      channel(Codecs.bool(), { subscribe: true }),                // true = open; SET in `manual` only (§7)
  openedAt: reading(Codecs.optional(Codecs.timestamp()), { subscribe: true }),
});

export const Pump = device('rainwater.pump', {
  '@':    channel(Codecs.bool(), { subscribe: true }),                  // powered; SET in `manual` only (§7)
  cutoff: reading(Codecs.bool(), { subscribe: true }),
});

export const Supply = device('rainwater.supply', {
  demand:    channel(Codecs.bool(), { subscribe: true }),               // set by the home supply valve (12c-11 §3.2)
  available: reading(Codecs.bool(), { subscribe: true }),               // §5.2
});

export const Alarm = device('rainwater.alarm', {
  '@': reading(Codecs.struct({ active: Codecs.bool(), since: Codecs.optional(Codecs.timestamp()) }), { subscribe: true }),
});
```

| Call | Effect |
|---|---|
| `refill` | starts a refill now (§5.1), as if the lower tank were low. `notAuto` outside `auto`; `notPossible` when no source can refill (no upper water, no mains or mains locked, bypass unreachable) or the lower tank is high |
| `fillUpper` | starts a transfer now. `notAuto`; `notPossible` without an upper tank, at cutoff, with the upper tank full or a demand on |
| `stop` | ends the running process; it does not start again until its start condition has been false once (§5.1) |
| `ack` | clears `refillFailed` and its lock (§5.3) |

A call that changes nothing — `refill` while refilling, `stop` while `idle` — answers `ok`.

## 5. Control in `auto`

### 5.1. Processes

One process at a time. A process starts when its start condition holds and no process runs — checked on every change of an input, so it also starts after a daemon start, a mode change or a bypass coming back. `stop` blocks a restart until the condition has been false once.

| Process | Start condition | Does | Ends when |
|---|---|---|---|
| `refillFromUpper` | lower low, upper above `upperEmptyPct` | drain open | lower reaches its target, or lower high. Upper reaches `upperEmptyPct` ⇒ `refillFromMains` for the rest |
| `refillFromMains` | lower low, no upper water; or from `refillFromUpper` | the bypass sequence (§5.3), mains open | lower reaches its target, or lower high; mains past `mainsMaxS` (§5.3) |
| `fillUpper` | lower high, upper below `upperFullPct`, no demand, no cutoff | fill open — the pump pushes water up on its pressure switch | upper reaches `upperFullPct`, lower reaches its target, cutoff. A demand pauses it (§5.2) |
| `idle` | — | every valve this driver opened is closed | — |

- **Lower low** is `lower.low`; without that float, or while it isn't reachable, the level at or below `lowPct`. **Lower high** likewise: `lower.high`, else at or above `highPct`.
- **Targets** are relative, computed at the start: a refill's is the start level + `refillPct`, a transfer's the start level − `transferPct`. `target` (§4) reports the one running.
- **No lower level** (§6.4): a refill runs until lower high, a mains refill still capped by `mainsMaxS`; `fillUpper` doesn't start — its target is unknown.
- **No upper level**: `refillFromUpper` and `fillUpper` don't start — a refill goes to mains.
- **Interlocks** (§5.5) hold in every process.

Example:

```
08:00  lower.low true, lower 9 %, upper 60 %      → refillFromUpper, target 42 %: drain open
08:09  upper estimate 5 % (§6.3)                  → drain closed, settle 10 s; upper reads 7 % → drain open again
08:10  upper 5 % at rest                          → refillFromMains: bypass on, 30 s, mains open
08:13  lower 42 %                                 → mains closed, 5 s, bypass off → idle
15:20  rain: lower.high true, lower 91 %          → fillUpper, target 41 %: fill open, the pump runs
15:40  supply.demand true (irrigation)            → fill closed — paused
16:05  supply.demand false                        → fill open again, same target
16:30  upper 95 %                                 → fill closed → idle
```

### 5.2. Pump, cutoff and demand

- **The pump is powered** in `auto` except at cutoff: lower at or below `cutoffPct`. Power returns above `resumePct`. Without a lower level, cutoff follows lower low (§5.1) — earlier, but safe. The pump also has its own dry-run protection; this is not a replacement for it.
- `pump.cutoff` and `alarm.cutoff` are true while cut off.
- `supply.available` = the pump powered, not at cutoff, `mode` not `off`, the pump's source reachable.
- **A demand** (`supply.demand` true) pauses `fillUpper`: the fill valve closes, the target is kept. When the demand ends, it goes on unless its end condition holds. A demand changes nothing else — the pump is already powered.

### 5.3. Mains and the descaler bypass

```
bypass on ── bypassLeadS ──► mains open ── … ──► mains closed ── bypassLagS ──► bypass off
```

- Without `bypass` configured the mains valve opens at once.
- **Bypass unreachable** — the link down, the endpoint not matching (05a §3.8b), a `SET` answering `unreachable` — ⇒ no mains refill, no exception: `refillFromMains` doesn't start; a running one closes the mains valve and ends. `alarm.bypass` is true while unreachable. A refill starts again when it comes back (§5.1).
- **`mainsMaxS`**, counted from the mains valve opening: the valve closes, `alarm.refillFailed` turns true, and no mains refill starts until `ack`. The lock is saved in KV (§8).
- The bypass goes off after `bypassLagS` whenever the mains valve closes, for any reason.

### 5.4. Retention

`alarm.retentionHigh` is true while the retention level is at or above `retentionAlarmPct`, or `retention.high` is true. Nothing else happens — the sludge pump is not this driver's.

### 5.5. Interlocks

Hold in `auto` and `manual`:

- Fill and drain are never open together.
- Mains opens only with the bypass on for `bypassLeadS`, when a bypass is configured.
- The pump is never powered at cutoff.
- Mains closes after `mainsMaxS`.

## 6. Measurement

### 6.1. Conversion

| Source | mm |
|---|---|
| `dyp.ds1603da` | as read; under 40 mm (its blind zone) ⇒ 0 (research/15 P3) |
| `unipi.ai` | linear between the `mA` and `mm` pairs; outside 3.6–21.0 mA ⇒ no value (NAMUR NE 43, research/15 §2) |

`percent = mm / fullMm × 100`, clamped to 0–100; `litres = percent × capacityL / 100` — the tanks are boxes.

### 6.2. Smoothing

- `@`'s level is the median of the source's values over the last `smoothingS`. It emits when it differs from the last emitted value by `deadbandMm` or more.
- The first value after a start, or after the source was not reachable, emits at once.
- `raw` emits every value, for diagnostics.
- The DS1603DA's own process value is already filtered (research/15 §1.4); this is on top.

### 6.3. The upper level, at rest only

The upper tank's pressure sensor sits on its outlet pipe: while the drain is open, it reads low (research/15 §3).

- The reading is used only after the drain has been closed for `settleS`. Otherwise `upper` keeps its last value with `held: true`.
- **During `refillFromUpper`** the upper level is estimated: its last value at rest minus what the lower tank gained since. Rain into the lower tank makes the estimate low — the refill checks earlier, never later.
- When the estimate reaches `upperEmptyPct`, the drain closes for `settleS` and the upper level is read. Still above ⇒ the drain opens again; else the refill goes to mains (§5.1).

### 6.4. Sources not reachable

- Each source is followed with `watchDevice` (05a §4b); a stale `polled` value counts as not reachable.
- A level not reachable, or with no value (§6.1): that tank's `mm`, `percent` and `litres` are absent; `alarm.sensor` is true.
- A float not reachable: its field keeps its last value; §5.1 uses the level instead; `alarm.sensor` is true.
- An output not reachable — pump, a valve: its `@` keeps its last value; a process that needs it doesn't start, a running one ends. A pump not reachable ⇒ `supply.available` false.

## 7. Modes

| `mode` | Processes | `SET` on a valve's or the pump's `@` |
|---|---|---|
| `auto` | §5 | refused, `domain-error` `notManual` |
| `manual` | none; `refill`/`fillUpper` answer `notAuto` | accepted; one that breaks an interlock (§5.5) is refused, `domain-error` `interlock` |
| `off` | none | refused, `notManual`; every valve closed, pump off |

- **A mode change** ends the running process and closes every valve; the pump follows the new mode.
- **A write from elsewhere** — an output changed on its own driver, say from the Inspector on `PLC:2.unipi.ro.02`: in `auto` and `off` it is set back at once and a warning logged; in `manual` it is taken as a `SET` here, and set back if it breaks an interlock.
- `mode` is saved in KV with the settings (§8).

## 8. Restart and persistence

KV holds `{ mode, settings, refillLock }`, each written before the `SET` or the event that changed it answers (06 §7).

At daemon start:

1. Every valve this driver controls is set closed — the bypass as soon as its link is up. The pump follows the saved mode, at cutoff once the lower level is known.
2. `process` is `idle`. No process is saved: one whose start condition still holds starts again (§5.1), with a target from the level now.
3. `alarm.refillFailed` and the lock are restored. Other alarms follow their inputs.

## 9. Commissioning

- **DS1603DA addresses.** Every sensor ships as address 1 (research/15 §1.3). Re-address each one alone on the line with FC 6 on register 0x04, through a Raw Relay Driver (07 §6) on that line, before the extension driver takes it:

  ```
  CALL RS2RAW:raw.writeSingleRegister { "unit": 1, "address": 4, "value": 3 }
  ```

- **Mounting.** Under the tank bottom, with couplant and no air gap (research/15 §1.2). Check the reading at a known level.
- **4–20 mA.** The `mm` pair comes from the sensor's label (its range), offset by the height between the tank bottom and the sensor (research/15 §3).
- **`settleS`.** Close the drain with water in the upper tank and watch `raw` settle.

## 10. Failure modes

| Failure | Result |
|---|---|
| A level source down | that tank's level absent, `alarm.sensor`; §5.1's fallbacks |
| A float down | the level stands in, `alarm.sensor` |
| An output source down | its process doesn't start or ends; pump ⇒ `supply.available` false |
| Bypass link down | no mains refill, `alarm.bypass` (§5.3) |
| Mains open too long | closed, `alarm.refillFailed`, locked until `ack` |
| KV not reachable at start | defaults, `mode` `auto`, no lock; an error logged. A `SET` of `settings` or `mode` answers `unreachable` |

## 11. Open

- **Forecast.** Before heavy rain, start `fillUpper` early so the lower tank has room — the retention tank and the sewer take less. Needs the almanac's rain forecast (12d). Deferred to M3.4.

## 12. Testing

Tier 1 (basics/03), fake `Clock`, fake source devices, a fake `RemoteLink`:

- Each §5.1 row: start condition, what opens, each end condition. Targets are relative to the start level.
- `refillFromUpper` switches to mains when the upper tank runs empty, by the estimate and the check at rest (§6.3).
- Bypass: lead and lag; unreachable ⇒ no mains refill and `alarm.bypass`; a refill starts again when it comes back.
- `mainsMaxS` ⇒ closed, `refillFailed`, lock survives a restart, cleared by `ack`.
- Cutoff and resume with hysteresis; `supply.available`.
- A demand pauses `fillUpper` and it resumes with the same target.
- Interlocks in `auto` and `manual`; `notManual`, `interlock`, `notAuto`, `notPossible`.
- A write from elsewhere is set back in `auto`, taken in `manual`.
- Smoothing: median window, deadband, first value at once; the 4–20 mA limits; the blind zone.
- `settings`: order checks, persisted before the answer, defaults when KV holds nothing or something that doesn't decode.
- Restart: everything closed, `idle`, a process whose condition holds starts again.
