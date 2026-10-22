# 12c-01 — Lights

## 1. Scope

Four home `DeviceType`s for luminaires, each a superset of the one before — the same chain as Matter's (research/matter/01 §1):

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `OnOffLight` | on/off, timed on | On/Off Light `0x0100` |
| `DimmableLight` | level | Dimmable Light `0x0101` |
| `ColorTemperatureLight` | colour temperature | Color Temperature Light `0x010C` |
| `ExtendedColorLight` | full colour (CIE xy) | Extended Color Light `0x010D` |

**For:** a light a user switches, dims or colours — one luminaire, or several drivers that together are one (12a §3).

**Not for:**

- A load that isn't a light — a socket, a pump: `OnOffPlugInUnit`.
- Scenes and effects. Matter's `OffWithEffect` is a plain off; scenes, groups and colour loop are not home features. 16a holds what Matter needs of them.
- Warm dimming (Matter `CoupleColorTempToLevel`).

### 1.1. Behaviour every light shares

It follows Matter's On/Off and Level Control clusters (research/matter/01 §2–§3):

| Action | Effect |
|---|---|
| `onOff` SET `false` | off; `level`, `colorTemp` and `color` keep their values |
| `onOff` SET `true` | on, at `onLevel` when set, else at the last `level` |
| `level` SET, `moveToLevel` | to that level; switches the light on when it is off |
| `onFor({ seconds })` | on now, off after `seconds`. Any later `onOff` SET or `onFor` replaces it |
| daemon start | the template applies `startUp` (§3.1) |

- **No level 0.** `level` is 1–254, as in Matter and DALI; off is `onOff`.
- **Fades.** A plain SET uses the template's default fade. `moveToLevel`, `moveToColorTemp` and `moveToColor` take an optional `transitionMs`, as Matter's commands do: absent ⇒ the default fade, `0` ⇒ as fast as the source can.
- **Down to 1, never off.** `move` down and `moveToLevel(1)` stop at level 1; only `onOff` switches off — as DALI's `DOWN` (12 §9.3).
- **`stop`** stops every movement of the light: level and colour.
- **Timed on.** `onFor` is Matter's `OnWithTimedOff`, the timed relay built into every Matter light. A timed on is not persistent: after a restart the light comes up as if it had been off (§3.1). A separate timer for other uses is `TimerRelay`.

## 2. Fields

```ts
// @evok-node/driver-home
const Level      = Codecs.uint8({ min: 1, max: 254 });
const Mired      = Codecs.uint16({ min: 1, max: 65279, unit: 'mired' });   // 1 000 000 / K
const Xy         = Codecs.struct({ x: Codecs.float32({ min: 0, max: 1 }), y: Codecs.float32({ min: 0, max: 1 }) });   // CIE 1931
const Transition = Codecs.optional(Codecs.uint32({ unit: 'ms' }));          // absent ⇒ the default fade

const Behavior = Codecs.struct({            // settings a consumer must see (12a §2.3) — 16a reports them as Matter attributes
  onLevel:          Codecs.optional(Level),      // absent ⇒ the last level
  startUp:          Codecs.string({ enumValues: ['off', 'on', 'toggle', 'previous'] }),
  startUpLevel:     Codecs.optional(Level),      // absent ⇒ the last level
  startUpColorTemp: Codecs.optional(Mired),      // colour lights; absent ⇒ the last one
  transitionMs:     Codecs.uint32(),             // the default fade
  onTransitionMs:   Codecs.optional(Codecs.uint32()),   // absent ⇒ transitionMs
  offTransitionMs:  Codecs.optional(Codecs.uint32()),
  moveRate:         Codecs.uint8({ min: 1, unit: 'level/s' }),
});

const LightFields = {                       // every light
  onOff:          channel(Codecs.bool(), { subscribe: true }),
  onFor:          method('mutates', Codecs.void, Codecs.struct({
                    seconds:    Codecs.uint32({ min: 1 }),
                    onlyWhenOn: Codecs.bool({ default: false }) })),   // Matter AcceptOnlyWhenOn: ignored while off
  onForRemaining: reading(Codecs.uint32({ unit: 's' }), { subscribe: true }),   // 0 ⇒ not timed; emits once a second while running
  behavior:       reading(Behavior, { subscribe: true }),
};

const LevelFields = {                       // dimmable and up
  level:       channel(Level, { subscribe: true }),
  moveToLevel: method('mutates', Codecs.void, Codecs.struct({ level: Level, transitionMs: Transition })),
  move:        method('mutates', Codecs.void, Codecs.struct({
                 direction: Codecs.string({ enumValues: ['up', 'down'] }),
                 rate:      Codecs.optional(Codecs.uint8({ min: 1, unit: 'level/s' })) })),   // absent ⇒ behavior.moveRate
  stop:        method('mutates', Codecs.void),
};

const ColorTempFields = {                   // colour temperature and up
  colorTemp:       channel(Mired, { subscribe: true }),
  colorTempRange:  reading(Codecs.struct({ min: Mired, max: Mired })),   // min = coolest
  moveToColorTemp: method('mutates', Codecs.void, Codecs.struct({ mireds: Mired, transitionMs: Transition })),
  moveColorTemp:   method('mutates', Codecs.void, Codecs.struct({
                     direction: Codecs.string({ enumValues: ['warmer', 'cooler'] }),
                     rate:      Codecs.optional(Codecs.uint16({ min: 1, unit: 'mired/s' })) })),
};

const ColorFields = {                       // extended colour
  color:       channel(Xy, { subscribe: true }),
  colorMode:   reading(Codecs.string({ enumValues: ['colorTemp', 'xy'] }), { subscribe: true }),   // which one the light shows now
  moveToColor: method('mutates', Codecs.void, Codecs.struct({ color: Xy, transitionMs: Transition })),
};

export const OnOffLight            = device('home.OnOffLight',            { ...CommonFields, ...LightFields });
export const DimmableLight         = device('home.DimmableLight',         { ...CommonFields, ...LightFields, ...LevelFields });
export const ColorTemperatureLight = device('home.ColorTemperatureLight', { ...CommonFields, ...LightFields, ...LevelFields, ...ColorTempFields });
export const ExtendedColorLight    = device('home.ExtendedColorLight',    { ...CommonFields, ...LightFields, ...LevelFields, ...ColorTempFields, ...ColorFields });
```

