# 12h — Central heating driver

## 1. Scope

Package: `packages/driver-central-heating` (`@evok-node/driver-central-heating`). Config `type: central-heating`. Kinds `heating.*`.

The building's hot-water heating as one system, on the boiler-room PLC: its circuits — one per mixer — and its zones — rooms, each with thermal actuators on relays. It answers the zone requests of the room devices (12c-10 §3.3), drives the relays, and trims circuits 1–3 through the Wolf (12f). Its endpoints are raw driver-kit devices (05a), shown and set in the Inspector (16).

```
room device (12c-10, flat PLC) ──request {mode, level}──► heating.zone ──► relays (unipi.ro) ──► thermal actuators
                                                              │
reference zone's level ──► heating.circuit ──setpointCorrection──► ism8i.circuit (12f) ──► Wolf BM-2
```

- **It knows no room temperature.** The room loop is 12c-10's; a zone only turns a `level` into valve time.
- **The Wolf keeps its control:** heating curve, mixers, pumps. Circuits 1–3 get a setpoint correction from their reference zone (§6); circuits 4–5 are not reachable (12f §1) and run on the Wolf's curve alone.
- **It is the only writer of its relays** (01 §2). They are other drivers' `unipi.ro` endpoints — onboard or extension — reached as `RemoteDevice`s (05a §3.8a). 12c-08's `thermal-valve-from-output` is not used for heating; it stays for valves outside this system.
- **Relays switch slowly on purpose** (§5.2): they are mechanical, and a hydronic system tolerates long periods.

**Not for:**

- Rooms without actuators. Their radiators are always open; a room device without a `heating` role covers their AC (12c-10 §3.2).
- The boiler, DHW, pumps, mixers: the Wolf's.
- Deciding the season. Summer and availability are set by hand, per circuit (§3).

**Must not depend on:** any api, `main`, another driver.

## 2. Configuration — the plant

Static facts: which circuits, zones and relays exist. Tunable values are settings (§3).

```ts
interface Group {
  readonly emitter: 'radiator' | 'floor';      // picks the duty period (§5.2)
  readonly stage: 'base' | 'boost';             // boost = a second emitter that helps the base (§5.3)
  readonly normallyOpen: boolean;               // the actuators' type: open without power
  readonly relays: readonly Address[];          // unipi.ro; several actuators may share one relay
}

interface Zone {
  readonly id: string;                          // tail part: 'flat1.living'
  readonly name: string;
  readonly circuit: string;
  readonly groups: readonly Group[];            // one base group; at most one boost group
}

interface Circuit {
  readonly id: string;                          // 'mk1' … 'mk5'
  readonly name: string;
  readonly reference: string;                   // a zone of this circuit (§6)
  readonly ism8i?: Address;                     // its ism8i.circuit (12f), circuits 1–3 only
}

interface CentralHeatingConfig {
  readonly circuits: readonly Circuit[];
  readonly zones: readonly Zone[];
}
```

```yaml
drivers:
  heating:
    type: central-heating
    circuits:
      - { id: mk1, name: Flat 1, reference: flat1.living, ism8i: wolf:circuit.1 }
      - { id: mk4, name: Flat 4, reference: flat4.living }
    zones:
      - id: flat1.living
        name: Living room
        circuit: mk1
        groups:
          - { emitter: floor,    stage: base,  normallyOpen: true,  relays: [EXT1:2.unipi.ro.01, EXT1:2.unipi.ro.02] }
          - { emitter: radiator, stage: boost, normallyOpen: true,  relays: [EXT1:2.unipi.ro.03] }
      - id: flat1.bedroom
        name: Bedroom
        circuit: mk1
        groups:
          - { emitter: radiator, stage: base, normallyOpen: false, relays: [EXT1:2.unipi.ro.04] }
```

Fatal at `configure()`: a zone or circuit id twice; a zone naming an unknown circuit; a circuit without a reference zone, or a reference in another circuit; a zone without exactly one base group, or with more than one boost group; a relay in two groups.

A relay source of the wrong kind is not fatal: its group is not reachable until it matches (§8), as in 12i §6.4.

## 3. Settings — KV

Edited in the Inspector; one `SET` of `control.settings` persists them in KV before it answers, as 12i §3. Nothing in KV ⇒ the defaults.

