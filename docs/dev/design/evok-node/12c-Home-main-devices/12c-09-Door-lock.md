# 12c-09 — Door lock

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `DoorLock` | a door released for a time by a signal, locked again by itself; door contact; who operated it | Door Lock `0x000A`, mapped in §4 — 16a ignores it for now |

**For:** a door whose lock a signal releases for a time the lock itself keeps — a motor lock's opener input, an electric strike, a 2N access unit's switch. The handle then opens the door; the lock locks again when the time ends and the door is shut.

**Not for:**

- A door that stays unlocked (a held relay, day mode) — not in this version.
- A door that moves by a motor — `Closure` (12c-07).
- Users, roles, PINs and who may unlock — 13a and the identity provider. The 2N's users come from the identity provider through Access Commander, never from evok-node (research/matter/08 P16).

### 1.1. Behaviour

`state` is `locked`, `unlocked`, `jammed` or `unknown`. `door` is `open`, `closed` or `unknown`; it is unbound without a door contact.

The **release window** starts at an unlock and lasts `releaseMs` — the lock's own release time (§3).

| Event | Result |
|---|---|
| `unlock` | release; `state` `unlocked`; the window starts |
| `unlock` while `unlocked` | release again; the window starts again |
| window over, door `closed` or unbound | `state` `locked`, `lastOperation` lock, source `auto` |
| window over, door `open` | stays `unlocked`; `locked` when the door closes |
| door opens while `locked` | `alarm` `forcedOpen` |
| door open longer than `openTooLongMs` | `alarm` `openTooLong`, once per opening |
| `lock` while `unlocked` | ends the release signal and answers `ok`; `state` follows the rows above — the lock's own release time can't be cut short |
| `lock` while `locked` | nothing; `ok` |

- **`locked` means secured.** With a door contact, `locked` needs the door shut. Without one, `locked` is assumed when the window ends.
- `jammed` is for a source that can tell; no built-in template sets it.
- A call that does nothing still answers `ok`, as 12c-05 §1.1.

### 1.2. Who operates it

Every `lock` and `unlock` records who did it in `lastOperation`:

- **The caller comes as `by`**, an `actor` argument of `lock` and `unlock` (13 §5). The api always overwrites it with its own caller, so no client can name someone else. `lastOperation.user` is `by.id` and `by.name`.
- **Source from `by`:** realm `matter` → `matter`; any other realm → `app`; no `by` → `rule`.
- **`unlock` is marked `access.proof`** (05a §3.1b, 13 §5): the api gets proof before it relays the call. What the proof is — a confirmation by a logged-in user, a PIN the identity provider resolves to a user — is 13a's. The device trusts the call it gets.
- Opened at the lock — a 2N keypad, card, exit button — the source and user come from the source (§3.2).

**Open:** what `proof` asks of a caller — M3.6 (13a).

## 2. Fields

```ts
// @evok-node/driver-home
const LockSource = Values.string({ enumValues: [
  'app',          // Home UI, Home API, Inspector — a call through an API
  'matter',       // a Matter controller (§4)
  'rule',         // 12b
  'auto',         // the window ended
  'keypad', 'rfid', 'biometric', 'mobileKey', 'button',   // at the lock (§3.2)
  'unspecified',  // the source changed without us (§3.1)
] });

const LockUser = Values.struct({
  id:   Values.optional(Values.string()),   // the identity provider's user id
  name: Values.optional(Values.string()),
});

const LockOperation = Values.struct({
  type:   Values.string({ enumValues: ['lock', 'unlock'] }),
  source: LockSource,
  user:   Values.optional(LockUser),
  seq:    Values.uint32(),                  // +1 per operation
  at:     Values.timestamp(),
});

const LockAlarm = Values.struct({
  kind: Values.string({ enumValues: ['forcedOpen', 'openTooLong', 'tamper'] }),
  seq:  Values.uint32(),
  at:   Values.timestamp(),
});

const LockBehavior = Values.struct({        // settings a consumer must see (12a §2.3) — a UI shows the window
  releaseMs: Values.uint32({ min: 1, unit: 'ms' }),
});

export const DoorLock = device('home.DoorLock', {
  ...CommonFields,
  state:         reading(Values.string({ enumValues: ['locked', 'unlocked', 'jammed', 'unknown'] }), { subscribe: true }),
  door:          optional(reading(Values.string({ enumValues: ['open', 'closed', 'unknown'] }), { subscribe: true })),
  lastOperation: reading(LockOperation, { subscribe: true }),
  alarm:         reading(LockAlarm, { subscribe: true }),
  behavior:      reading(LockBehavior, { subscribe: true }),
  unlock:        method('mutates', Values.void, Values.struct({ by: Values.actor() }), { errorKinds: ['blocked'], access: { proof: true } }),   // 05a §3.1b, 13 §5
  lock:          method('mutates', Values.void, Values.struct({ by: Values.actor() })),
});
```

| `errorKinds` | Means |
|---|---|
| `blocked` | the lock refused — a 2N switch locked out or blocked after tamper (§3.2) |

- `lastOperation` and `alarm` carry one value per operation or alarm; a gap in `seq` means a subscription coalesced values away (03 §6.3). No value until the first one.
- `door` is bound only with a door contact. Without it, `forcedOpen` and `openTooLong` never occur.
- `identify` is unbound — releasing a door to identify it is unsafe.

