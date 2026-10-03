# 12 — DALI driver

## 1. Scope

Package: `packages/driver-dali` (`@evok-node/driver-dali`). Config `type: dali`.

Everything DALI-bus-specific goes here: pluggable controller backends, raw frame construction, the stored gear/group model, discovery. It depends on `driver-kit` (05a), the KV-store driver's client (06) for persisted gears/groups (05a §3.6), `line-kit` (07b) for serial/TCP byte transport, and optionally `modbus-kit`'s `ModbusTransport` (07 §4/§7) for a Modbus-backed controller.

Out of scope for v1, stated once here rather than per-section: DALI2 control-device frames (24-bit, IEC 62386-103/2xx), scenes, colour control (device type 8), memory-bank access. §13 lists these; nothing below silently half-supports them.

## 2. Configuration

```ts
interface DaliConfig {
  daliCtrlKind: string;                 // resolves a DaliControllerFactory — §3
  transport: DaliTransportConfig;       // §4
  ctrl?: unknown;                       // opaque here — validated only by the resolved factory's own schema
}

type DaliTransportConfig =
  | { kind: 'line'; line: LineTransportConfig }       // 07b — serial or TCP, line-kit's own two variants
  | { kind: 'modbus'; modbus: ModbusTransportConfig }; // 07 §4 — direct or relay, all three of its own kinds; no built-in controller uses this yet, §4.2
```

```yaml
drivers:
  DALI1:
    type: dali
    daliCtrlKind: dali-foxtron-ASCII
    transport: { kind: line, line: { kind: serial, path: /dev/ttyUSB0, baudRate: 19200, dataBits: 8, stopBits: 1, parity: even } }
    ctrl: {}                                 # dali-foxtron-ASCII needs nothing extra — its own schema says so
```

Same two-schema sequencing 02 §5 step 4 already uses for a whole driver's body, one level deeper: `main` validates `DaliConfig` itself (`daliCtrlKind`/`transport` known here, `ctrl` opaque); this driver's own `configure()` then resolves `daliCtrlKind` (§3) and validates `ctrl` against that factory's own `schema`. A `ctrl` that doesn't parse, or a `transport.kind` the resolved factory doesn't declare support for (§3's `acceptsTransport`), is fatal at `configure()` — same tier as an unresolvable `daliCtrlKind` itself.

How many DALI buses live behind one `transport` — one, or several multiplexed over it — is entirely the resolved controller's own business, declared inside `ctrl`, never a key this file defines generically. §7 covers what that means for addressing.

## 3. Pluggable controllers — the `dali-controller` plugin kind

Same mechanism as `modbus-kind-binder` (07a §7), not a new one. New manifest kind, identifying field `ctrlKind`:

```json
// @acme/evok-node-dali-acme — package.json
{
  "evokNodePlugin": {
    "manifestVersion": "1",
    "plugins": [{ "kind": "dali-controller", "ctrlKind": "dali-acme-x1", "path": "./dist/index.js", "export": "acmeX1Controller" }]
  }
}
```

```ts
// @evok-node/driver-dali
interface DaliBusHealth {
  state: 'unknown' | 'probing' | 'online' | 'degraded' | 'offline';
  detail?: 'short-circuit' | 'mains-voltage' | 'unsuitable-power-supply' | 'buffer-full' | 'checksum-error' | 'invalid-command';
  lastGoodAt: Date | null;   // §5's Clock rule — never Date.now()
}

interface DaliController {
  open(): Promise<void>;
  close(): Promise<void>;
  send(frame: DaliFrame, deadline?: Deadline): Promise<CallOutcome<DaliBusTransaction, DaliBusExceptionKind>>;
  onTraffic(cb: (t: DaliBusTransaction) => void): void;   // every transaction observed, ours or not — §8
  health(): DaliBusHealth;                                // pull — seeds this bus's health field, answerable on demand
  onHealth(cb: (h: DaliBusHealth) => void): void;         // push — a controller with no spontaneous fault reporting just never calls this
}

interface DaliControllerFactory<Config> {
  readonly ctrlKind: string;
  readonly schema: ZodType<Config>;
  readonly acceptsTransport: readonly ('line'|'modbus')[];
  create(transport: LineTransport | ModbusTransport, config: Config, deps: { clock: Clock; log: Logger }): ReadonlyMap<number, DaliController>;
}
```