```ts
const Min = (d: number, label: string, hint?: string) => Codecs.uint16({ unit: 'min', default: d, label, hint });
const Pct = (d: number, label: string, hint?: string) => Codecs.uint8({ min: 0, max: 100, unit: '%', default: d, label, hint });

const Settings = Codecs.struct({
  periodRadiatorMin: Min(30, 'Radiator duty period'),
  periodFloorMin:    Min(60, 'Floor duty period'),
  minPulseMin:       Min(6,  'Minimum pulse', 'an on or off phase shorter than this is skipped — about 2× the actuator travel'),
  saturationLowPct:  Pct(10, 'Always off at or below'),
  saturationHighPct: Pct(90, 'Always on at or above'),
  levelStepPct:      Pct(10, 'Level step'),
  maxSwitchesPerDay: Codecs.uint16({ default: 40, label: 'Relay switches per day', hint: 'rolling 24 h, per relay' }),
  wearWarning:       Codecs.uint32({ default: 80_000, label: 'Relay wear warning', hint: 'lifetime switches' }),
  exerciseDays:      Codecs.uint8({ default: 7, label: 'Exercise after days unmoved' }),
  exerciseMin:       Min(5, 'Exercise time'),
  requestTimeoutMin: Min(15, 'No request ⇒ baseline', 'the room device re-sends every 5 min (12c-10 §3.3)'),
  boostAfterMin:     Min(45, 'Boost after', 'base group at 100 % this long'),
  boostOffPct:       Pct(70, 'Boost off below'),
  correction: Codecs.struct({
    highPct:  Pct(90, 'Raise when reference at or above'),
    lowPct:   Pct(20, 'Lower when reference at or below'),
    holdMin:  Min(120, 'For at least'),
    stepK:    Codecs.float32({ default: 0.5, unit: 'K', label: 'Step' }),
    minK:     Codecs.float32({ default: -4, unit: 'K', label: 'Lowest' }),
    maxK:     Codecs.float32({ default: 4, unit: 'K', label: 'Highest' }),
    everyMin: Min(30, 'At most every'),
  }),
});
```

- A `SET` that breaks an order answers `domain-error` `invalidSettings`, nothing saved: `saturationLowPct < saturationHighPct`, `minPulseMin` below half of the shorter period, `correction.lowPct < correction.highPct`, `minK < maxK`.
- Per circuit, `season` and `available` (§4) are kept in KV too.
- KV also holds the relays' switch counts (§5.4) and each circuit's desired correction (§6).

## 4. Endpoints

| Tail | Kind | What |
|---|---|---|
| `control` | `heating.control` | settings, alarms |
| `circuit.<id>` | `heating.circuit` | season, availability, reference, correction |
| `zone.<id>` | `heating.zone` | the room's contract (12c-10 §3.3), and what was applied |
| `relay.<zone>.<n>` | `heating.relay` | one relay: state, switches |

```ts
// @evok-node/driver-central-heating
const Percent = Codecs.uint8({ min: 0, max: 100, unit: '%' });
const K       = Codecs.float32({ unit: 'K' });
const Mode    = Codecs.string({ enumValues: ['off', 'heat', 'baseline'] });

export const Control = device('heating.control', {
  settings: channel(Settings, { subscribe: true }),
  alarms:   reading(Codecs.struct({ relayWear: Codecs.array(Codecs.string()), relayUnreachable: Codecs.array(Codecs.string()),
                                    ism8iUnreachable: Codecs.array(Codecs.string()) }), { subscribe: true }),   // tails
});

export const Circuit = device('heating.circuit', {
  season:     channel(Codecs.string({ enumValues: ['heating', 'summer'] }), { subscribe: true }),
  available:  channel(Codecs.bool(), { subscribe: true }),
  reference:  reading(Codecs.string()),                                    // the zone's tail
  correction: optional(reading(Codecs.struct({
                desired:   K,                                              // this driver's target (§6)
                reported:  Codecs.optional(K),                             // what 12f reports
                changedAt: Codecs.optional(Codecs.timestamp()) }), { subscribe: true })),   // bound with `ism8i`
  zones:      reading(Codecs.array(Codecs.struct({ zone: Codecs.string(), mode: Mode, level: Percent, running: Codecs.bool() })), { subscribe: true }),
});

export const Zone = device('heating.zone', {
  request:   channel(Codecs.struct({ mode: Mode, level: Percent }), { subscribe: true }),          // 12c-10 §3.3
  available: reading(Codecs.struct({ heat: Codecs.bool(),
               reason: Codecs.optional(Codecs.string({ enumValues: ['summer', 'fault', 'circuitOff'] })) }), { subscribe: true }),
  running:   reading(Codecs.bool(), { subscribe: true }),                  // a valve of the zone is open
  fallback:  reading(Codecs.bool(), { subscribe: true }),                  // no request for requestTimeoutMin
  reference: reading(Codecs.bool()),
  applied:   reading(Codecs.struct({ mode: Mode, level: Percent, periodMin: Codecs.uint16({ unit: 'min' }) }), { subscribe: true }),
  groups:    reading(Codecs.array(Codecs.struct({ emitter: Codecs.string(), stage: Codecs.string(),
               open: Codecs.bool(), since: Codecs.timestamp() })), { subscribe: true }),
});

export const Relay = device('heating.relay', {
  on:            reading(Codecs.bool(), { subscribe: true }),
  switchesToday: reading(Codecs.uint16(), { subscribe: true }),            // rolling 24 h
  switchesTotal: reading(Codecs.uint32(), { subscribe: true }),
  stretched:     reading(Codecs.bool(), { subscribe: true }),              // period doubled by the budget (§5.2)
});
```

