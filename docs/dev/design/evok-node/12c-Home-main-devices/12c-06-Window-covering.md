# 12c-06 — Window covering

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `WindowCovering` | lift, optional tilt, wind protection | Window Covering `0x0202` |

**For:** a motorised cover that goes up and down — an exterior venetian blind, a roller shutter, an awning — with or without slats that tilt.

**Not for:**

- A window, a garage door or a gate: `Closure` (12c-07). Matter 1.5 makes them a Closure, not a Window Covering (research/matter/06 §1.5).
- Covers with position feedback (an encoder, a motor that reports its position). No built-in source has one; a template for one keeps these fields.
- Rain, frost and sun automation. They are rules (12b); only wind is built in (§1.2).

### 1.1. Behaviour

Positions are Matter's: **0.01 % closed**, `0` = fully open (up), `10000` = fully closed (down). Tilt the same: `0` = slats open, `10000` = slats closed. 16a maps them 1:1; UI components show them as %.

| Action | Effect |
|---|---|
| `goTo({ lift?, tilt? })` | to the lift position first, then the tilt (§3.2). An absent field keeps its target |
| `up`, `down` | `goTo({ lift: 0, tilt: 0 })`, `goTo({ lift: 10000, tilt: 10000 })` |
| `stop` | stops; targets := current |
| `reference({ end })` | runs to that end with overrun; the position is then exact |
| a call while moving | merges: the given targets replace the running ones, the move continues from where it is |
| daemon start | relays off; the template restores the saved position (§3.5) |

- **Every move to an end is a reference.** It runs the overrun (§3.1) against the motor's own limit switch, and the position is then exact (research/matter/06 §3.1).
- **Position may be unknown.** `current` is absent after a restart mid-move, or after both relays were seen on together. Until the next end, a `goTo` to a middle position first runs to the end nearer its target.
- **Tilt is restored.** A `goTo` without `tilt` brings the slats back to the angle they had before it.

### 1.2. Wind protection

The cover protects itself from wind; no rule is involved. It compares **gusts** against two levels (research/matter/06 §4.6):

| Level | On rise | While active |
|---|---|---|
| 1 | a cover not fully up whose slats are not open: tilt to 0 | tilt refused; after a lift move the slats go to 0, not back |
| 2 | `up` | everything but `up` and `reference({ end: 'up' })` refused |

- **Fast in, slow out.** A level rises on the first gust at or over its threshold. It drops after gusts have stayed below threshold × (100 − `hysteresisPct`) / 100 for `releaseAfterMs`.
- **Which levels act** is the `protection` setting: `none`, `level1`, `level2` or `both`. A level that doesn't act is still reported.
- **Source lost** — no fresh gust for `sourceLostAfterMs`, or the source unreachable: `onSourceLost` (`none`, `level1`, `level2`) acts as that level until the source is back. Then the level follows gusts again, with the release delay.
- **Release.** `onRelease`: `none` stays where protection left it; `restore` goes back to the targets from before the level rose.
- A refused call answers `domain-error` `protected` (§2); the move in progress, if any, goes on.

Thresholds are set at commissioning: level 2 at the cover's wind-class speed, level 1 below it (research/matter/06 §4.5).

## 2. Fields

