# 12 — DALI driver

## 1. Scope

Package: `packages/driver-dali` (`@evok-node/driver-dali`). Config `type: dali`.

Everything DALI-bus-specific goes here: pluggable controller backends, raw frame construction, the stored gear/group model, discovery. It depends on `driver-kit` (05a), the KV-store driver's client (06) for persisted gears/groups (05a §3.6), `line-kit` (new package, §4) for serial/TCP byte transport, and optionally `modbus-kit`'s `ModbusTransport` (07 §4/§7) for a Modbus-backed controller.

Out of scope for v1, stated once here rather than per-section: DALI2 control-device frames (24-bit, IEC 62386-103/2xx), scenes, colour control (device type 8), memory-bank access. §12 lists these; nothing below silently half-supports them.

## 2. Configuration

```ts
interface DaliConfig {
  daliCtrlKind: string;                 // resolves a DaliControllerFactory — §3
  transport: DaliTransportConfig;       // §4
  ctrl?: unknown;                       // opaque here — validated only by the resolved factory's own schema
}

type DaliTransportConfig =
  | { kind: 'serial'; path: string; baudRate: number; dataBits?: 7|8; stopBits?: 1|2; parity?: 'none'|'even'|'odd' }
  | { kind: 'tcp'; host: string; port: number }
  | { kind: 'modbus'; modbus: ModbusTransportConfig | { relay: Tail } };   // 07 §4/§7 — no built-in controller uses this yet, §4.2
```

```yaml
drivers:
  DALI1:
    type: dali
    daliCtrlKind: dali-foxtron-ASCII
    transport: { kind: serial, path: /dev/ttyUSB0, baudRate: 19200, dataBits: 8, stopBits: 1, parity: even }
    ctrl: {}                                 # dali-foxtron-ASCII needs nothing extra — its own schema says so
```

Same two-schema sequencing 02 §5 step 4 already uses for a whole driver's body, one level deeper: `main` validates `DaliConfig` itself (`daliCtrlKind`/`transport` known here, `ctrl` opaque); this driver's own `configure()` then resolves `daliCtrlKind` (§3) and validates `ctrl` against that factory's own `schema`. A `ctrl` that doesn't parse, or a `transport.kind` the resolved factory doesn't declare support for (§3's `acceptsTransport`), is fatal at `configure()` — same tier as an unresolvable `daliCtrlKind` itself.

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
  onTraffic(cb: (t: DaliBusTransaction) => void): void;   // every transaction observed, ours or not — §7
  health(): DaliBusHealth;                                // pull — seeds $health's initial value, answerable on demand
  onHealth(cb: (h: DaliBusHealth) => void): void;         // push — a controller with no spontaneous fault reporting just never calls this
}

interface DaliControllerFactory<Config> {
  readonly ctrlKind: string;
  readonly schema: ZodType<Config>;
  readonly acceptsTransport: readonly ('serial'|'tcp'|'modbus')[];
  create(transport: LineTransport | ModbusTransport, config: Config, deps: { clock: Clock; log: Logger }): DaliController;
}
```

Registered one of two ways, same duality as `modbus-kind-binder` (07a §7): direct, `registerCtrl(factory)`, for a controller known at this package's own build time — `dali-foxtron-ASCII` (§6) uses this; manifest, the `package.json` shape above, resolved lazily via `ctx.plugins.resolve('dali-controller', ctrlKind)`, memoized the same way every other kind is (02 §4). `isDaliControllerFactory` is registered as `'dali-controller'`'s own guard at this package's module-load time, same shape as `isModbusKindBinder` (07a §7).

`DaliBusExceptionKind` is this driver's own closed `domain-error` vocabulary (03 §7) for a transmission the controller itself refuses or can't complete — `'bus-collision-unresolved' | 'buffer-full' | 'controller-error'` — distinct from `'unreachable'`/`'timeout'`, which cover the controller or line simply not answering at all.

## 4. Transport

### 4.1. `line-kit` — a new, protocol-agnostic package

`@evok-node/line-kit`. One small interface, two implementations, no framing of its own — framing is every consumer's own job (Foxtron's SOH/checksum/ETB here, Modbus's own framing in `modbus-kit`):

```ts
// @evok-node/line-kit
type LineTransportConfig =
  | { kind: 'serial'; path: string; baudRate: number; dataBits?: 7|8; stopBits?: 1|2; parity?: 'none'|'even'|'odd' }
  | { kind: 'tcp'; host: string; port: number };

