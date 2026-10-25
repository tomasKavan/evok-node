# 12c-05 — Timer relay

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `TimerRelay` | a countdown that rules start and react to | none — 16a ignores it |

**For:** waiting, in rules. A rule never waits (12b §1): one rule starts a timer, another reacts when it elapses — a light off after a delay, a fan that runs on. The UI calls it "Timer".

**Not for:**

- Switching a load. It has no roles and drives nothing; a rule switches the load (12b §2.1). A light's or plug-in unit's own timed on is `onFor` (12c-01 §1.1) — the one a Matter controller reaches.
- Time of day and schedules — the almanac driver (12d).
- Repeating. There is no flasher mode; a rule may start the timer again on `elapsed`.

### 1.1. Behaviour

`state` is `idle`, `elapsing` or `paused`. **Running** means `elapsing` or `paused`: a paused timer is still running.

T is the call's `ms`, or `defaultMs` (§3) when absent — always clamped to `maxMs`.

| Call | `idle` | running |
|---|---|---|
| `start` | → `elapsing`, T | nothing |
| `restart` | → `elapsing`, T | remaining = T; `paused` stays `paused` |
| `add` | → `elapsing`, T | remaining + T, clamped to `maxMs`; `paused` stays `paused` |
| `toggle` | → `elapsing`, T | → `idle`, no `elapsed`; `ms` ignored |
| `pause` | nothing | `elapsing` → `paused` |
| `resume` | nothing | `paused` → `elapsing` |
| `cancel` | nothing | → `idle`, no `elapsed` |
| remaining reaches 0 | — | → `idle`; `elapsed` emits with `seq` +1 |

- **Only an expiry is `elapsed`.** `toggle` and `cancel` stop the timer on request; a consumer that must react to them reads `state` (12b §2.1, `on-and-set-delay-off`).
- **A call that does nothing still answers `ok`.** A rule fires and forgets (12b §4); a timer already in the asked-for state is not an error. Over `maxMs` is clamped, never refused.
- **`warning`** turns true when an `elapsing` timer's remaining reaches `warnBeforeMs`. It turns false when the timer goes `idle`, or when `restart`/`add` lifts remaining above `warnBeforeMs` again — so it can warn again. `pause` keeps it as it is. A rule triggers on it changing to true.

## 2. Fields

```ts
// @evok-node/driver-home
const Ms       = Codecs.uint32({ min: 1, unit: 'ms' });
const Duration = Codecs.struct({ ms: Codecs.optional(Ms) });   // absent ⇒ defaultMs

const TimerBehavior = Codecs.struct({        // settings a consumer must see (12a §2.3) — the Home UI offers a start from them
  defaultMs:    Ms,
  maxMs:        Codecs.optional(Ms),         // absent ⇒ no cap
  warnBeforeMs: Codecs.optional(Ms),         // absent ⇒ no warning
  persistent:   Codecs.bool(),
});

export const TimerRelay = device('home.TimerRelay', {
  ...CommonFields,
  state:       reading(Codecs.string({ enumValues: ['idle', 'elapsing', 'paused'] }), { subscribe: true }),
  remainingMs: reading(Codecs.uint32({ unit: 'ms' }), { subscribe: true }),
  warning:     reading(Codecs.bool(), { subscribe: true }),
  elapsed:     reading(Codecs.struct({ seq: Codecs.uint32(), at: Codecs.timestamp() }), { subscribe: true }),
  behavior:    reading(TimerBehavior, { subscribe: true }),
  start:       method('mutates', Codecs.void, Duration),
  restart:     method('mutates', Codecs.void, Duration),
  add:         method('mutates', Codecs.void, Duration),
  toggle:      method('mutates', Codecs.void, Duration),
  pause:       method('mutates', Codecs.void),
  resume:      method('mutates', Codecs.void),
  cancel:      method('mutates', Codecs.void),
});
```

- `remainingMs` is 0 when `idle` and frozen while `paused`. It emits on every call that changes it and once a second while `elapsing`, as `onForRemaining` does (12c-01 §2) — enough for a UI countdown. Rules never trigger on it (12b §3 `fields`).
- `elapsed` is one value per expiry; a gap in `seq` means a subscription coalesced expiries away (03 §6.3). No value until the first expiry.
- `identify` is unbound — nothing to blink.

## 3. Templates

| Template | Roles |
|---|---|
| `timer` | none |

A virtual device, always `reachable` (12a §3).

| Setting | Default |
|---|---|
| `defaultMs` | 60000 |
| `maxMs` | — |
| `warnBeforeMs` | — |
| `persistent` | `false` |

- The countdown is a one-shot deadline on the `Clock` (04 §4.1); `remainingMs` is read from it. `warning` is a second deadline, `warnBeforeMs` before the first.
- **State** (12a §3), only with `persistent`: saves `{ state, remainingMs, seq }` through `ctx.state` — on every call and while `elapsing`, at the debounce's pace (at most every 5 s). No wall clock: time the daemon is down does not count, and a restored timer may run up to one save interval longer.
- **Daemon start:**

| Saved | After start |
|---|---|
| nothing, or not `persistent` | `idle`, `elapsed` without a value |
| `paused` | `paused` with the saved `remainingMs` |
| `elapsing` | `elapsing` with the saved `remainingMs` |

- A restored timer resumes only once the rule engine has taken its baselines (12b §5.6), so its expiry triggers rules — the light a `delay-off` rule (12b §2.1) holds still goes off after a restart.
- A settings change (`manage`, 12a §5) applies from the next call; a running countdown keeps its remaining.

## 4. Matter

None. 16a ignores `TimerRelay`, and a `matter` origin never produces one: Matter has no timer device type and no timer cluster (research/matter/05 §1). A Matter controller's timed on is `OnWithTimedOff`, mapped to `onFor` (12c-01 §4).

## 5. Moving and target

Nothing moves. Every call takes effect at once: `state` and `remainingMs` emit before the call answers. While `elapsing`, `remainingMs` counts down once a second.