`colorTemp` and `color` are both kept: a SET on one makes `colorMode` follow it, and the other keeps its last value.

`identify` (12a §2.1) is bound by every light template: the light blinks itself — no `indicator` role.

## 3. Templates

| DeviceType | Template | Roles |
|---|---|---|
| `OnOffLight` | `onoff-from-output` (§3.2) | `outputs`: `unipi.ro` \| `unipi.do`, 1–8 |
| `OnOffLight` | `onoff-from-dali` (§3.3) | `gear`: `dali.gear` \| `dali.group`, 1 |
| `DimmableLight` | `dimmable-from-dali` (§3.4) | `gear`: `dali.gear` \| `dali.group`, 1 |
| `DimmableLight` | `dimmable-from-ao` (§3.5) | `output`: `unipi.ao`, 1 · `power`: `unipi.ro` \| `unipi.do`, 0–1 |
| `ColorTemperatureLight` | `tunable-white-2dali` (§3.6) | `warm`, `cold`: `dali.gear` \| `dali.group`, 1 each |
| `ExtendedColorLight` | `tunable-rgbw-4dali` (§3.7) | `red`, `green`, `blue`: `dali.gear` \| `dali.group`, 1 each · `white`: same, 0–1 |

### 3.1. Rules every light template follows

- **Settings → `behavior`.** A template fills `behavior` from its settings, and only `manage` changes them (12a §2.3). A setting a source can't honour is not in that template's form — DALI has one fade, so its templates have no `onTransitionMs`.
- **`startUp`** is stored in the device record's settings. At daemon start the template applies it to its sources: `off`, `on` (at `startUpLevel`, else the last level), `toggle` (the opposite of the last state), `previous`. A DALI template also mirrors it into the gear (`powerOnLevel`, `systemFailureLevel`, 12 §9.1), so the gear does the same after its own power loss; DALI has no `toggle`, so DALI templates don't offer it.
- **Its own echoes.** A source value equal to what the template just wrote is its own echo: no re-derivation, no emit. Any other source change — a wall switch, another DALI master — is re-derived into the device's fields and emitted.
- **Ramps** — a fade the source can't do itself — run on `scheduleRepeating` (04 §5.2, `'skip'`), cancelled by `stop` or any later write.
- **Identify** blinks: on/off once a second for `seconds`, then back to the state before.

### 3.2. `onoff-from-output`

One light on one or more relays or digital outputs — a chandelier on two circuits.

| Setting | Default |
|---|---|
| `startUp` | `previous` |

- `onOff` is `true` when every output is on. A SET writes every output; if one throws `SourceUnreachable`, the answer is `unreachable`, nothing rolled back (12a §3).
- A `unipi.do` in `pwm` mode marks the device stale (12a §4.2) until it is back in `bool` mode.
- `onFor` switches on and starts a one-shot timer on the `Clock`.
- `behavior`: `transitionMs: 0`, `moveRate: 1` — fixed, not settings.

### 3.3. `onoff-from-dali`

A DALI load that only switches — a non-dimmable driver, a DALI relay.

| Setting | Default |
|---|---|
| `onLevel` | 254 |
| `startUp` | `previous` |