interface LineTransport {
  open(): Promise<void>;
  close(): Promise<void>;
  write(bytes: Uint8Array): Promise<void>;
  onData(cb: (bytes: Uint8Array) => void): void;
  health(): LineHealth;   // connected/reconnecting/closed — never protocol-aware
}

function createLineTransport(config: LineTransportConfig, deps: { clock: Clock; log: Logger }): LineTransport;
```

Serial is `serialport`, wrapped, never raw (07 §2's "wrap, don't reinvent" reasoning, generalized past Modbus); TCP is a plain `net.Socket`. A reconnect supervisor with backoff is this package's own job for both — the one piece of behaviour every consumer would otherwise reimplement identically.

This is also where `modbus-kit`'s own RTU transport (07 §3) now gets its serial port from, landing in the same change as this document: `modbus-kit` depends on `line-kit` for the raw byte pipe and keeps only what's genuinely Modbus-specific on top — the RX-flush subclassing (07 §2) moves to wrap `line-kit`'s own serial implementation rather than `serialport` a second, independent time, and t3.5 pacing/the per-line mutex/deadline enforcement stay exactly where 07 §2 already puts them. 07 §2/§3 are amended accordingly; nothing about `ModbusTransport`'s own public interface (07 §4) changes.

### 4.2. Modbus-backed controllers

For a `daliCtrlKind` whose `acceptsTransport` includes `'modbus'`: this driver obtains a `ModbusTransport` exactly the two ways 07 §7 already provides — `createModbusTransport` (owns the line outright) or `createRelayModbusTransport` (shares another driver's `MODBUS_RAW`). No built-in controller uses this yet (§12); it exists so a future Modbus-mode DALI gateway's own `DaliControllerFactory` has a real transport to build against without this driver reinventing Modbus.

## 5. The frame model

Fixed 16-bit DALI (Part 102) only — no DALI2 24-bit control-device frames yet (§12).

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
  dapc(t: DaliAddress, level: number): DaliFrame,                          // 1-254; level 0 is off(), never dapc(t,0) — §8.2
  off(t: DaliAddress, opts?: { fade?: boolean }): DaliFrame,               // fade ⇒ false (default): opcode 0x00, immediate; true: DAPC value 0x00, fades to min then off
  up(t)/down(t)/stepUp(t)/stepDown(t)/recallMaxLevel(t)/recallMinLevel(t): DaliFrame,
  enableDapcSequence(t: DaliAddress): DaliFrame,                          // opcode 0x09 — forces a fixed 200ms fade for the DAPC(s) that follow, self-expiring; sendTwice: false — §8.2
  goToScene(t, scene: number): DaliFrame,                                  // 0-15 — §12
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
function queryGroups(t: DaliAddress): DaliQuery<readonly number[]>;   // issues both QUERY GROUPS 0-7/8-15 internally (§9), decodes to a plain array — never a bitmask on this side of the boundary
```

## 6. Built-in controller: `dali-foxtron-ASCII`

Foxtron DALI232/DALI232e/DALInet/DALI2net, ASCII protocol (their own "Communication protocol", not their Modbus RTU mode — that would be a `modbus`-backed `ctrlKind`, §4.2, not this one).

Framing: `SOH (0x01) | data (ASCII hex pairs) | checksum (ASCII hex pair) | ETB (0x17)`; checksum is the two's-complement of the data bytes' sum mod 256. Message types used: `11`/`13`/`14` (sender-differentiated send/receive) in preference to `1`/`3`/`4` — the only way `DaliBusTransaction.origin` can distinguish `'self'` from `'other'` rather than falling back to `'unknown'`. Type `5` (bus fault/mains/buffer/checksum/invalid-command) maps directly onto `DaliBusHealth.detail`. Serial: 19200 baud, 8 data bits, even parity, 1 stop bit, DTR held on (this converter is DTR-powered — a controller without external power needs it; `line-kit`'s serial config doesn't manage DTR itself, so this controller sets it directly on open). TCP (`DALInet`/`DALI2net`): identical ASCII messages over a plain socket, port 23 (bus 1) or 24 (bus 2) — no separate framing, confirming `line-kit`'s "one byte pipe, protocol decides framing" split was the right cut.

## 7. Raw bus access

