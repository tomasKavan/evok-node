# 12c-03 — Generic switch

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `GenericSwitch` | press events of a momentary push button | Generic Switch `0x000F` |

**For:** a push button a user presses — a wall button on a digital input, a Matter remote. It only reports presses; a rule (12b) or a Matter controller decides what they do.

**Not for:**

- A latching switch — a rocker, a rotary switch that stays where it is put. Not supported; a Matter endpoint with the latching feature is of unknown type (12a §4a).
- A digital input that reports a state, not a press — a door contact: `ContactSensor`.
- Switching a load directly. A button wired to an output by DirectSwitch (research/02 §4.7) is still read as a button here; the coupling is the hardware's.

### 1.1. Behaviour

Events and their order are Matter's Switch cluster (research/matter/03 §3). `features` (§2) says which of them a switch produces:

| Gesture | Events, multi-press off | Events, multi-press on |
|---|---|---|
| short press | `initialPress` · `shortRelease` | `initialPress` · `shortRelease` · *window* · `multiPressComplete(1)` |
| long press | `initialPress` · `longPress` · `longRelease` | same — a long press ends the sequence, no `multiPressComplete` |
| double press | two short presses | `initialPress` · `shortRelease` · `initialPress` · `multiPressOngoing(2)` · `shortRelease` · *window* · `multiPressComplete(2)` |
| more presses than `multiPressMax` | — | `initialPress` · `shortRelease` per press; `multiPressOngoing` only up to the max; `multiPressComplete(0)` |

- A long press is detected only as the first press of a sequence; held later in a multi-press, it counts as a press.
- With multi-press on, a single press is known to be single only after the window — a consumer that needs it fast reacts to `initialPress` or `shortRelease` instead (12b §2.1).
- A switch with multi-press and no release (Matter `ActionSwitch`, from a `matter` origin) sends one `initialPress` per sequence, then `multiPressComplete(n)`; a long press still sends `longPress` · `longRelease`.

## 2. Fields

```ts
// @evok-node/driver-home
const SwitchEvent = Codecs.struct({
  type:     Codecs.string({ enumValues: ['initialPress', 'shortRelease', 'longPress', 'longRelease',
                                         'multiPressOngoing', 'multiPressComplete'] }),
  position: Codecs.uint8(),       // the position pressed (Matter NewPosition) or released (PreviousPosition)
  count:    Codecs.uint8(),       // multiPressOngoing: presses so far · multiPressComplete: the total, 0 = over multiPressMax · else 0
  seq:      Codecs.uint32(),      // +1 per event — two identical presses are two values, never one
  at:       Codecs.timestamp(),
});

const SwitchFeatures = Codecs.struct({        // what the switch produces — 16a builds the Matter FeatureMap from it
  numberOfPositions: Codecs.uint8({ min: 2 }),               // 0 = released; 2 for a plain button
  release:           Codecs.bool(),                          // shortRelease
  longPress:         Codecs.bool(),                          // longPress, longRelease
  multiPress:        Codecs.bool(),                          // multiPressOngoing, multiPressComplete
  multiPressMax:     Codecs.optional(Codecs.uint8({ min: 2 })),   // present when multiPress
});

export const GenericSwitch = device('home.GenericSwitch', {
  ...CommonFields,
  switch:   reading(Codecs.struct({ position: Codecs.uint8(), lastEvent: SwitchEvent }), { subscribe: true }),
  features: reading(SwitchFeatures, { subscribe: true }),
});
```

- `switch.position` is the position now: 0 after any release. Position and event are one value, so a consumer never sees one without the other.
- `lastEvent` carries every event as a consecutive value. A gap in `seq` means a subscription coalesced events away (03 §6.3).
- `features` is the template's settings (§3) for a `local` switch, the device's own Switch cluster for a `matter` one. Timings are settings only — no consumer needs them (§4).
- No `SET`: every field is a reading.

## 3. Templates

| Template | Roles |
|---|---|
| `switch-from-di` | `input`: `unipi.di`, 1 · `indicator`: `unipi.led` \| `unipi.do`, 0–1 |

One push button on one digital input.