```ts
// @evok-node/driver-home
const Closed = Codecs.uint16({ max: 10000, unit: '0.01%' });   // Matter Percent100ths: 0 = open/up, 10000 = closed/down
const MetresPerSecond = Codecs.float32({ min: 0, unit: 'm/s' });

const Moving = Codecs.struct({
  current: Codecs.optional(Closed),       // absent ⇒ unknown (§1.1)
  target:  Closed,
  motion:  Codecs.string({ enumValues: ['stopped', 'opening', 'closing'] }),
});

const Wind = Codecs.struct({
  level:  Codecs.uint8({ max: 2 }),       // highest level risen, acting or not
  acting: Codecs.uint8({ max: 2 }),       // highest level that acts (protection setting) — what the cover obeys
  source: Codecs.string({ enumValues: ['ok', 'lost', 'none'] }),   // none ⇒ no wind role
  gust:   Codecs.optional(MetresPerSecond),
});

const CoverBehavior = Codecs.struct({     // settings a consumer must see (12a §2.3) — 16a reports them
  endProductType: Codecs.string({ enumValues: ['exteriorVenetianBlind', 'interiorVenetianBlind', 'rollerShutter', 'rollerShade', 'awning'] }),
  protection:     Codecs.string({ enumValues: ['none', 'level1', 'level2', 'both'] }),
});

export const WindowCovering = device('home.WindowCovering', {
  ...CommonFields,
  lift:      reading(Moving, { subscribe: true }),
  tilt:      optional(reading(Moving, { subscribe: true })),   // unbound ⇒ no slats
  wind:      reading(Wind, { subscribe: true }),
  behavior:  reading(CoverBehavior, { subscribe: true }),
  goTo:      method('mutates', Codecs.void, Codecs.struct({ lift: Codecs.optional(Closed), tilt: Codecs.optional(Closed) }), { errorKinds: ['protected', 'interlock'] }),
  up:        method('mutates', Codecs.void, undefined, { errorKinds: ['protected'] }),
  down:      method('mutates', Codecs.void, undefined, { errorKinds: ['protected', 'interlock'] }),
  stop:      method('mutates', Codecs.void, undefined, { errorKinds: ['protected'] }),
  reference: method('mutates', Codecs.void, Codecs.struct({ end: Codecs.string({ enumValues: ['up', 'down'] }) }), { errorKinds: ['protected', 'interlock'] }),
});
```

- `tilt` in `goTo` on a cover without tilt is ignored.
- `interlock`: a down move refused because the window it shares a KLF with isn't closed (12c-07 §3.2).
- `wind.level` with `acting` lower is a level the `protection` setting switched off — the Home UI can still show it.
- `identify` is unbound: moving a cover to identify it is unsafe, like a load (12c-02 §1.1).

## 3. Templates

| Template | Roles |
|---|---|
| `cover-from-relays` (§3.1–§3.5) | `up`: `unipi.ro` \| `unipi.do`, 1 · `down`: `unipi.ro` \| `unipi.do`, 1 · `wind`: the almanac's wind DeviceType (12d), 0–1, `reachable: false` (12a §3) |
| `cover-from-klf` (§3.6) | `up`: `unipi.ro`, 1 · `down`: `unipi.ro`, 1 · `feedback`: `unipi.di`, 0–1 · `wind`: as above |

One motor on two relays, no feedback (research/matter/06 §3). The motor stops itself at its ends.

### 3.1. Settings

| Setting | Default | Note |
|---|---|---|
| `upMs`, `downMs` | required | full travel, measured end to end, tilt included |
| `tiltMs` | absent | measured alone, closed → open; absent ⇒ no tilt, `tilt` unbound. Must be below `upMs` and `downMs` |
| `overrunPct` | 10 | added to a move to an end, % of that direction's full travel |
| `reversePauseMs` | 500 | before any start opposite to the last run (MDT, Loxone) |
| `startDelayMs` | 0 | motor start lag, added to every run |
| `minPulseMs` | 100 | a run shorter than this is skipped |
| `referenceAfterMoves` | 20 | after this many moves without reaching an end, the next middle `goTo` runs to the nearer end first; 0 = never |
| `endProductType` | `exteriorVenetianBlind` | → `behavior`, 16a |
| `protection` | `both` | which wind levels act (§1.2) → `behavior` |
| `level1`, `level2` | required with `wind` | gust thresholds, m/s; `level1` < `level2` |
| `hysteresisPct` | 20 | |
| `releaseAfterMs` | 900000 (15 min) | |
| `sourceLostAfterMs` | 7200000 (2 h) | the forecast updates hourly at best (research/matter/06 §4.4) |
| `onSourceLost` | `level2` | `none` \| `level1` \| `level2` |
| `onRelease` | `none` | `none` \| `restore` |

Settings change only through `manage` (12a §2.3) — the Home API does not relay settings (12a §5), so they are set in the Inspector UI.

### 3.2. Moves