```ts
export const DALI_RAW = device('dali-kit.raw', {
  send: method('send', 'mutates', DaliBusTransactionCodec, DaliFrameCodec, { errorKinds: DALI_BUS_EXCEPTION_KINDS }),
  traffic: reading('dali-kit.traffic', DaliBusTransactionCodec, { subscribe: true }),   // GET = last observed transaction (memory, legal per 05 §2); subscribe = every one since
});
```

No `health` field here (unlike `MODBUS_RAW`'s ninth field, 07 §6) — DALI is one bus with one health signal, not Modbus's per-slave breaker, so it's exactly what the reserved `$health` address (03 §3) already is: this driver relays `controller.health()` there once at `start()` (seeding it) and `controller.onHealth()` afterward, and a client reads or subscribes it the same way it would any other driver's `$health` — no bespoke device needed to re-expose it.

## 8. Stored gears and groups

### 8.1. `DaliGear` — `gear.<0-63>`

`@`'s own schema can't be primitive once siblings exist (05a §3.3) — so intensity lives inside a one-field struct, not bare:

```ts
const DaliGear = device('DALI.gear', {
  '@':            channel('DALI.gear.level', Codecs.struct({ intensity: Codecs.uint8({ min: 0, max: 254 }) }), { subscribe: true, set: DaliLevelSetCodec }),
  fadeTime:       channel('DALI.gear.fadeTime', Codecs.uint8({ min: 0, max: 15 })),
  fadeRate:       channel('DALI.gear.fadeRate', Codecs.uint8({ min: 0, max: 15 })),
  minLevel:       channel('DALI.gear.minLevel', Codecs.uint8()),
  maxLevel:       channel('DALI.gear.maxLevel', Codecs.uint8()),
  powerOnLevel:       channel('DALI.gear.powerOnLevel', Codecs.uint8()),
  systemFailureLevel: channel('DALI.gear.systemFailureLevel', Codecs.uint8()),
  groups:         channel('DALI.gear.groups', Codecs.array(Codecs.uint8({ min: 0, max: 15 }))),   // array of group numbers, never a bitmask — SET diffs old vs new into ADD/REMOVE-GROUP
  status:         reading('DALI.gear.status', DaliStatusBitsCodec, { subscribe: true }),           // lamp/ballast failure — the one field the sparse poll exists for, §9
  dimming:        reading('DALI.gear.dimming', Codecs.enum(['up', 'down', 'none']), { subscribe: true }),
});
// same tail, method fields:
//   up()/down(): starts a repeating command — §8.3
//   stop(): cancels it
```

`DaliLevelSetCodec = Codecs.struct({ intensity: Codecs.uint8({min:0,max:254}), instant: Codecs.bool() })` — `instant` omitted ⇒ `false`.

### 8.2. `intensity` — 0 is categorically off, never "a low level"

`intensity: 0` and `minLevel` are different things (a ballast's configured floor is never `0` in practice, and `1..254` is "on" regardless of where it sits relative to `minLevel`). `SET({intensity: 0, instant})` maps to `off(t, {fade: !instant})` — immediate `OFF` (opcode `0x00`) when `instant`, DAPC-fade-to-min-then-off otherwise. `SET({intensity: n > 0, instant})` maps to `dapc(t, n)` directly when `!instant`; when `instant`, it's `enableDapcSequence(t)` → `dapc(t, n)` — the gear uses a fixed 200ms fade for this DAPC regardless of its configured `fadeTime`, and the override expires on its own 200ms later, so there's nothing to restore and no failure mode where a botched write leaves `fadeTime` wrong. `fadeTime`'s own configured value (§8.1's `fadeTime` channel) is never touched by an `instant` write. This is 200ms, not a true 0ms snap — the only way to get an actual instant transition is `fadeTime=0` itself, which is what the DALI standard's own fade-time scale calls "no fade"; that's a real fallback (`setDtr(0)` → `storeDtrAsFadeTime(t)` ×2 → `dapc` → restore ×2, the DTR-save/restore dance) but not the default, since `ENABLE DAPC SEQUENCE` covers the practical "instant-ish" case at a sixth of the cost and none of the restore risk (§12 leaves the true-0ms case open).

A successful `SET`'s own requested value is written straight into the cache — §9 says why a read-back isn't needed. `status`'s own `lampPowerOn` bit is the one thing that can disagree with a `SET` that reported success (the ballast refused for a reason the bus transaction itself can't see, e.g. a burnt-out lamp) — that disagreement surfaces through `status`, never by second-guessing `@`.

### 8.3. `up`/`down`/`stop`/`dimming`

`UP`/`DOWN` are each a single ~200ms ramp-and-stop, not a continuous action (per the standard's own timing) — continuous dimming is this driver re-issuing the same command back-to-back. `up()`/`down()` starts a `scheduleRepeating(clock, 200ms, 'skip', ...)` loop that keeps sending the same command until: `stop()` is called, or the gear's own cached intensity (updated from each iteration — there's no backward frame for `UP`/`DOWN`, so a `queryActualLevel` runs once the loop actually stops, never mid-loop) reaches `maxLevel` (`up`) or `minLevel` (`down` — `DOWN` never crosses into off, matching §8.2's off/minLevel split). `dimming` reflects `'up'|'down'|'none'` for exactly as long as the loop runs, emitted on every transition.

### 8.4. `DaliGroup` — `group.<0-15>`, all 16 always bound

Mirrors `DaliGear`'s `@`/`fadeTime`/`fadeRate`/`up`/`down`/`stop`/`dimming` exactly. Differs in two ways: `minLevel`/`maxLevel` are `reading`-only here (never `channel`) — computed live as the lowest `minLevel`/highest `maxLevel` over the group's own current members, never written through this field directly (a group-addressed `STORE DTR AS MIN/MAX LEVEL` is still reachable via `DALI_RAW.send` if genuinely needed — this convenience field just isn't how). And a group's own `@`/`fadeTime`/`fadeRate` cache is **sticky**: set only by a direct write to the group, never re-derived from a member's own later, individually-addressed change — but the reverse direction does propagate: a successful group `SET` writes the same value into every current member gear's own cache too (from `groups`, §8.1) and emits for each, so a client watching one gear stays in sync without polling. No `groups`/`status` fields — a group has no failure state of its own to report.

## 9. Cache model

A DALI bus is slow (~1200 bps) and shared with other masters (§3's Multimaster) — scanning every gear the way `hw-modbus-kit`'s `ScanCache` scans registers (07a §8) would congest it, not just waste cycles. So the update strategy inverts hw-modbus-kit's own default:

- **A successful `SET`'s own requested value is the cache update.** No read-back `QUERY ACTUAL LEVEL` round trip after a plain write — the bus transaction's own success is the confirmation, per the design note that started this section.
- **The raw traffic tap (§7) freshens the cache reactively, best-effort.** A `DaliBusTransaction` this driver recognizes as addressed to a known gear/group (any origin) updates that field's cache the same way a `SET` would — this is how another controller's or a wall switch's change is ever seen at all, short of polling.
- **The one genuine background poll is sparse and narrow: `status` only**, on a `scheduleRepeating(clock, minutes, 'skip', ...)` cadence — lamp/ballast failure is the one thing neither a `SET`'s own success nor the traffic tap can ever surface, since nothing generates bus traffic for a lamp quietly failing on its own.
- **Staleness** (`05 §2`'s "no value yet ≠ value 0", carried over from `hw-modbus-kit`'s `polled` convention) means "never yet confirmed by any of the above," not "older than N seconds" — the same definition 07a §8 already settled on, just fed by different sources here.

### 9.1. Startup

For every gear/group `bindDevice`'d from KV-store on `configure()` (05a §3.6's replay), this driver **re-pushes** its last-known `intensity`/`fadeTime`/`fadeRate`/`groups`/etc. to the bus — the same `SET` path a client call would take, not a passive cache repopulation — because the ballast, not just this process, may have restarted, and a plain reconciliation read (per §9's own reasoning) is exactly the expensive thing being avoided here.

## 10. Device management and commissioning

Listing is `$introspect`/`kit.list()` (05a §3.5) — never a bespoke method, per the same reasoning 17's memo already gives generic introspection credit for. Binding is dynamic, user-data-backed (05a §3.6, KV-store per 06): `saveDevice(shortAddr, label?)` binds `gear.<shortAddr>`; `removeGear(shortAddr)` unbinds it. Both persist immediately, replayed at the next `configure()`.

Addressing workflow, `method`s on a `commissioning` tail:

```ts
interface CommissioningSession { readonly initialisedAt: Date; /* + resumable search-address bounds */ }
```

`discoverNextDevice()` runs `initialise('unaddressed')` + `randomise()` only if no session is active or the active one's `initialisedAt` is older than the standard's own 15-minute `INITIALISE` validity (checked against this driver's own `Clock`, never a raw `Date.now()` comparison) — every other call resumes the `COMPARE`/`WITHDRAW` binary search on the random search address from where the previous call left it, returning the next lowest-address device found (or nothing, ending the session with `terminate()` rather than waiting out the 15 minutes). It's a `method`, and a real candidate for `reportProgress` (03 §6.4) — a full narrowing pass is many bus round trips.

`setShortAddress(addr)` runs `programShortAddress(addr)` then `verifyShortAddress(addr)` against the currently-`withdraw`n device from the active session, then `withdraw()`s it to move on. If `gear.<addr>` is already `saveDevice`'d (a re-commissioned replacement reusing a known address), this immediately re-runs §9.1's startup reconciliation push for it — the newly-addressed hardware is not assumed to already match what the old one had.

`freeShortAddress(addr)` — `setDtr(0xFF)` then, addressed to `addr`, `storeDtrAsShortAddress`. `freeAllShortAddresses()` — the same pair, broadcast.

## 11. Testing

Tier 1, against a fixture `LineTransport`/`DaliController` (no hardware, no real serial port — `line-kit`'s own fixture, shared with `modbus-kit`'s tests once §4.1's migration lands):

- Frame constructors: every `sendTwice: true` constructor in §5.1's table sends exactly twice, gap-free, on the fixture transport's own call log; every other constructor sends exactly once.
- `off(t, {fade:false})` issues opcode `0x00` in command form, never a DAPC value-`0x00` frame; `off(t, {fade:true})` is the reverse.
- Instant nonzero `SET`: asserts exactly `enableDapcSequence → dapc` on the fixture transport's own call log — never the DTR dance — and that `fadeTime`'s own cached value is untouched by it.
- `DaliBusTransaction.observedAt` comes from a `FakeClock`, never real wall time — advancing the fake clock changes it deterministically.
- Answer classification: no `backward` at all, `backward.garbled`, and `backward.value` are three distinct, correctly-decoded fixture cases — never conflated (05 §2's rule, exercised here).
- Cache: a `SET`'s own success updates `@` with no fixture "read-back" call ever issued; a fixture traffic-tap transaction addressed to a known gear updates its cache the same way; `status`'s poll interval is the only recurring fixture-transport traffic in an otherwise idle test.
- Group propagation: a group `SET` updates every current member's own cache and emits per-member events; a later individual gear `SET` never retroactively changes the group's own sticky cache.
- Group aggregate `minLevel`/`maxLevel`: recomputed correctly as membership changes, rejected as a `SET` target (read-only).
- `up()`/`down()`/`stop()`: `dimming` transitions `'none'→'up'→'none'` correctly; a fixture gear already at `maxLevel` never issues a first `up()` frame at all; `stop()` mid-sequence issues exactly one `queryActualLevel` to reconcile.
- Commissioning: a second `discoverNextDevice()` inside the 15-minute window issues no `initialise`/`randomise` frames; one issued after the fixture clock advances past it does; `setShortAddress` against an address already `saveDevice`'d triggers §9.1's reconciliation push, asserted via the fixture transport's call log.
- Startup reconciliation: a fixture gear restored from a KV fixture is re-pushed to the transport at `configure()`, not merely re-cached.
- `dali-foxtron-ASCII`: checksum computed and verified against the datasheet's own worked example (07's own precedent for citing a vendor example verbatim); type-11/13/14 correctly resolve `origin: 'self'`; type-5 sub-codes map onto the right `DaliBusHealth.detail`.

## 12. Open

- **DALI2** — 24-bit control-device forward frames (Part 103 and the 2xx device-type parts), memory-bank access, `ENABLE DEVICE TYPE x`.
- **Scenes** — `GO TO SCENE`/`STORE DTR AS SCENE`/`REMOVE FROM SCENE` are in `DaliFrames` (§5.1) but nothing binds them to a device field yet.
- **Colour (device type 8)** — Foxtron's own Modbus register map already models RGBWAF and Tc for a Modbus-mode gateway; a `dali-foxtron-modbus` controller kind would be the natural first consumer, not built here.