| Setting | Default | Note |
|---|---|---|
| `invert` | `false` | `true` for a normally closed button |
| `longPress` | `true` | |
| `longPressMs` | 800 | |
| `multiPress` | `false` | off: single presses come without the window delay |
| `multiPressWindowMs` | 400 | time after a release in which a next press continues the sequence |
| `multiPressMax` | 2 | |

`features`: `numberOfPositions` 2, `release` true, the rest from the settings.

Workflow — on each `input` value (`{ value, counter }`, 07a §10.1), `pressed = value XOR invert`, every time is the value's `readAt`:

| Input | Does |
|---|---|
| first value after start or after the source was unreachable | sets `position`, remembers `counter`; no event |
| `pressed` false → true | `position` 1; `initialPress`. First press of a sequence: starts the long-press timer. Later press: `count` +1, `multiPressOngoing(count)` while `count ≤ multiPressMax` |
| long-press timer fires, still pressed | `longPress`; the sequence ends |
| `pressed` true → false | `position` 0; `longRelease` after a long press, else `shortRelease`. Multi-press on and the sequence still open: starts the window timer |
| window timer fires | `multiPressComplete(count)`, or `(0)` if `count` went over `multiPressMax` |
| `counter` rose by more than the rising edges seen since its last value | each missed press is replayed at once as a short one: `position` 1, `initialPress` (`multiPressOngoing`), `position` 0, `shortRelease` — before the edge seen in the same poll |
| source unreachable | an open sequence is dropped without further events |

- Timers run on the `Clock` (04 §4), measured from `readAt`.
- **Timing is the poll's.** An edge is seen at the next poll — `fast`: 100 ms onboard (08 §8), 200 ms on an extension (09 §4). Every threshold is accurate to one poll period, and a press shorter than one poll is seen only through the counter, as a short press. Keep `longPressMs` and `multiPressWindowMs` about ten times the poll period. The user documentation states it.
- `counter` wraps at 2³² (research/02 §4.9); the delta is taken modulo 2³².
- No state is saved (12a §3): after a restart the switch starts released or pressed as the input reads, with no event.
- The DI's own `debounce` is the source's, left as it is.
- **Identify** with an `indicator`: it blinks once a second for `seconds`, then goes back to its state before. Without one, `identify` is unbound.

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`).

| Matter | Home |
|---|---|
| FeatureMap | `MS` always · `MSR` = `release` · `MSL` = `longPress` · `MSM` = `multiPress` · `AS` = `multiPress && !release` |
| `NumberOfPositions` | `features.numberOfPositions` |
| `CurrentPosition` | `switch.position` |
| `MultiPressMax` | `features.multiPressMax` |
| `InitialPress(NewPosition)`, `LongPress(NewPosition)` | `lastEvent` `initialPress`, `longPress`; `position` = NewPosition |
| `ShortRelease(PreviousPosition)`, `LongRelease(PreviousPosition)` | `shortRelease`, `longRelease`; `position` = PreviousPosition |
| `MultiPressOngoing(NewPosition, CurrentNumberOfPressesCounted)` | `multiPressOngoing`; `count` |
| `MultiPressComplete(PreviousPosition, TotalNumberOfPressesCounted)` | `multiPressComplete`; `count` |

- **16a emits the events from `lastEvent`**, one Matter event per value, through its own `SwitchBehavior.with(…)` (16a) — never matter.js's `SwitchServer` press detection, which would decide gestures a second time with its own timings (research/matter/03 §5). The template is the one place a gesture is decided, for rules and Matter controllers alike. A gap in `seq` is not filled in.
- **`matter` origin** (12a §4a): an endpoint with Switch `MS` maps to `GenericSwitch`; `LS` is of unknown type. FeatureMap → `features`, events → `lastEvent` as above, `seq` counted here, `at` from the event's timestamp.
- **Tags** (12a §2.1): `position` → Common Position, `index` → Common Number, on each endpoint of a multi-button device (research/matter/03 §7).
- Apple Home: momentary only; offers double press only with `MSM` (research/matter/03 §6).

## 5. Moving and target

Nothing moves, and nothing is written: every field is a reading, reported as the source reports it.
