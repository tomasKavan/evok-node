# 12c-07 — Closures

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `Closure` | open / close / stop, optional % position, interlock and gating state | Closure `0x0230`, tags from `kind`; Closure Panel `0x0231` child for the %; access kinds not exposed for now (§4) |

**For:** a motorised opening a person or a rule opens and closes — a roof or facade window, a garage door, a gate, a door. One type for all of them; `kind` tells them apart, as Matter's tags do (research/matter/10 §3).

**Not for:**

- A cover in front of a window: `WindowCovering` (12c-06). Apple supports Window Covering, not (as found) Closure; a window exported as a cover would open on "open all blinds" (research/matter/10 §3).
- Locking. A lock is a `DoorLock` (12c-09). Who may open an access closure, and whether a lock gates it (`blocked.open: 'locked'`), is M3.6 (§6); no template sets `locked` yet.

### 1.1. Behaviour

Positions are Matter's, as in 12c-06: **0.01 % closed**, `0` = fully open, `10000` = fully closed.

| Action | Effect |
|---|---|
| `open`, `close` | to that end |
| `goTo({ position })` | to a % — only with `positioning: 'percent'` |
| `stop` | stops; never refused |
| `confirm` | asks the device to prove it is closed (§3.1); `state` and `confirmed` follow |
| a call while moving | replaces the running target |

- **`state` is always there**: `closed`, `open`, `partial`, `unknown`. `current` is the % when the template knows it; a door with end contacts only has `state` without `current`.
- **`confirmed`** is when the device last proved `state` — an end contact, a feedback pulse. A state the template only computed has an older `confirmed`, or none.
- **Refused, never sequenced.** A move `blocked` forbids answers `domain-error` with the reason, and nothing moves. A rule (12b) or a person decides what to do first.
- **Opening is what gets blocked.** `blocked.close` exists for an interlock that forbids closing; no built-in template sets it.

## 2. Fields

```ts
// @evok-node/driver-home
const Closed = Codecs.uint16({ max: 10000, unit: '0.01%' });     // 0 = fully open, 10000 = fully closed (12c-06 §2)

const ClosurePosition = Codecs.struct({
  state:     Codecs.string({ enumValues: ['closed', 'open', 'partial', 'unknown'] }),
  current:   Codecs.optional(Closed),       // absent ⇒ not known as a %
  target:    Codecs.optional(Closed),       // absent ⇒ no target (stopped, or after a restart)
  motion:    Codecs.string({ enumValues: ['stopped', 'opening', 'closing'] }),
  confirmed: Codecs.optional(Codecs.timestamp()),
});

const Blocked = Codecs.struct({              // why a direction is refused now; absent ⇒ free
  open:  Codecs.optional(Codecs.string({ enumValues: ['interlock', 'locked'] })),
  close: Codecs.optional(Codecs.string({ enumValues: ['interlock'] })),
});

const ClosureBehavior = Codecs.struct({      // settings a consumer must see (12a §2.3) — 16a reports them
  kind:        Codecs.string({ enumValues: ['roofWindow', 'facadeWindow', 'garageDoor', 'gate', 'door'] }),
  positioning: Codecs.string({ enumValues: ['ends', 'percent'] }),
});

export const Closure = device('home.Closure', {
  ...CommonFields,
  position: reading(ClosurePosition, { subscribe: true }),
  blocked:  reading(Blocked, { subscribe: true }),
  fault:    reading(Codecs.optional(Codecs.string({ enumValues: ['notCarriedOut', 'travelTimeout', 'endContacts'] })), { subscribe: true }),
  behavior: reading(ClosureBehavior, { subscribe: true }),
  open:     method('mutates', Codecs.void, undefined, { errorKinds: ['interlock', 'locked'] }),
  close:    method('mutates', Codecs.void, undefined, { errorKinds: ['interlock'] }),
  stop:     method('mutates', Codecs.void),
  goTo:     optional(method('mutates', Codecs.void, Codecs.struct({ position: Closed }), { errorKinds: ['interlock', 'locked'] })),
  confirm:  optional(method('mutates', Codecs.void, undefined, { errorKinds: ['notCarriedOut'] })),
});
```

| `fault` | Means | Cleared by |
|---|---|---|
| `notCarriedOut` | a command got no confirmation in time (§3.1, §3.4) | the next confirmed end |
| `travelTimeout` | no end reached within the travel time — templates with end contacts | the next confirmed end |
| `endContacts` | both end contacts at once | the contacts disagreeing again |

- `goTo` is bound only with `positioning: 'percent'`; `confirm` only when the template has a way to prove "closed".
- `goTo` toward open is an opening: `blocked.open` refuses it.
- `identify` is unbound — moving a window or a door to identify it is unsafe.

## 3. Templates