`create()` returns one `DaliController` per DALI bus the resolved config actually exposes over this one transport, keyed by `busIndex` — the controller's own numbering, never inferred, validated for contiguity, or renumbered by this driver; it's used only as an opaque map key and tail segment (§7). `dali-foxtron-ASCII` (§6) always returns a one-entry map at `busIndex: 0` — not a special case this driver branches on, just the common size of that map. An empty map is fatal at `configure()`, same tier as an unresolvable `daliCtrlKind`.

Registered one of two ways, same duality as `modbus-kind-binder` (07a §7): direct, `registerCtrl(factory)`, for a controller known at this package's own build time — `dali-foxtron-ASCII` (§6) uses this; manifest, the `package.json` shape above, resolved lazily via `ctx.plugins.resolve('dali-controller', ctrlKind)`, memoized the same way every other kind is (02 §4). `isDaliControllerFactory` is registered as `'dali-controller'`'s own guard at this package's module-load time, same shape as `isModbusKindBinder` (07a §7).

`DaliBusExceptionKind` is this driver's own closed `domain-error` vocabulary (03 §7) for a transmission the controller itself refuses or can't complete — `'bus-collision-unresolved' | 'buffer-full' | 'controller-error'` — distinct from `'unreachable'`/`'timeout'`, which cover the controller or line simply not answering at all.

## 4. Transport

### 4.1. `line-kit`

The serial/TCP byte transport itself — `LineTransport`/`LineTransportConfig`, its reconnect policy, and its testing — is 07b's own doc, not restated here. This driver's `transport.line` (§2, `kind: 'line'`) is a `LineTransportConfig` passed straight through, unwrapped; `dali-foxtron-ASCII` (§6) is what actually frames Foxtron's SOH/checksum/ETB protocol on top of the raw byte stream 07b hands it, identically for either of `LineTransportConfig`'s own serial/TCP variants. `modbus-kit`'s own RTU transport (07 §3) builds on the same package, for the same reason.

### 4.2. Modbus-backed controllers

For a `daliCtrlKind` whose `acceptsTransport` includes `'modbus'`: this driver calls 07's own `createModbusTransport(transport.modbus, ctx)` (07 §4) and hands the resolved controller factory's `create()` (§3) whatever `ModbusTransport` comes back — direct wire or relay facade, entirely `transport.modbus.kind`'s own answer (07 §4, §6); this driver never branches on it itself. This is also the natural home for a controller kind that maps *several* DALI buses onto one Modbus connection via distinct register blocks (§3's `ReadonlyMap` return exists for exactly this, worked example in §7) — no built-in controller does this yet (§13); it exists so one has somewhere real to build against without this driver reinventing Modbus.

## 5. The frame model

Fixed 16-bit DALI (Part 102) only — no DALI2 24-bit control-device frames yet (§13).

```ts
// @evok-node/driver-dali
type DaliAddress =
  | { readonly kind: 'short'; readonly address: number }    // 0-63
  | { readonly kind: 'group'; readonly group: number }       // 0-15
  | { readonly kind: 'broadcast' };

interface DaliFrame {
  readonly addressByte: number;   // uint8, wire-ready — encodes DaliAddress + the level/command selector bit
  readonly dataByte: number;      // uint8, wire-ready
  readonly sendTwice: boolean;    // set by the constructor that built this frame, per its own opcode — never a send()-time option
}

interface DaliAnswer {
  readonly garbled: boolean;      // an answer arrived but was unreadable (collision) — never "value 0"
  readonly value?: number;        // uint8; absent iff garbled
}

interface DaliBusTransaction {
  readonly forward: DaliFrame;              // what actually went on the bus — ours or another controller's
  readonly backward?: DaliAnswer;           // absent = nothing answered at all; present (garbled or not) = something did
  readonly origin: 'self' | 'other' | 'unknown';   // 'unknown' for a controller kind that can't tell (§6)
  readonly observedAt: Date;                // new Date(clock.now()) — never Date.now() (04 §4.1); same-process relative ordering only, never compared across a link
}
```