Tilt runs first in each direction, then the lift (research/matter/06 input). Per direction:

```
liftMs(up)   = upMs − tiltMs         liftMs(down) = downMs − tiltMs
tiltPhase(d) = tiltMs × (d = down ? 10000 − tilt : tilt) / 10000   // slats to that direction's end first
```

`goTo({ lift: L, tilt: T })`, from `lift`, `tilt`:

```
d = sign(L − lift)                                       // down when closing
if d: run d for  startDelayMs + tiltPhase(d) + liftMs(d) × |L − lift| / 10000  (+ overrun when L is 0 or 10000)
T' = T ?? (wind acting ≥ 1 ? 0 : tilt before the call)
t  = d = down ? 10000 : d = up ? 0 : tilt                // where the lift run left the slats
if T' ≠ t: run (T' < t ? up : down) for  startDelayMs + tiltMs × |T' − t| / 10000
```

Example — `upMs` 60 000, `downMs` 55 000, `tiltMs` 1 500; from lift 0, tilt 0; `goTo({ lift: 6000, tilt: 3000 })`:

| Step | Relay | ms |
|---|---|---|
| tilt to closed, lift 0 → 6000 | `down` | 1 500 + 53 500 × 0.6 = 33 600 |
| pause | — | 500 |
| tilt 10000 → 3000 | `up` | 1 500 × 0.7 = 1 050 |

- **Interlock.** The template never has both relays on. A run starts only after the other relay's off-write is acknowledged, and after `reversePauseMs` when it reverses.
- **Time is counted from the acks.** A run's duration is measured from the on-write's ack to the off-write's ack, on the `Clock` (04 §4.1); `current` follows from it.
- **Merge.** A call during a run recomputes the plan from the current position; a reversal stops first and pauses.
- **Reference after moves.** Every run that ends in the middle counts one; reaching an end resets the count. At `referenceAfterMoves`, the next middle `goTo` first runs to the end nearer its target, then on — as with an unknown position (§1.1).
- A source that throws `SourceUnreachable` (12a §3): both relays are written off, the call answers `unreachable`, `current` becomes absent.
- A `unipi.do` in `pwm` mode marks the device stale (12a §4.2), as 12c-02 §3.

### 3.3. Relays switched elsewhere

A relay change that is not the template's own echo (12c-01 §3.1) — a wall button through DirectSwitch, a write in the Inspector — is tracked as a move:

| Seen | Then |
|---|---|
| one relay on | a run in its direction, counted from the poll that saw it; `motion` follows |
| that relay off | the run ends; `current` computed |
| both on | both written off, `current` absent |

Tracking is accurate to one poll period (12c-03 §3). Wind protection still applies: a foreign run the acting level refuses is stopped.

### 3.4. Wind

- `wind` reads the source's gust and the time it was measured — what 12d must provide (Open below).
- A gust value older than `sourceLostAfterMs`, or the source not reachable (12a §4.2, `reachable: false` roles), is **source lost**.
- Level changes act as §1.2. Level 1 on rise: `goTo({ tilt: 0 })` when lift > 0 and tilt > 0. Level 2 on rise: `up`, merged into any run.
- `restore` keeps the targets from before the first level rose, and goes back to them when the last one drops.
- Without a `wind` role, `wind` is `{ level: 0, acting: 0, source: 'none' }`.

**Open:** the almanac's wind DeviceType — a gust in m/s with the time it applies to. Deferred to M3.4 (12d), which designs the almanac's devices. A hardware anemometer template for the same role follows it.

### 3.5. State

Saved through `ctx.state` (12a §3): `{ lift, tilt, moving, movesSinceReference, restore? }`.

| Saved | After start |
|---|---|
| nothing | `current` absent, targets 0 |
| `moving: false` | `current` and targets as saved |
| `moving: true` | `current` absent — the save may be up to 5 s old and the motor ran on |

Both relays are written off before anything else. Wind levels start at 0 and follow the first gust; a source silent for `sourceLostAfterMs` after start is lost.

### 3.6. `cover-from-klf`