| Template | Roles |
|---|---|
| `closure-from-klf` (§3.1) | `open`: `unipi.ro`, 1 · `close`: `unipi.ro`, 1 · `feedback`: `unipi.di`, 0–1 |
| `closure-from-uap` (§3.4) | `open`, `close`, `stop`: `unipi.ro` \| `unipi.do`, 1 each · `openEnd`, `closedEnd`: `unipi.di`, 1 each · `moving`: `unipi.di`, 0–1 |

The bundle `velux-klf` (§3.2) creates a window and its cover together, with their interlock.

### 3.1. `closure-from-klf`

A VELUX io-homecontrol window behind a VELUX KLF 150 (research/matter/10 §1). Relays close the KLF's input pair; its output, on a DI, pulses 2 s when a command has been carried out. Assumed as in research/matter/10 §1.3 — to be verified at commissioning (§3.3).

| Setting | Default | Note |
|---|---|---|
| `kind` | `roofWindow` | → `behavior` |
| `openMs`, `closeMs` | required | full travel, measured (GGU: 35 s) |
| `startDelayMs` | 2000 | KLF and radio lag before the motor runs |
| `pulseMs` | 500 | a press the KLF reads as short: < 1.5 s ⇒ run to the end |
| `holdMinMs` | 1600 | a press the KLF reads as long; a middle move needing less is skipped |
| `confirmFastMs` | 4000 | a pulse sooner than this after `confirm` ⇒ it was closed already |
| `feedbackMarginMs` | 5000 | added to travel when waiting for the pulse |

`positioning` is `percent`. `goTo` and `confirm` are bound; `confirm` only with `feedback`.

**Drive** (research/matter/10 §1.2):

| Action | Relays |
|---|---|
| `open`, `close` | that relay on for `pulseMs` — the window runs to its end |
| `goTo` a middle position | that relay held `startDelayMs` + travel share, then off — the window stops on release |
| `stop` | both relays on for `pulseMs` |

- Every write waits for the ack of the one before. A reversal is `stop`, then the new command.
- **Position by time**, from the on-write's ack plus `startDelayMs`, as 12c-06 §3.2. `current` emits once a second while moving.

**Feedback** — the DI's rising edge:

| After | Pulse within | Result |
|---|---|---|
| `open` / `close` | `startDelayMs` + travel + `feedbackMarginMs` | `current` = that end, `state` = end, `confirmed` = now, `fault` cleared |
| `open` / `close` | no pulse | `state` `unknown`, `current` absent, `fault` `notCarriedOut` — rain, entrapment, a fault |
| a middle `goTo` | — | no pulse expected; `confirmed` keeps its value |
| nothing of ours | any | ignored, logged — a move from elsewhere (research/matter/10 §2.3) |

**`confirm`** — "prove it is closed" (research/matter/10 P3a):

```
close pulse → wait for feedback
  pulse < confirmFastMs                      ⇒ it was closed: state closed, confirmed now
  pulse later, within the close travel       ⇒ it was open and has closed: state closed, confirmed now
  no pulse                                    ⇒ answer notCarriedOut; state unknown, fault notCarriedOut
```

It is a real `close`: a window opened by the INTEGRA remote closes. It answers when the pulse arrives or the wait ends.

Without `feedback`: no confirmation exists, `confirmed` stays absent, every end is computed, and `confirm` is unbound.

- **State** (12a §3): `{ current, state, confirmed, moving }`, saved at every confirmation and at the debounce's pace. After a restart: relays off; `moving: true` ⇒ `unknown`; else as saved, `confirmed` kept — it says when the state was last proved, not that it still holds.
- A relay changed elsewhere ⇒ `state` `unknown` until the next confirmed end.
- A source that throws `SourceUnreachable`: both relays off, the call answers `unreachable` (12a §3).

### 3.2. Bundle `velux-klf` — window and cover

One roof window and its cover on one KLF 150: two home devices, a `Closure` and a `WindowCovering`, that exclude each other.

| Member | Template | Sources |
|---|---|---|
| `window` | `closure-from-klf` (§3.1) | `open`, `close`, `feedback` |
| `cover` | `cover-from-klf` (12c-06 §3.6) | `up`, `down`, `feedback`, `wind` |