Three answer states, never conflated (05 §2's "no value yet is not value 0," restated for a bus with no memory of its own): `backward` absent (nothing answered — the standard "No" to a yes/no query), `backward.garbled` (something answered, unreadably — usually a collision), `backward.value` (a clean 8-bit answer).

### 5.1. Constructors — `DaliFrames`

One function per command, `sendTwice` baked in per IEC 62386-102's own classification (opcodes `0x20`–`0x80`, the "configuration commands" block, plus the special commands `INITIALISE`, `RANDOMISE`, `PROGRAM SHORT ADDRESS`) — never left to a caller to get right:

```ts
// @evok-node/driver-dali — illustrative subset; every opcode below is a real IEC 62386-102 command
const DaliFrames = {
  dapc(t: DaliAddress, level: number): DaliFrame,                          // 1-254; level 0 is off(), never dapc(t,0) — §9.2
  off(t: DaliAddress, opts?: { fade?: boolean }): DaliFrame,               // fade ⇒ false (default): opcode 0x00, immediate; true: DAPC value 0x00, fades to min then off
  up(t)/down(t)/stepUp(t)/stepDown(t)/recallMaxLevel(t)/recallMinLevel(t): DaliFrame,
  enableDapcSequence(t: DaliAddress): DaliFrame,                          // opcode 0x09 — forces a fixed 200ms fade for the DAPC(s) that follow, self-expiring; sendTwice: false — §9.2
  goToScene(t, scene: number): DaliFrame,                                  // 0-15 — §13
  reset(t): DaliFrame,                                                     // sendTwice: true
  setDtr(value: number): DaliFrame,                                        // special command — no DaliAddress, sendTwice: false
  storeDtrAsFadeTime(t)/AsFadeRate/AsMinLevel/AsMaxLevel/AsPowerOnLevel/AsSystemFailureLevel(t: DaliAddress): DaliFrame,  // sendTwice: true
  addToGroup(t: DaliAddress, group: number)/removeFromGroup(t, group): DaliFrame,   // sendTwice: true
  initialise(scope: 'unaddressed' | 'all' | { shortAddress: number }): DaliFrame,   // sendTwice: true
  randomise(): DaliFrame,                                                  // sendTwice: true
  compare(): DaliFrame, withdraw(): DaliFrame, terminate(): DaliFrame,
  searchAddrH(byte: number)/searchAddrM(byte)/searchAddrL(byte): DaliFrame,
  programShortAddress(addr: number): DaliFrame,                            // sendTwice: true
  verifyShortAddress(addr: number): DaliFrame,
  queryShortAddress(): DaliFrame,
};
```

### 5.2. Paired queries — `DaliQuery<T>`

A query and how to read its own answer travel together, never authored separately — same reasoning `TypedCodec` already applies to a `Codec`/`ValueSchema` pair (05a §3.1):

```ts
interface DaliQuery<T> { readonly frame: DaliFrame; decode(a: DaliAnswer | undefined): T; }

function queryActualLevel(t: DaliAddress): DaliQuery<{ level: number } | { unknown: true }>;
function queryStatus(t: DaliAddress): DaliQuery<DaliStatusBits | { unknown: true }>;
function queryGroups(t: DaliAddress): DaliQuery<readonly number[]>;   // issues both QUERY GROUPS 0-7/8-15 internally, decodes to a plain array for the gear's own `groups` field (§9.1) — never a bitmask on this side of the boundary
```

## 6. Built-in controller: `dali-foxtron-ASCII`

Foxtron DALI232/DALI232e/DALInet/DALI2net, ASCII protocol (their own "Communication protocol", not their Modbus RTU mode — that would be a `modbus`-backed `ctrlKind`, §4.2, not this one).

Framing: `SOH (0x01) | data (ASCII hex pairs) | checksum (ASCII hex pair) | ETB (0x17)`; checksum is the two's-complement of the data bytes' sum mod 256. Message types used: `11`/`13`/`14` (sender-differentiated send/receive) in preference to `1`/`3`/`4` — the only way `DaliBusTransaction.origin` can distinguish `'self'` from `'other'` rather than falling back to `'unknown'`. Type `5` (bus fault/mains/buffer/checksum/invalid-command) maps directly onto `DaliBusHealth.detail`. Serial: 19200 baud, 8 data bits, even parity, 1 stop bit, DTR held on (this converter is DTR-powered — a controller without external power needs it; `line-kit`'s serial config doesn't manage DTR itself, so this controller sets it directly on open). TCP (`DALInet`/`DALI2net`): identical ASCII messages over a plain socket, port 23 (bus 1) or 24 (bus 2) — no separate framing, confirming `line-kit`'s "one byte pipe, protocol decides framing" split was the right cut.

Every physical bus this family exposes is its own TCP port (or, for `DALI232`/`DALI232e`, its own serial port) — never two buses sharing one connection — so this controller kind always returns a one-entry `ReadonlyMap` at `busIndex: 0` (§3). `DALInet`'s second bus, where the hardware has one, is a second driver instance pointed at port 24 (§7's second worked example), not a second entry here.