- `request` is set by the room device; a `SET` answers its own value (05a §3.1) and takes effect at the next period (§5.2).
- `season` and `available` are set in the Inspector. They are user decisions; nothing here changes them.

## 5. Zones

### 5.1. Modes

| Situation | Valves | `available` | `running` |
|---|---|---|---|
| `heat` | duty cycle at the applied level (§5.2) | `{ heat: true }` | while open |
| `off` | closed | `{ heat: true }` | false |
| `baseline` — asked for, or no request for `requestTimeoutMin` (`fallback` true) | open — as the house without valves | `{ heat: true }` | true |
| circuit `season: summer` | closed, at rest; exercised (§5.4) | `{ heat: false, reason: 'summer' }` | false |
| circuit `available: false` | closed, at rest | `{ heat: false, reason: 'circuitOff' }` | false |
| no relay of the base group reachable | — | `{ heat: false, reason: 'fault' }` | false |
| the **reference zone**, any of the above | **open, always** (§6) | as its circuit | true |

- A valve is "open" by its type: NO ⇒ relay off, NC ⇒ relay on.
- A mode change applies at once — one switch per relay at most. A level change applies at the next period start.
- Some relays of a group unreachable: the others go on; an alarm names the missing ones.

### 5.2. Duty cycle on relays

A relay is a mechanical contact, rated "up to 100 000" switches (research/matter/09 §4.3). Every rule here exists to switch it less.

| # | Rule |
|---|---|
| R1 | **Period** per emitter: radiator `periodRadiatorMin` (30), floor `periodFloorMin` (60). Actuators travel ~3 min; a floor reacts in hours (research/matter/11 §5) |
| R2 | **Saturation:** applied level ≥ `saturationHighPct` (90) ⇒ on for the whole period; ≤ `saturationLowPct` (10) ⇒ off |
| R3 | **Minimum pulse:** an on or off phase shorter than `minPulseMin` (6) is skipped — the relay stays as it is for the period |
| R4 | **Level steps:** the request's level is rounded to `levelStepPct` (10). The applied level changes only when the request moves a full step away from it — 54 → 50; then 58 stays 50, 61 → 60 |
| R5 | **Mirrored periods:** odd periods are on-then-off, even periods off-then-on, so the on phases of two periods join. At most **one switch per period** |
| R6 | **Budget:** at 80 % of `maxSwitchesPerDay` (40) on a relay, its period doubles (`stretched`) until the rolling count falls below it; at the limit, it holds its state until it may switch again. Opening — towards `baseline` — is always allowed |

Example — radiator zone, 30 min periods, level 60 %:

```
period 1   on 18 min  ┐ off 12 min           — on at 0, off at 18
period 2   off 12 min ┘ on 18 min            — on at 42 (period 2 starts at 30)
period 3   on 18 min (joined with period 2's) off 12 min
           → 1 switch per period: 48 a day at most; level 95 % or 5 % ⇒ 0
```

- **Period starts are staggered** per relay — offset = period × relay index / relay count — so the actuators' switch-on current (< 0.3 A each, research/matter/09 §4.3) is spread, not summed on the 24 V supply.
- Several actuators on one relay act as one.

Expected wear in a heating season of ~150 days:

| Case | Switches a day | A season | 100 000 after |
|---|---|---|---|
| radiator, typical | 15–25 | ~3 000 | ~30 years |
| radiator, worst — at the budget | 40 | 6 000 | ~16 years |
| floor, worst | 24 | 3 600 | ~27 years |
| summer exercise | ~0.3 | ~70 | — |

[I — arithmetic on R1–R6.]

### 5.3. Boost group

A zone's boost group — a radiator that helps a floor sized for part of the load — is on/off, never duty-cycled:

- **on** when the base group's applied level has been ≥ `saturationHighPct` for `boostAfterMin` (45);
- **off** when it drops below `boostOffPct` (70), or the mode is not `heat`.

`baseline` opens it with the base group. Like 12c-10's stage 2, it is the slower, bigger answer to a room that stays cold.

### 5.4. Exercise and counters

- **Exercise.** A valve that hasn't moved for `exerciseDays` (7) is moved for `exerciseMin` (5) — in summer, and in winter for a zone left `off`. MDT uses 6 d / 5 min (research/matter/09 §4.3). Exercises are staggered, one relay at a time; not on the reference zone, which is always open.
- **Counters.** Every relay switch counts: `switchesToday` (rolling 24 h), `switchesTotal` (saved in KV every 10 min and on stop). At `wearWarning` (80 000) the relay is listed in `control.alarms.relayWear`.
- **A write from elsewhere** on a relay — the Inspector on `EXT1:2.unipi.ro.01`: set back at once, counted, a warning logged. As 12i §7, this driver is its only writer.