- **Anchor:** the window's `open` relay. The other sources are not found from it: they are `home.source` refs in the bundle's settings, with the members' required timings (`openMs`, `closeMs`, `upMs`, `downMs`), and `resolve` hands them on (12a §3a).
- **Interlock**, each member checking its peer (`ctx.peer`, 12a §3a) when a call arrives:

  | Call | Allowed when | Else |
  |---|---|---|
  | window `open`, `goTo` toward open | cover `lift.current` = 0 | `interlock` |
  | cover down — `down`, `goTo` with a higher lift, `reference({ end: 'down' })` | window `state` `closed`, and window `confirm` succeeds | `interlock` |
  | window `close`, cover `up` | always | |

  - **Every cover-down is confirmed first**: the cover calls the window's `confirm`, then moves. It costs a few seconds, and the KLF can't run both products at once anyway (research/matter/10 §1.4).
  - An unknown position, an unreachable peer, a peer removed from the bundle ⇒ refuse.
  - The window shows it: `blocked.open: 'interlock'` while the cover isn't fully up.
  - Wind level 2 raises the cover (12c-06 §1.2); raising never needs the window.
  - A move from VELUX's own controls bypasses all of this (research/matter/10 §2.3).
- 16a exposes the bundle as one bridged node with two children, Closure and Window Covering (16a, composed bridged devices).

### 3.3. KLF 150 set-up

What `closure-from-klf` and `cover-from-klf` need set in the KLF 150's software (research/matter/10 §1.5):

| | Window | Cover |
|---|---|---|
| Input pair | 1/2, this product only | 3/4, this product only |
| Output | A, 2 s pulse on a carried-out command | B, the same |
| Input behaviour | default: < 1.5 s ⇒ end, longer ⇒ runs while held, both ⇒ stop | the same |
| Groups, scenes, set positions | none | none |

Commissioning test, a stopwatch on each DI: `close` on a closed window, `close` on an open one, `open` with the rain sensor wet — pulse or none, and its delay. The templates assume: a pulse each time a command is carried out, at its end, and none when it isn't. `confirmFastMs` comes from the first test.

### 3.4. `closure-from-uap`

A Hörmann drive with a UAP1-HCP adapter board — a garage door (research/matter/07 §3). Three relays pulse the UAP's open, close and stop inputs; its relays K01 and K02 report the two ends, K03 optionally reports travel. Fits any drive with pulse inputs for open, close, stop and contacts at both ends.

| Role | Types | UAP1-HCP |
|---|---|---|
| `open` | `unipi.ro` \| `unipi.do`, 1 | 15–20 |
| `close` | `unipi.ro` \| `unipi.do`, 1 | 17–20 |
| `stop` | `unipi.ro` \| `unipi.do`, 1 | stop input, NO |
| `openEnd` | `unipi.di`, 1 | K01 |
| `closedEnd` | `unipi.di`, 1 | K02 |
| `moving` | `unipi.di`, 0–1 | K03, menu 30 = `09` (§3.5) |

| Setting | Default | Note |
|---|---|---|
| `kind` | `garageDoor` | → `behavior` |
| `openMs`, `closeMs` | required | full travel, measured |
| `marginMs` | 5000 | added to travel before `travelTimeout` |
| `startMs` | 3000 | time for a pulse to show; longer than the drive's pre-warning (menu 32) |
| `pulseMs` | 500 | relay on; the UAP's minimum is not known (research/matter/07 §3.1) |
| `reversePauseMs` | 1000 | between `stop` and the opposite pulse |
| `openEndInvert`, `closedEndInvert`, `movingInvert` | `false` | `active = value XOR invert`, as `contact-from-di` (12c-04 §3.2) |

`positioning` is `ends`: `current` stays absent, `target` is 0 or 10000. `goTo` and `confirm` are unbound — the end contacts prove the state all the time.

**Drive:**

| Call | Relays |
|---|---|
| `open`, `close` | that relay on for `pulseMs` |
| `stop` | `stop` on for `pulseMs` |
| `open` while closing, `close` while opening | `stop`, wait `reversePauseMs`, then the new pulse |
| the same direction while moving; `open` while `open`; `close` while `closed` | nothing; `ok` |

- One relay at a time; every write waits for the ack of the one before.
- `target` emits at once (12a §4a). `stop` clears it.

**State** — from the contacts, after inversion:

| `openEnd` | `closedEnd` | `moving` | `state` | `motion` |
|---|---|---|---|---|
| 1 | 0 | – | `open` | `stopped` |
| 0 | 1 | – | `closed` | `stopped` |
| 0 | 0 | 1 | `partial` | direction: our last command; else away from the end just left |
| 0 | 0 | 0 | `partial` | `stopped` |
| 0 | 0 | unbound | `partial` | inferred, below |
| 1 | 1 | – | `unknown` | `stopped`; `fault` `endContacts` |

- **Without `moving`:** a move starts at our pulse or when an end contact drops; `motion` is our last command's direction, else away from the end just left. It ends at an end, or after `openMs`/`closeMs` + `marginMs` ⇒ `stopped`, `partial`. A stop elsewhere (hand remote) is not seen until then.
- **`confirmed`** = when the end contacts took their current values, or the first read after a start.

**Faults** (§2):