A VELUX io-homecontrol roller shutter, awning or blind behind a VELUX KLF 150 — the drive of `closure-from-klf` (12c-07 §3.1). Usually created with its window by the bundle `velux-klf` (12c-07 §3.2).

| Setting | Default | Note |
|---|---|---|
| `upMs`, `downMs` | required | full travel, measured |
| `startDelayMs`, `pulseMs`, `holdMinMs`, `feedbackMarginMs` | 2000, 500, 1600, 5000 | as 12c-07 §3.1 |
| `referenceAfterMoves` | 20 | as §3.1 |
| `endProductType` | `rollerShutter` | |
| wind settings | as §3.1 | `protection`, `level1`, `level2`, `hysteresisPct`, `releaseAfterMs`, `sourceLostAfterMs`, `onSourceLost`, `onRelease` |

- **No tilt.** The KLF input pair moves one axis; `tilt` is unbound.
- **Drive:** `up`/`down` and a `goTo` to an end pulse that relay for `pulseMs` — the product runs to its own end, no overrun. A middle `goTo` holds the relay `startDelayMs` + `liftMs × |Δ| / 10000`, `liftMs` = `upMs` or `downMs`; one needing less than `holdMinMs` is skipped. `stop` is both relays for `pulseMs`. A reversal is `stop`, then the new command.
- **Feedback:** a pulse in time after an end command sets `current` to that end exactly — a reference; none ⇒ `current` absent. Middle moves count toward `referenceAfterMoves` as in §3.2.
- **Wind** as §1.2 and §3.4; level 2's `up` is one pulse.
- **Interlock** in the bundle: 12c-07 §3.2.
- A relay changed elsewhere ⇒ `current` absent until the next confirmed end — both relays on is the KLF's stop, not a fault (unlike §3.3).
- **State** as §3.5.

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). Device type Window Covering `0x0202`; features `LF`, `PA_LF`, and `TL`, `PA_TL` when `tilt` is bound (research/matter/06 §1).

| Matter | Home |
|---|---|
| `CurrentPositionLiftPercent100ths` | `lift.current`; null when absent |
| `TargetPositionLiftPercent100ths` | `lift.target` |
| `CurrentPositionLiftPercentage` | `⌊lift.current / 100⌋` |
| `…Tilt…` | the same from `tilt` |
| `OperationalStatus` | `Lift`, `Tilt` from `motion` (opening 1, closing 2); `Global` = `Lift` while it moves, else `Tilt` |
| `ConfigStatus` | `Operational` 1; `LiftPositionAware` 1; `TiltPositionAware` = tilt bound; encoder bits 0 — timer controlled |
| `Type` · `EndProductType` | from `behavior.endProductType`: `exteriorVenetianBlind` 8 · 13, `interiorVenetianBlind` 8 · 12, `rollerShutter` 6 · 17, `rollerShade` 0 · 0, `awning` 5 · 19 |
| `SafetyStatus` | `Protection` while `wind.acting` > 0; `FailedCommunication` while `wind.source` = `lost` |
| `UpOrOpen`, `DownOrClose`, `StopMotion` | `up`, `down`, `stop` |
| `GoToLiftPercentage`, `GoToTiltPercentage` | `goTo({ lift: v })`, `goTo({ tilt: v })` — merged into a running move (§1.1) |
| `Mode` | 0. A write of `CalibrationMode` → `reference({ end: 'up' })`; any other bit refused, `CONSTRAINT_ERROR` |
| `domain-error` `protected`, `interlock` | Matter `BUSY` |

- `NumberOfActuations…` are not exposed.
- `matter` origin (12a §4a): an endpoint of `0x0202` maps to `WindowCovering`; its own `SafetyStatus` is not mapped, and `wind` is `{ level: 0, acting: 0, source: 'none' }`. Without `PA_LF`, `current` is absent.

## 5. Moving and target

| Field | Reports |
|---|---|
| `target` | at once, on every call (12a §4a) |
| `current` | once a second while a run is on, and at every stop |
| `motion` | at every start and stop |

16a reports `CurrentPosition…` at most once a second.