## 7. Addressing and multi-bus

One driver instance owns exactly the set of DALI buses reachable through the one transport it was configured with (§2, §4) — usually one, occasionally more when a controller kind multiplexes several logical buses over one shared transport (§4.2). How many, and how each is reached, is entirely the resolved `DaliControllerFactory`'s own business (§3); this driver just binds whatever `busIndex → DaliController` map it gets back.

Bus index is always part of the tail for anything bus-scoped, even when there's only one bus (`bus.0`) — a uniform grammar, never conditional on how many buses a given instance happens to have, the same "don't special-case the common size" reasoning 05a §3.3 already applies to a single-field `Device`. Commissioning is the one deliberate exception:

| Tail | Device / methods | Scope |
|---|---|---|
| `bus.<i>.raw` | `DALI_RAW` (`send`, `traffic`, `health`) | one bound per bus — §8 |
| `bus.<i>.gear.<0-63>` | `DaliGear` | one per gear, per bus — §9.1 |
| `bus.<i>.group.<0-15>` | `DaliGroup`, all 16 always bound | one set per bus — §9.4 |
| `commissioning` | `discoverNextDevice`/`setShortAddress`/`freeShortAddress`/`freeAllShortAddresses`/`saveDevice`/`removeGear` | **not** bus-indexed by tail — every method takes `busIndex` as its own first argument instead — §11 |

Its session state (§11) is naturally keyed by `busIndex` internally (`Map<busIndex, CommissioningSession>`), and every one of its methods already names a specific address as an argument — adding `busIndex` alongside it is simpler than multiplying six methods across N tails for no addressing benefit, since nothing subscribes to a commissioning method the way it subscribes to a reading. The data-plane devices get the opposite treatment because that's exactly what driver-kit's own `$introspect`/wildcard machinery (05a §4/§6) already expects an address, not a parameter, to iterate over: `bus.0.gear.*` is an ordinary wildcard subscribe (05a §6); nothing here invents a bus-spanning one (`bus.*.gear.5`) — a client wanting "every gear on every bus" subscribes once per bus it already knows about from `$introspect`.

### 7.1. Worked examples

**One controller, two buses sharing one transport** — a Modbus gateway mapping two DALI buses onto two register blocks of the same connection; `ctrl`'s own shape is this controller kind's business, never this driver's:

```yaml
drivers:
  DALI1:
    type: dali
    daliCtrlKind: acme-dali-modbus-2bus
    transport: { kind: modbus, modbus: { kind: modbus-tcp, host: 10.0.0.5, port: 502 } }
    ctrl:
      unitId: 1
      buses:
        - { index: 0, registerBase: 0 }
        - { index: 1, registerBase: 1000 }
```

`acmeDaliModbus2BusController.create(transport, ctrlConfig, deps)` opens the one `ModbusTransport` and returns `Map { 0 => DaliController, 1 => DaliController }` — two controllers, one connection. Resulting addresses, all under the one driver id:

