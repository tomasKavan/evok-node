# 12c-02 — Plug-in units

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `OnOffPlugInUnit` | on/off, timed on | On/Off Plug-in Unit `0x010A` |

**For:** a switched load that isn't a light — a socket, a heater, a small pump.

**Not for:**

- A light on a relay: `OnOffLight` (12c-01). Ecosystems treat the two differently — "lights off" never cuts a plug (research/matter/02 §4).
- Equipment that a fast on/off cycle damages — a compressor, a heat-pump, a pump with a minimum off time. It needs a device of its own.
- Energy metering. No built-in source measures a relay's power, so there is no field for it (research/matter/02 §3).
- Dimmable loads.
- A fan: `Fan` (12c-12), so controllers show it as one.

### 1.1. Behaviour

The on/off part of a light (12c-01 §1.1), nothing more:

| Action | Effect |
|---|---|
| `onOff` SET | on or off |
| `onFor({ seconds })` | on now, off after `seconds`. Any later `onOff` SET or `onFor` replaces it |
| daemon start | the template restores the state and applies `startUp` (§3) |

- **Timed on** is Matter's `OnWithTimedOff`, as on a light. Not persistent: a timed on is saved as off.
- **Identify never switches the load.** Blinking a heater or a pump is unsafe. `identify` is bound only through an `indicator` role (12a §3).

## 2. Fields

```ts
// @evok-node/driver-home
const PlugBehavior = Codecs.struct({        // settings a consumer must see (12a §2.3)
  startUp: Codecs.string({ enumValues: ['off', 'on', 'toggle', 'previous'] }),
});

export const OnOffPlugInUnit = device('home.OnOffPlugInUnit', {
  ...CommonFields,
  ...OnOffFields,                           // onOff, onFor, onForRemaining — 12c-01 §2
  behavior: reading(PlugBehavior, { subscribe: true }),
});
```

## 3. Templates

| Template | Roles |
|---|---|
| `plug-from-output` | `outputs`: `unipi.ro` \| `unipi.do`, 1–8 · `indicator`: `unipi.led` \| `unipi.do`, 0–1 |

One load on one or more relays or digital outputs.

| Setting | Default |
|---|---|
| `startUp` | `previous` |

- **State** (12a §3): saves `{ onOff }` through `ctx.state`; a timed `onFor` is saved as off.
- **Daemon start:** applies `startUp` from the saved state — `off`, `on`, `toggle` (the opposite of the saved state), `previous`. No saved state ⇒ off.
- `onOff` is `true` when every output is on. A SET writes every output; if one throws `SourceUnreachable`, the answer is `unreachable`, nothing rolled back (12a §3).
- A `unipi.do` in `pwm` mode marks the device stale (12a §4.2) until it is back in `bool` mode.
- `onFor` switches on and starts a one-shot timer on the `Clock`.
- **Its own echoes** are ignored; an output changed elsewhere is re-derived and emitted — as 12c-01 §3.1.
- **Identify** with an `indicator`: the indicator blinks once a second for `seconds`, then goes back to its state before. Without one, `identify` is unbound.

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). The On/Off cluster maps as on a light (12c-01 §4):

| Matter | Home |
|---|---|
| On/Off `OnOff` | `onOff` |
| `On`, `Off`, `Toggle` | `onOff` SET |
| `OffWithEffect` | `onOff` SET false — the effect is ignored |
| `OnWithRecallGlobalScene` | `onOff` SET true; `GlobalSceneControl` always true |
| `OnWithTimedOff` | `onFor({ seconds: ⌈OnTime / 10⌉, onlyWhenOn: AcceptOnlyWhenOn })`; `OffWaitTime` ignored, reported 0 |
| `OnTime` | `onForRemaining × 10` |
| `StartUpOnOff` | `behavior.startUp` (`previous` = null); writes refused — `manage` only |
| Identify | `identify` when bound; unbound ⇒ 16a counts `IdentifyTime` down with no effect — Identify is on every endpoint (16a) |

- No Level Control — optional on this device type.
- **Device type: `0x010A` only.** Matter 1.4's Mounted On/Off Control `0x010F` fits a DIN-rail relay better, but controllers don't support it yet (research/matter/02 §4).
- `matter` origin (12a §4a): an endpoint of `0x010A` or `0x010F` maps to `OnOffPlugInUnit`. Dimmable plug-in units are not imported.

## 5. Moving and target

Nothing moves. `onOff` reports the target at once (12a §4a); during `onFor`, `onForRemaining` counts down.