- On → gear `@` SET `{ intensity: onLevel }`; off → `{ intensity: 0 }`. The gear's own `fadeTime` applies.
- `onOff` is `intensity > 0`.

### 3.4. `dimmable-from-dali`

| Setting | Default | Note |
|---|---|---|
| `fadeTime` | 2 (1.0 s) | DALI fade code 0–15, labelled in seconds; written to the gear (12 §9.1) — the default fade |
| `fadeRate` | 7 (44.7 steps/s) | DALI fade-rate code 1–15; written to the gear — the default `move` rate |
| `onLevel` | absent | |
| `startUp`, `startUpLevel` | `previous`, absent | |

Workflow:

| Action | To the gear |
|---|---|
| `level` SET n | `@` SET `{ intensity: n }` |
| `onOff` SET false / true | `{ intensity: 0 }` / `{ intensity: onLevel ?? last level }` |
| `moveToLevel`, `transitionMs` absent | as `level` SET |
| `moveToLevel`, `transitionMs: 0` | `{ intensity: n, instant: true }` (12 §9.2) |
| `moveToLevel`, other `transitionMs` | a ramp of `instant` writes every 200 ms, the arc level interpolated linearly — DALI's curve makes that look even |
| `move`, `rate` absent / given | gear `up()`/`down()` (12 §9.3) / a ramp at `rate` |
| `stop` | gear `stop()`, ramp cancelled |
| gear `intensity` changes elsewhere | `0` → `onOff` false, `level` kept; n → `onOff` true, `level` n |

`behavior.transitionMs` and `moveRate` are the times of `fadeTime` and `fadeRate`.

### 3.5. `dimmable-from-ao`

A 0–10 V or 1–10 V ballast on an analog output, with an optional relay for its mains — a 1–10 V ballast cannot switch off from the signal.

| Setting | Default |
|---|---|
| `minVolts`, `maxVolts` | 1.0, 10.0 |
| `curve` | `log` — `log` \| `linear`: level → light |
| `transitionMs`, `onTransitionMs`, `offTransitionMs` | 500, absent, absent |
| `moveRate` | 50 |
| `onLevel`, `startUp`, `startUpLevel` | absent, `previous`, absent |

- Level → light fraction by `curve` (`log`: DALI's curve, 1 = 0.1 %, 254 = 100 %), light → volts linear between `minVolts` and `maxVolts`.
- Every fade is a ramp, 100 ms ticks.
- On: `power` on, then a ramp from `minVolts` up. Off: a ramp down to `minVolts`, then `power` off. Without `power`, off is 0 V — whether the ballast then goes dark is the installer's to know.
- The AO must be in `voltage10` mode; any other marks the device stale.
- An AO value changed elsewhere is mapped back through `curve`, clamped to 1–254.

### 3.6. `tunable-white-2dali`

A tunable-white strip on two DALI DT6 channels, warm and cold (research/matter/01 §6).

| Setting | Default | Note |
|---|---|---|
| `warmMired`, `coldMired` | 370 (2700 K), 154 (6500 K) | the strip's datasheet; `colorTempRange` = `{ min: coldMired, max: warmMired }` |
| `curve` | `log` | the gears' dimming curve; `log` is DALI's standard. Tells the template, never sets the gears |
| `fadeTime`, `fadeRate` | as §3.4 | written to both gears |
| `colorMoveRate` | 50 mired/s | default for `moveColorTemp` |
| `onLevel`, `startUp`, `startUpLevel`, `startUpColorTemp` | absent, `previous`, absent, absent | |

**Mixing** — in linear light, so brightness stays constant across colour temperature:

```
L = curve(level)                                   // linear light, 0.001 … 1
r = (mired − coldMired) / (warmMired − coldMired)  // warm share, 0 … 1
warm = arc(L · r),  cold = arc(L · (1 − r))        // arc = curve⁻¹; below arc 1 ⇒ that gear off
```

| `level` | colour | warm | cold |
|---|---|---|---|
| 200 (22.9 %) | middle | 175 | 175 |
| 200 | 70 % warm | 187 | 156 |
| 254 | middle | 229 | 229 |

The pair's maximum is one channel at full, at every colour temperature — a mixed white never reaches both channels' combined output.

- Both gears are written together, with the same fade, so they arrive together.
- Back from the gears (changed elsewhere): `L = light(warm) + light(cold)`, `level = curve⁻¹(min(L, 1))`, `mired = coldMired + (warmMired − coldMired) · light(warm) / L`.
- Colour fades and `moveColorTemp` are ramps of `instant` writes every 200 ms.

### 3.7. `tunable-rgbw-4dali`

An RGB or RGBW strip on three or four DALI DT6 channels.

| Setting | Default | Note |
|---|---|---|
| `primaries` | none — required | per channel `{ x, y, flux }`: chromaticity and relative luminous flux at full, from the strip's datasheet |
| `colorTempRange` | 153–500 mired | narrowed to what the gamut holds |
| `curve`, `fadeTime`, `fadeRate`, `colorMoveRate` | as §3.6 | |
| `onLevel`, `startUp`, `startUpLevel`, `startUpColorTemp` | as §3.6 | |

- `color` → channel shares: the mix of `primaries` that gives that xy; with `white`, white takes the largest share the mix allows. A colour temperature is first turned into its xy on the Planckian locus, then mixed the same way.
- xy outside the gamut → the nearest point on its edge; `color` reports the point applied.
- **Brightness:** `level` 254 is the brightest the strip can make *that* colour. Unlike §3.6 it is not constant across colours — a constant rule would cap every colour at the dimmest one (blue).
- Back from the gears: the shares give xy and `level`; `colorMode` becomes `xy`.

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). Values per research/matter/01. Fixed: `MinLevel` 1, `MaxLevel` 254, `ColorCapabilities` = the features below.