```
DALI1:bus.0.raw            DALI1:bus.0.gear.5            DALI1:bus.0.group.2
DALI1:bus.1.raw            DALI1:bus.1.gear.5            DALI1:bus.1.group.2   # a different physical gear/group from bus 0's, despite the same number
DALI1:commissioning        # one tail for both buses — discoverNextDevice({busIndex:1}) runs a session scoped to bus 1 only
DALI1:$health              # aggregate — degraded if either bus is (§7.2)
```

**Two independent physical connections** — `DALI2net`'s two TCP ports, for contrast: not one instance with two buses, just two ordinary single-bus instances, same as any other independent line:

```yaml
drivers:
  DALI_BUS1: { type: dali, daliCtrlKind: dali-foxtron-ASCII, transport: { kind: line, line: { kind: tcp, host: 10.0.0.9, port: 23 } } }
  DALI_BUS2: { type: dali, daliCtrlKind: dali-foxtron-ASCII, transport: { kind: line, line: { kind: tcp, host: 10.0.0.9, port: 24 } } }
```

```
DALI_BUS1:bus.0.gear.5     DALI_BUS2:bus.0.gear.5   # the driver id already disambiguates — bus.0 in both, by construction
```

The tail grammar is identical either way; what differs is only whether one `daliCtrlKind` hands back a multi-entry bus map from one transport, or several driver instances each get their own one-entry map.

### 7.2. Health

`$health` (03 §3) is driver-scoped and singular, so it never carries a specific bus's own detail. `bus.<i>.raw`'s `health` field (§8) is that one bus's current `DaliBusHealth`, fed directly from its own `DaliController.health()`/`onHealth()` (§3). `$health` itself is this driver's own aggregate across every bound bus — the worst state present — for a client that only wants "is this instance healthy at all" without enumerating buses first.

## 8. Raw bus access

```ts
export const DALI_RAW = device('dali.raw', {
  send:    method('dali.send', 'mutates', DaliBusTransactionCodec, DaliFrameCodec, { errorKinds: DALI_BUS_EXCEPTION_KINDS }),
  traffic: reading('dali.traffic', DaliBusTransactionCodec, { subscribe: true }),   // GET = last observed transaction (memory, legal per 05 §2); subscribe = every one since
  health:  reading('dali.raw.health', DaliBusHealthCodec, { subscribe: true }),     // this bus's own — §7.2
});
```

Bound once per bus, at `bus.<i>.raw` (§7) — never a single shared instance, even though one physical transport may underlie several.

## 9. Stored gears and groups

### 9.1. `DaliGear` — `bus.<i>.gear.<0-63>`

`@`'s own schema can't be primitive once siblings exist (05a §3.3) — so intensity lives inside a one-field struct, not bare:

```ts
const DaliGear = device('dali.gear', {
  '@':            channel('dali.gear.level', Codecs.struct({ intensity: Codecs.uint8({ min: 0, max: 254 }) }), { subscribe: true, set: DaliLevelSetCodec }),
  fadeTime:       channel('dali.gear.fadeTime', Codecs.uint8({ min: 0, max: 15 })),
  fadeRate:       channel('dali.gear.fadeRate', Codecs.uint8({ min: 0, max: 15 })),
  minLevel:       channel('dali.gear.minLevel', Codecs.uint8()),
  maxLevel:       channel('dali.gear.maxLevel', Codecs.uint8()),
  powerOnLevel:       channel('dali.gear.powerOnLevel', Codecs.uint8()),
  systemFailureLevel: channel('dali.gear.systemFailureLevel', Codecs.uint8()),
  groups:         channel('dali.gear.groups', Codecs.array(Codecs.uint8({ min: 0, max: 15 }))),   // array of group numbers, never a bitmask — SET diffs old vs new into ADD/REMOVE-GROUP; always this gear's own bus (§7) — group numbers don't cross buses
  status:         reading('dali.gear.status', DaliStatusBitsCodec, { subscribe: true }),           // lamp/ballast failure — the one field the sparse poll exists for, §10
  dimming:        reading('dali.gear.dimming', Codecs.enum(['up', 'down', 'none']), { subscribe: true }),
});
// same tail, method fields:
//   up()/down(): starts a repeating command — §9.3
//   stop(): cancels it
```

`DaliLevelSetCodec = Codecs.struct({ intensity: Codecs.uint8({min:0,max:254}), instant: Codecs.bool() })` — `instant` omitted ⇒ `false`.