## 3. Templates

| Template | Roles |
|---|---|
| `lock-from-relay` (§3.1) | `release`: `unipi.ro` \| `unipi.do`, 1 · `door`: `unipi.di`, 0–1 |
| `lock-from-2n` (§3.2) | `access`: a 2N switch, 1 · `door`: the 2N door state \| `unipi.di`, 0–1 — types from the 2N driver (12e) |

### 3.1. `lock-from-relay`

A lock with an opener input (motor lock) or a fail-secure strike on a relay or DO.

| Setting | Default | Note |
|---|---|---|
| `pulseMs` | 1000 | relay on |
| `releaseMs` | required | the lock's own release time → `behavior` |
| `openTooLongMs` | — | absent ⇒ no `openTooLong` |
| `doorInvert` | `false` | `closed = value XOR doorInvert`, as `contact-from-di` (12c-04 §3.2) |

```
unlock    release on → off after pulseMs (on-write acked ⇒ state unlocked, lastOperation)
          window = releaseMs from the on-write's ack
lock      release off if still on; ok
release on from elsewhere ⇒ an unlock, source 'unspecified'
```

- A fail-safe strike or maglock (release on = locked) is not supported: the watchdog's off state would open the door (research/matter/08 P9).
- **State** (12a §3): nothing saved. After a restart: release off, `state` `unknown`; after `releaseMs` the §1.1 rules apply — a release from before the restart may still run in the lock.
- A write that throws `SourceUnreachable` answers `unreachable`; `state` keeps its value (12a §3).
- `door` unreachable ⇒ `door` `unknown`, and locking falls back to the window alone.

### 3.2. `lock-from-2n`

One switch of a 2N Access Unit 2.0 or IP Verso 2.0, through the 2N driver (12e). The 2N keeps its own users, keypad and cards; this template opens the door and reports what the 2N reports.

| Home | 2N (research/matter/08 §4) |
|---|---|
| `unlock`, `by` with a user of realm `idp` | `grantaccess` for that user, `by` handed on — the 2N's access log names them; the user map is 12e's |
| `unlock`, any other `by` or none | `switch/ctrl` `trigger`, `message` naming the source |
| `lock` | `switch/ctrl` `off` |
| switch on | `state` `unlocked`, `lastOperation` unlock: source and user from the event that caused it — `UserAuthenticated` → its user and credential kind (`keypad`, `rfid`, `biometric`, `mobileKey`), `RexActivated` → `button`, ours → our source |
| switch off | the window is over — §1.1 |
| `UnauthorizedDoorOpen` | `alarm` `forcedOpen` |
| `DoorOpenTooLong` | `alarm` `openTooLong` |
| `TamperSwitchActivated` | `alarm` `tamper` |
| switch locked, `SwitchesBlocked`, `grantaccess` refused | `unlock` answers `blocked` |

- `releaseMs` is the 2N switch's Switch-On Duration, read by the driver; not a setting here.
- `openTooLongMs` is the 2N's own Door Open Too Long setting when `door` is the 2N's.

**Open:** the role types and the user map — M3.6a (12e).

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`), **not exposed for now**: 16a ignores `DoorLock`. A remote PIN, Matter's user database and a bridge per flat are deferred (research/matter/08 P11–P16).

Door Lock `0x000A`. Features: `DPS` when `door` is bound; no `UBOLT`, `USR`, `PIN`, `COTA`.

| Matter | Home |
|---|---|
| `LockState` | `locked` → `Locked`, `unlocked` → `Unlocked`, `jammed` → `NotFullyLocked`, `unknown` → null |
| `LockType` | `Other` |
| `ActuatorEnabled` | `true` |
| `OperatingMode` | `Normal`; supported: `Normal`, `NoRemoteLockUnlock` |
| `AutoRelockTime` | not present — `state` comes from home, never from matter.js's relock timer (research/matter/08 §1.10) |
| `DoorState` | `open` → `DoorOpen` (`DoorForcedOpen` after a `forcedOpen` until it closes), `closed` → `DoorClosed`, `unknown` → null |
| `UnlockDoor`, `LockDoor` | `unlock`, `lock`; source `matter` |
| event `LockOperation` | from `lastOperation`: `matter` → `Remote`, `app`/`rule` → `ProprietaryRemote`, `auto` → `Auto`, `keypad` → `Keypad`, `rfid` → `RFID`, `biometric` → `Biometric`, `button` → `Button`, `mobileKey`/`unspecified` → `Unspecified` |
| event `DoorLockAlarm` | `forcedOpen` → `DoorForcedOpen`, `openTooLong` → `DoorAjar`, `tamper` → `FrontEsceutcheonRemoved`; `jammed` → `LockJammed` |
| event `DoorStateChange` | from `door` |
| `domain-error` `blocked` | `Failure` + `LockOperationError` |

- Without `UBOLT` the lock "perform[s] the same operation for both commands" (research/matter/08 §1.5); `UnboltDoor` is absent.
- `matter` origin (12a §4a): a Door Lock endpoint maps to `DoorLock` by the same table; `releaseMs` from its `AutoRelockTime` when present.

## 5. Moving and target

Nothing moves. `unlock`: `state` and `lastOperation` emit before the call answers — after the relay's on-write ack, or the 2N's answer. `locked` follows later, from the window and the door.