| `fault` | When |
|---|---|
| `notCarriedOut` | no reaction within `startMs` of our pulse: `moving` didn't rise, or the end contact didn't drop. From the middle without `moving`: not checked |
| `travelTimeout` | a move of ours, not stopped by us, reaches no end within travel + `marginMs` |
| `endContacts` | both end contacts at once |

- **Moves from elsewhere** — hand remote, wall button, BiSecur app — are tracked from the contacts, never refused: the drive's own inputs stay active (research/matter/07 §3.3).
- **Saved state:** nothing. After a restart: relays off; `state` from the contacts. In the middle `motion` is `stopped` — the direction of a move already running is not known; the next end contact sets the state.
- A relay write that throws `SourceUnreachable` answers `unreachable`. An end contact unreachable ⇒ `state` `unknown` (12a §3).

### 3.5. UAP1-HCP set-up

What `closure-from-uap` needs (research/matter/07 §3):

| | |
|---|---|
| Inputs | open 15–20, close 17–20, stop; potential-free NO contacts only — never a voltage |
| K01, K02 | end open, end closed → `openEnd`, `closedEnd` |
| K03 | drive menu 30 = `09`, relay on during travel → `moving` |
| Pre-warning | drive menus 32/33: the drive's light flashes before every travel, from any source; `startMs` must be longer |

Commissioning test: stopwatch `openMs` and `closeMs`; the shortest `pulseMs` the drive takes; what the drive does on `open` while closing, which sets `reversePauseMs`.

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). Closure `0x0230`; Closure Control with `PS`, and `PT` when the device can be blocked (an interlock peer, a gating lock).

| Matter | Home |
|---|---|
| Descriptor `TagList` | from `kind`: `roofWindow` → Closure `Window` (0x44/0x01) + Closure Window `Roof` (0x47/0x00); `facadeWindow` → `Window` + `Facade` (0x47/0x01); `garageDoor` → `GarageDoor` (0x44/0x05); `gate` → `Gate` (0x44/0x04); `door` → `Door` (0x44/0x06) |
| `MainState` | `Moving` while `motion` ≠ stopped; else `Error` with a `fault`; else `Protected` while `blocked` has an entry; else `Stopped` |
| `OverallCurrentState` | null when `state` is `unknown`; else `Position` `FullyClosed` / `FullyOpened` / `PartiallyOpened`, `SecureState` = `state` is `closed` |
| `OverallTargetState` | `Position` `MoveToFullyClosed` for target 10000, `MoveToFullyOpen` for 0; null otherwise |
| `MoveTo(position)` | `MoveToFullyOpen` → `open`, `MoveToFullyClosed` → `close`; other positions refused `CONSTRAINT_ERROR` |
| `Stop` | `stop` |
| `CurrentErrorList`, `OperationalError` | `notCarriedOut`, `travelTimeout` → `PhysicallyBlocked`; `endContacts` → `MaintenanceRequired` |
| `domain-error` `interlock`, `locked` | Matter `INVALID_IN_STATE` |

With `positioning: 'percent'`, a Closure Panel `0x0231` child carries the %: Closure Dimension with `PS`; `CurrentState.Position` = `current`, `TargetState.Position` = `target`, `SetTarget(Position)` → `goTo`; `Resolution` and `StepValue` 100 (1 %).

- `matter` origin (12a §4a): an endpoint of `0x0230` maps to `Closure`, `kind` from its tags; its Panel, if any, gives `current`. `blocked` stays empty.
- Apple and Google support for Closure: unknown (research/matter/07 §2). No Window Covering fallback (§1).
- **Access closures are not exposed for now.** 16a ignores a `Closure` with `kind` `garageDoor`, `gate` or `door`: exposing one needs the same proof on `open` as `DoorLock.unlock`, and Closure Control carries no PIN (research/matter/07 §1.8). Deferred with Door Lock's exposure (12c-09 §4) to M3.6. Windows stay exposed.

## 5. Moving and target

| Field | Reports |
|---|---|
| `target` | at once, on every call (12a §4a) |
| `current` | once a second while moving, and at the stop |
| `state`, `motion` | at every start, stop and confirmation |
| `confirmed` | at every confirmation |

## 6. Open

- **Who may open an access closure, and how it is proved** — M3.6 (13a). `open` (and `goTo` toward open) of a `garageDoor`, `gate` or `door` needs the same proof as `DoorLock.unlock` (12c-09 §1.2); `close` and `stop` need none. `proof` marks a method of a `DeviceType` (13 §5), and `Closure` is one type for every `kind` — how only the access kinds get it is decided there too. Whether a (virtual) `DoorLock` also gates it through `blocked.open: 'locked'` is decided there (research/matter/07 §1.8). Until then nothing is gated.