### 9.2. `intensity` — 0 is categorically off, never "a low level"

`intensity: 0` and `minLevel` are different things (a ballast's configured floor is never `0` in practice, and `1..254` is "on" regardless of where it sits relative to `minLevel`). `SET({intensity: 0, instant})` maps to `off(t, {fade: !instant})` — immediate `OFF` (opcode `0x00`) when `instant`, DAPC-fade-to-min-then-off otherwise. `SET({intensity: n > 0, instant})` maps to `dapc(t, n)` directly when `!instant`; when `instant`, it's `enableDapcSequence(t)` → `dapc(t, n)` — the gear uses a fixed 200ms fade for this DAPC regardless of its configured `fadeTime`, and the override expires on its own 200ms later, so there's nothing to restore and no failure mode where a botched write leaves `fadeTime` wrong. `fadeTime`'s own configured value (§9.1's `fadeTime` channel) is never touched by an `instant` write. This is 200ms, not a true 0ms snap — the only way to get an actual instant transition is `fadeTime=0` itself, which is what the DALI standard's own fade-time scale calls "no fade"; that's a real fallback (`setDtr(0)` → `storeDtrAsFadeTime(t)` ×2 → `dapc` → restore ×2, the DTR-save/restore dance) but not the default, since `ENABLE DAPC SEQUENCE` covers the practical "instant-ish" case at a sixth of the cost and none of the restore risk (§13).

A successful `SET`'s own requested value is written straight into the cache — §10 says why a read-back isn't needed. `status`'s own `lampPowerOn` bit is the one thing that can disagree with a `SET` that reported success (the ballast refused for a reason the bus transaction itself can't see, e.g. a burnt-out lamp) — that disagreement surfaces through `status`, never by second-guessing `@`.

### 9.3. `up`/`down`/`stop`/`dimming`

`UP`/`DOWN` are each a single ~200ms ramp-and-stop, not a continuous action (per the standard's own timing) — continuous dimming is this driver re-issuing the same command back-to-back. `up()`/`down()` starts a `scheduleRepeating(clock, 200ms, 'skip', ...)` loop that keeps sending the same command until: `stop()` is called, or the gear's own cached intensity (updated from each iteration — there's no backward frame for `UP`/`DOWN`, so a `queryActualLevel` runs once the loop actually stops, never mid-loop) reaches `maxLevel` (`up`) or `minLevel` (`down` — `DOWN` never crosses into off, matching §9.2's off/minLevel split). `dimming` reflects `'up'|'down'|'none'` for exactly as long as the loop runs, emitted on every transition.

### 9.4. `DaliGroup` — `bus.<i>.group.<0-15>`, all 16 always bound

Mirrors `DaliGear`'s `@`/`fadeTime`/`fadeRate`/`up`/`down`/`stop`/`dimming` exactly, on the same bus as its members (a group number is local to one bus — bus 0's group 3 and bus 1's group 3 are unrelated). Differs in two ways: `minLevel`/`maxLevel` are `reading`-only here (never `channel`) — computed live as the lowest `minLevel`/highest `maxLevel` over the group's own current members, never written through this field directly (a group-addressed `STORE DTR AS MIN/MAX LEVEL` is still reachable via `DALI_RAW.send` if genuinely needed — this convenience field just isn't how). And a group's own `@`/`fadeTime`/`fadeRate` cache is **sticky**: set only by a direct write to the group, never re-derived from a member's own later, individually-addressed change — but the reverse direction does propagate: a successful group `SET` writes the same value into every current member gear's own cache too (from `groups`, §9.1) and emits for each, so a client watching one gear stays in sync without polling. No `groups`/`status` fields — a group has no failure state of its own to report.

## 10. Cache model

A DALI bus is slow (~1200 bps) and shared with other masters (DALI is explicitly multi-master, §6) — scanning every gear the way `hw-modbus-kit`'s `ScanCache` scans registers (07a §8) would congest it, not just waste cycles. So the update strategy inverts hw-modbus-kit's own default:

- **A successful `SET`'s own requested value is the cache update.** No read-back `QUERY ACTUAL LEVEL` round trip after a plain write — the bus transaction's own success is the confirmation, per the design note that started this section.
- **The raw traffic tap (§8) freshens the cache reactively, best-effort.** A `DaliBusTransaction` this driver recognizes as addressed to a known gear/group on that same bus (any origin) updates that field's cache the same way a `SET` would — this is how another controller's or a wall switch's change is ever seen at all, short of polling. A transaction never crosses buses: it only ever updates the cache of the bus it was actually observed on.
- **The one genuine background poll is sparse and narrow: `status` only**, on a `scheduleRepeating(clock, minutes, 'skip', ...)` cadence, per bus — lamp/ballast failure is the one thing neither a `SET`'s own success nor the traffic tap can ever surface, since nothing generates bus traffic for a lamp quietly failing on its own.
- **Staleness** (`05 §2`'s "no value yet ≠ value 0", carried over from `hw-modbus-kit`'s `polled` convention) means "never yet confirmed by any of the above," not "older than N seconds" — the same definition 07a §8 already settled on, just fed by different sources here.

### 10.1. Startup

For every gear/group `bindDevice`'d from KV-store on `configure()` (05a §3.6's replay), this driver **re-pushes** its last-known `intensity`/`fadeTime`/`fadeRate`/`groups`/etc. to its own bus — the same `SET` path a client call would take, not a passive cache repopulation — because the ballast, not just this process, may have restarted, and a plain reconciliation read (per §10's own reasoning) is exactly the expensive thing being avoided here.

## 11. Device management and commissioning

Listing is `$introspect`/`kit.list()` (05a §3.5) — never a bespoke method; a flattened endpoint table already says which buses exist and what each one has bound, so a second listing call would only duplicate it. Binding is dynamic, user-data-backed (05a §3.6, KV-store per 06): `saveDevice(busIndex, shortAddr, label?)` binds `bus.<busIndex>.gear.<shortAddr>`; `removeGear(busIndex, shortAddr)` unbinds it. Both persist immediately (keyed by `busIndex` alongside `shortAddr`), replayed at the next `configure()`.

Addressing workflow, `method`s on a single, non-bus-indexed `commissioning` tail (§7):

```ts
interface CommissioningSession { readonly initialisedAt: Date; /* + resumable search-address bounds */ }
// one per busIndex, held internally by this driver — never exposed as its own tail
```

Every method below takes `busIndex` as its first argument; an argument naming a bus this instance's own controller map (§3) doesn't have is `bad-payload`, before any transport call.

`discoverNextDevice(busIndex)` runs `initialise('unaddressed')` + `randomise()` on that bus only if no session is active for it or the active one's `initialisedAt` is older than the standard's own 15-minute `INITIALISE` validity (checked against this driver's own `Clock`, never a raw `Date.now()` comparison) — every other call resumes that bus's own `COMPARE`/`WITHDRAW` binary search on the random search address from where the previous call left it, returning the next lowest-address device found (or nothing, ending that bus's session with `terminate()` rather than waiting out the 15 minutes). It's a `method`, and a real candidate for `reportProgress` (03 §6.4) — a full narrowing pass is many bus round trips.

`setShortAddress(busIndex, addr)` runs `programShortAddress(addr)` then `verifyShortAddress(addr)` against the currently-`withdraw`n device from that bus's active session, then `withdraw()`s it to move on. If `bus.<busIndex>.gear.<addr>` is already `saveDevice`'d (a re-commissioned replacement reusing a known address), this immediately re-runs §10.1's startup reconciliation push for it — the newly-addressed hardware is not assumed to already match what the old one had.

`freeShortAddress(busIndex, addr)` — `setDtr(0xFF)` then, addressed to `addr` on that bus, `storeDtrAsShortAddress`. `freeAllShortAddresses(busIndex)` — the same pair, broadcast on that bus.

## 12. Testing

Tier 1, against a fixture `LineTransport`/`DaliController` (no hardware, no real serial port — 07b's own fixture, shared with `modbus-kit`'s tests):

- Frame constructors: every `sendTwice: true` constructor in §5.1's table sends exactly twice, gap-free, on the fixture transport's own call log; every other constructor sends exactly once.
- `off(t, {fade:false})` issues opcode `0x00` in command form, never a DAPC value-`0x00` frame; `off(t, {fade:true})` is the reverse.
- Instant nonzero `SET`: asserts exactly `enableDapcSequence → dapc` on the fixture transport's own call log — never the DTR dance — and that `fadeTime`'s own cached value is untouched by it.
- `DaliBusTransaction.observedAt` comes from a `FakeClock`, never real wall time — advancing the fake clock changes it deterministically.
- Answer classification: no `backward` at all, `backward.garbled`, and `backward.value` are three distinct, correctly-decoded fixture cases — never conflated (05 §2's rule, exercised here).
- Cache: a `SET`'s own success updates `@` with no fixture "read-back" call ever issued; a fixture traffic-tap transaction addressed to a known gear updates its cache the same way; `status`'s poll interval is the only recurring fixture-transport traffic in an otherwise idle test.
- Group propagation: a group `SET` updates every current member's own cache and emits per-member events; a later individual gear `SET` never retroactively changes the group's own sticky cache.
- Group aggregate `minLevel`/`maxLevel`: recomputed correctly as membership changes, rejected as a `SET` target (read-only).
- `up()`/`down()`/`stop()`: `dimming` transitions `'none'→'up'→'none'` correctly; a fixture gear already at `maxLevel` never issues a first `up()` frame at all; `stop()` mid-sequence issues exactly one `queryActualLevel` to reconcile.
- **Multi-bus:** a fixture `DaliControllerFactory` returning a 2-entry map binds `bus.0.raw`/`bus.1.raw` and each one's own `gear`/`group` tails independently; a fixture transaction observed on bus 0 never updates bus 1's cache, even addressed to the same short address.
- **`$health` aggregation:** bus 0 `degraded` + bus 1 `online` ⇒ this driver's own `$health` reports `degraded`; both `online` ⇒ `online`; `bus.<i>.raw.health` always reflects only its own bus's `DaliController`, never the aggregate.
- Commissioning: two sessions (one per `busIndex`) are tracked independently — a `discoverNextDevice(0)` mid-session never affects `discoverNextDevice(1)`'s own state; a `busIndex` not in the fixture's own bus map is rejected as `bad-payload` before any transport call, for every commissioning method; a second `discoverNextDevice(busIndex)` inside that bus's own 15-minute window issues no `initialise`/`randomise` frames, one issued after the fixture clock advances past it does; `setShortAddress` against an address already `saveDevice`'d triggers §10.1's reconciliation push, asserted via the fixture transport's call log.
- Startup reconciliation: a fixture gear restored from a KV fixture is re-pushed to its own bus's transport at `configure()`, not merely re-cached.
- `dali-foxtron-ASCII`: checksum computed and verified against the datasheet's own worked example (07's own precedent for citing a vendor example verbatim); type-11/13/14 correctly resolve `origin: 'self'`; type-5 sub-codes map onto the right `DaliBusHealth.detail`; `create()` always returns a one-entry map at `busIndex: 0`.

## 13. Open

- **DALI2** — 24-bit control-device forward frames (Part 103 and the 2xx device-type parts), memory-bank access, `ENABLE DEVICE TYPE x`.
- **Scenes** — `GO TO SCENE`/`STORE DTR AS SCENE`/`REMOVE FROM SCENE` are in `DaliFrames` (§5.1) but nothing binds them to a device field yet.
- **Colour (device type 8)** — Foxtron's own Modbus register map already models RGBWAF and Tc for a Modbus-mode gateway; a `dali-foxtron-modbus` controller kind would be the natural first consumer, not built here.
- **A Modbus-backed controller kind** — §4.2 states the transport seam and §3's `ReadonlyMap` return already accounts for one exposing several buses (§7.1's first worked example); no built-in controller exercises either yet.
- **A true 0ms snap** — `ENABLE DAPC SEQUENCE` (§9.2) gets a nonzero instant `SET` to a fixed 200ms fade, not an actual `fadeTime=0` transition; nothing in this document exposes the DTR-save/restore route to get a genuine 0ms snap, since no real use case has needed one yet over 200ms.