| Matter | Home |
|---|---|
| On/Off `OnOff` | `onOff` |
| `On`, `Off`, `Toggle` | `onOff` SET |
| `OffWithEffect` | `onOff` SET false — the effect is ignored |
| `OnWithRecallGlobalScene` | `onOff` SET true; `GlobalSceneControl` always true |
| `OnWithTimedOff` | `onFor({ seconds: ⌈OnTime / 10⌉, onlyWhenOn: AcceptOnlyWhenOn })`; `OffWaitTime` ignored, reported 0 |
| `OnTime` | `onForRemaining × 10` |
| `StartUpOnOff` | `behavior.startUp` (`previous` = null) |
| Level `CurrentLevel` | `level` |
| `MoveToLevel(WithOnOff)` | `TransitionTime` null → `level` SET; else `moveToLevel({ transitionMs: TransitionTime × 100 })` |
| `MoveToLevelWithOnOff` to `MinLevel` | `moveToLevel(1)`, then `onOff` false |
| `Move(WithOnOff)` | `move({ direction, rate: Rate ?? absent })` |
| `Step(WithOnOff)` | `moveToLevel(level ± StepSize)` |
| `Stop(WithOnOff)` | `stop` |
| `OnLevel`, `OnOffTransitionTime`, `On/OffTransitionTime`, `DefaultMoveRate`, `StartUpCurrentLevel` | `behavior` (`× 100` ms ↔ 1/10 s) |
| `RemainingTime` | 0 — home reports the target at once (§5) |
| `Options` | 0 — no `ExecuteIfOff` |
| Color `ColorTemperatureMireds` | `colorTemp` |
| `ColorTempPhysicalMin/MaxMireds`, `CoupleColorTempToLevelMinMireds` | `colorTempRange.min`/`max`, `.min` |
| `MoveToColorTemperature`, `StepColorTemperature` | `moveToColorTemp` |
| `MoveColorTemperature` | `moveColorTemp` (up = warmer) |
| `StopMoveStep` | `stop` |
| `StartUpColorTemperatureMireds` | `behavior.startUpColorTemp` |
| `CurrentX`, `CurrentY` | `color.x`, `color.y` × 65536 |
| `MoveToColor`, `StepColor` | `moveToColor` |
| `MoveColor` | 16a steps `moveToColor` once a second — translation state only |
| `ColorMode`, `EnhancedColorMode` | `colorMode`; always `colorTemp` on a `ColorTemperatureLight` |

- Writes to the attributes backed by `behavior` are refused by 16a: settings change through `manage` only (12a §2.3).
- `ExtendedColorLight` exposes XY and CT, Matter's mandatory features — no HS.
- Matter `TransitionTime` on `MoveToColor…` is not nullable: 0 there means instant, never the default fade.

## 5. Moving and target

| Action | What `level`, `colorTemp`, `color` report |
|---|---|
| any SET, `moveTo…`, `onOff` | the target at once, whatever the fade (12a §4a) |
| `move`, `moveColorTemp` | each step as it happens; 16a reports at most once a second |
| a source changed elsewhere, fading on its own | each value the source reports |
| `onFor` | `onOff` true at once; `onForRemaining` counts down |

## 6. Open

- **Template state.** `startUp: previous`, `toggle` and "the last level" need the last state across a restart. A DALI gear keeps its own (`powerOnLevel` 255); a relay or an AO does not. Proposal: `AssemblyContext` gets an opaque persisted state, as 12b §5.5, saved at most every few seconds. Needs a 12a §3 change.
- **`startUp` with a `dali.group` source.** A `DaliGroup` has no `powerOnLevel` (12 §9.4), so it can't be mirrored.
- **HS for Apple Home.** Which colour commands Apple sends is unknown (research/matter/01 §7). If it needs HS, 16a converts HS ↔ xy.