## 6. Reference zone and circuit correction

Each circuit has one reference zone, usually the living room.

- **Never closed.** It is the circuit's flow path: with every other valve closed, the circuit pump still has a way through (research/matter/11 §5). The mixer is not one: it blends before the pump, the water still has to pass the rooms. Wolf's own rule asks the reference room's valves to be fully open (research/19 §5.3).
- An NO reference zone rests unpowered; an NC one keeps its relay on — no switching either way. NO is the better choice for a reference.
- **Its request drives the correction** of circuits with `ism8i` (1–3):

  | Reference request | For | Desired correction |
  |---|---|---|
  | `heat`, level ≥ `correction.highPct` (90) | `holdMin` (120) without a break | + `stepK` (0.5), up to `maxK` (4) |
  | `heat`, level ≤ `correction.lowPct` (20) | `holdMin` | − `stepK`, down to `minK` (−4) |
  | anything else — `off`, `baseline`, no request, summer, not available | — | unchanged |

  A change resets the hold; at most one change per `everyMin` (30). About 3 K of flow per step at Wolf's default curve (research/19 §7.2).
- **Writing.** `desired` is this driver's, kept in KV. It is written to the circuit's `ism8i.circuit.setpointCorrection` (12f) whenever it differs from what 12f reports: after a change, after 12f reconnects, after a read-all. 12f's own budget applies (12f §5.2); a refused write is tried again at the next difference.
- **First start.** With nothing in KV, `desired` takes the value 12f reports — the driver never resets the Wolf's setting on its own.
- Circuits 4–5 have no correction; their reference zone is only the flow path.

## 7. Restart and persistence

KV holds the settings, each circuit's `season`, `available` and `desired`, and the relay counts — each written before the `SET` or event that changed it answers (06 §7), the counts every 10 min.

At daemon start:

1. Every zone is in `baseline` until its first request: valves open. Nothing of the last requests is restored — a room device re-sends within 5 min (12c-10 §3.3).
2. Relays found in another state are set — counted like any switch.
3. Period starts are staggered afresh (§5.2).

**The PLC itself down:** relays drop out (09's section watchdog, research/matter/09 §4.6). NO zones open, NC zones close — the living rooms and bathrooms keep their heat, bedrooms don't. The Wolf heats on its curve meanwhile.

## 8. Failure modes

| Failure | Result |
|---|---|
| a room device stops sending | after `requestTimeoutMin`: `baseline`, `fallback` true |
| a relay's driver down or not matching | that relay not reachable; its group goes on with the others; alarm `relayUnreachable`; no relay of the base group ⇒ zone `fault` |
| 12f unreachable | no correction writes; zones unaffected; alarm `ism8iUnreachable` |
| a relay at its budget | holds; opening still allowed; `stretched`, warning |
| relay wear at `wearWarning` | alarm `relayWear` |
| KV not reachable at start | defaults, `season: heating`, `available: true`, `desired` from 12f, counts from 0; a `SET` of settings answers `unreachable` |

## 9. Commissioning

1. Per zone: switch each relay from the Raw Relay or onboard driver, before this driver runs, and note which actuators move and whether they are NO or NC.
2. Per circuit: choose the reference zone; prefer NO actuators there.
3. Balance the floor manifolds' loops by their flow meters; the driver doesn't.
4. Set each circuit's `season` and `available` in the Inspector.
5. Watch `relay.*.switchesToday` for a week of heating; adjust periods only if wear runs high.

## 10. Open

- **Correction tuning** — thresholds and hold time on the real building, per circuit.
- **The Wolf's own summer switch** (20 °C average, research/19 §7.2) and the manual `season` can disagree. Whether the Inspector should show a hint when they do.

## 11. Testing

Tier 1 (basics/03), fake `Clock`, fake relay sources, a fake 12f circuit:

- Config: every fatal case of §2.
- Modes: each row of §5.1, the reference zone always open, `fallback` after the timeout, `fault` with no base relay.
- Duty: R1–R6 one by one — saturation, minimum pulse, level steps with hysteresis, mirrored periods (one switch per period), staggered starts, budget stretching and holding, opening always allowed.
- Boost: on after the hold, off below `boostOffPct`, open in `baseline`.
- Exercise: after `exerciseDays`, one at a time, never the reference.
- Correction: up and down after `holdMin`, limits, `everyMin`; written on a difference, again after a 12f reconnect; first start adopts 12f's value.
- Counters: rolling 24 h, saved and restored; wear alarm; a write from elsewhere set back and counted.
- Restart: everything `baseline`, counts restored.
