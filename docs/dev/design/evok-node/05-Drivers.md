# 05 — Drivers

## 1. Scope

What every driver must be, whatever it talks to — the obligations that hold regardless of transport, and the concrete shape 01 §6 and 03 §5 leave open: how a driver actually builds and maintains its introspection table and binds endpoints to addresses. It assumes 01's two-kind model, 02's lifecycle and reload machinery, 03's envelope/addressing/introspection schema, and 04's common services; it does not restate them. 07 onward specialise this per transport class — Modbus, 1-Wire, the filesystem — and are the only place a transport's own data types belong.

## 2. What a driver is, and what it must never do

Three obligations, unconditional:

- **Never blocks the caller past its own answer.** A slow driver is a wedged driver, never proof the bus was slow this once (01 §8) — every wait already races a `Deadline` (04 §6).
- **Never throws across the boundary.** Expected failure is a `Response` value (03 §7) — for a `method` endpoint specifically, `onCall`'s own `CallOutcome` (§6.4) is how a handler produces one; a throw that escapes a handler is a bug driver-kit's dispatcher catches and reports as `internal-error`, never something a caller has to guard against.
- **A `reading`'s `GET` answers from memory, never from a live bus read.** This is what makes a timeout honest — the driver is genuinely wedged, not the bus slow this once. `CALL` is the deliberate exception: a method is an action, not a snapshot of held state, so touching the live device is the entire point of one. (`SET`'s own answer is always its declared type — `T`, or the narrower `TSet` when one's declared — never ambiguous; §6.1/§6.4 have the mechanism.)

**"No value yet" is not "value 0."** A reading carries `value`, `readAt`, and `stale` — an endpoint nothing has read yet must be representable as such, never defaulted quietly to zero or false. A client that can't tell "never read" from "read as zero" will eventually act on the wrong one; this is the failure mode research/04 documents repeatedly.

## 3. Lifecycle

Thin, deliberately: `configure`/`start`/`drain`/`stop` are 02 §4's, the two-phase startup barrier is 03 §9's. What this section adds is specific to a driver — what happens *inside* those calls is its own business (open a connection in `configure`, release it in `stop`), and there is no separate handshake/identify stage: whatever a driver needs to trust its own state before answering a request happens inside `configure`/`start` as ordinary logic, not a new lifecycle primitive.

`prepareReload` matters to exactly the drivers §7 is about: one holding something exclusive — a shared transport it arbitrates for others, a lock, a namespace — implements it to release precisely what the next config won't need, before commit ever begins. 02 §5.1 and 03 §9 already guarantee that ordering; this section only says which drivers need to act on it.

## 4. The scan loop — a best practice, not a contract

The right shape for a request/response bus with no push mechanism of its own — most of Modbus, most sensors — never a rule every driver must follow. A driver talking to something event-native has no scan loop and is not in violation of anything by lacking one.

Where a scan loop does apply, cadence, prioritization between fast and slow channels, and what falls behind first under load are guidance, not requirements this file enforces: `scheduleRepeating` (04 §5.2) with an explicit `overrunPolicy` is the mechanism; which channels get `'skip'` versus `'coalesce'`, and in what order a scan pass visits them, is each driver's own judgment about its own device. Reporting degradation, however it's reached, is `$health` (03 §3) — consumed like any other address, by whoever subscribes.

## 5. Using `driver-kit`, or building bare

What it buys: `bindDevice`/`unbindDevice` and the `$introspect` table they maintain, generic payload validation against a bound endpoint's own `Codec`, facet and wildcard resolution (§5b, §5c), the scan-scheduling helper if §4 applies. 03 §5 already covers the fallback — a driver not built on `driver-kit` answers `$introspect` itself, by hand, as ordinary `onRequest` logic; nothing about the address is privileged at the protocol level, only the convenience is. That trade is worth taking deliberately rather than by default: a driver with one endpoint and no interest in facets or wildcards gains little from the machinery and can reasonably skip it.

## 5a. Introspection payload

`driver-kit` is what fills in the rest of `IntrospectionBase` (03 §5) once `type: 'driver-kit'` is on it:

```ts
// @evok-node/driver-kit
interface DriverKitIntrospection extends IntrospectionBase {
  readonly type: 'driver-kit';
  readonly tailMode: 'opaque' | 'dottedAddressing';   // whatever this driver passed to onRequest (03 §4) — a consumer needs this before attempting a wildcard subscribe (§5c)
  readonly devices: readonly DeviceEntry[];           // every bound tail — a device with a single '@' field is how a lone endpoint is bound (§6.3), not a special wire case
}

interface DeviceEntry {
  readonly tail: Tail;
  readonly kind: string;    // the DeviceType's own kind (§6.3), resolved from its own manifest — every bound tail has one, even a single-field device
  readonly fields: Readonly<Record<string, FieldEntry>>;   // '@' present whenever the tail itself answers GET/SET/CALL with no suffix; a sibling field is addressed at `<tail>.<key>`
}

interface FieldEntry {
  readonly kind: string;                // resolves to the registered EndpointType (§6.4)
  readonly shape: 'reading' | 'channel' | 'method';
  readonly subscribe: boolean;
  readonly effect?: 'none' | 'mutates';   // method only
  readonly schema: ValueSchema;         // duplicated from the registered EndpointType (§6.1) — see below for why
  readonly setSchema?: ValueSchema;     // channel only, present iff the registered type has one
  readonly argsSchema?: ValueSchema;    // method only, present iff the registered type has one
}
```

```json
{
  "tail": "DI.01", "kind": "DI",
  "fields": {
    "@":        { "kind": "DI",          "shape": "reading", "subscribe": true,  "schema": { "type": "struct", "fields": { "value": {"type":"primitive","format":"bool"}, "counter": {"type":"primitive","format":"uint32"}, "readAt": {"type":"primitive","format":"timestamp"}, "stale": {"type":"primitive","format":"bool"} } } },
    "debounce": { "kind": "DI.debounce", "shape": "channel", "subscribe": false, "schema": { "type": "primitive", "format": "uint16", "unit": "ms" } }
  }
}
```
(`directSwitch` is absent above — an `optional()` field (§6.3) this particular binding didn't supply, same as a struct field simply not existing yet, §2's "no value yet" rule extended to a field that may never exist for this device at all.)

A device with a single `'@'` field and no siblings — 06's `get`, say — takes the identical shape:

```json
{ "tail": "get", "kind": "method.get", "fields": { "@": { "kind": "method.get", "shape": "method", "subscribe": false, "effect": "none", "schema": {"type":"primitive","format":"json"}, "argsSchema": {"type":"primitive","format":"json"} } } }
```

`shape`, `subscribe`, and `effect` travel on the wire alongside `schema`, not just its declarative data — enough of an `EndpointType`'s own contract to route a request correctly without resolving `kind` locally at all. The earlier reasoning for keeping them off the wire — "any consumer resolving `kind` already has, or can lazily get, that exact object" — only holds for a peer in the same running instance with manifest access (02 §4); it doesn't hold for a browser UI or a third-party API client that's never imported this plugin's package, which is exactly the consumer `schema` was already carried for. `Codec` itself — the actual `decode`/`encode`/`validate` — stays exactly as thin as before, resolved locally through `kind`, because a function genuinely cannot cross this boundary; only its declarative twin does (§6.1).

This isn't a wire-only normalization — `bindDevice()` (§6.4) is the only way to bind anything at all, so `$introspect`'s single `devices[]` list follows directly from what's actually bound, rather than needing to reconcile two binding primitives into one shape.

## 5b. Facets — an endpoint's own schema, addressed on its own

Any endpoint whose registered `EndpointType` has a `struct`/`array`/`union` `schema` (§6.1) is reachable, field by field, at `<tail>:<path>` — `path` a dot-joined walk of that schema, for `GET`/`subscribe` only. Nothing is declared for this to work: it falls straight out of `schema` itself, so `DI.01`'s `{value, counter, readAt, stale}` struct is automatically reachable at `DI.01:value`, `DI.01:counter`, and so on, with no opt-in list a driver author has to keep in sync with the struct's own fields — the old `facets?` allow-list is gone; the schema already says which fields exist. Nesting composes the same way: a struct field that is itself a struct is walked with another `.`, and a `union` schema is walked by its own `tag` first — `DO.01:mode` always resolves (it only projects the discriminant), while `DO.01:value.duty` resolves only while the endpoint's *current* value is actually the `pwm` variant; asking for it while set to `bool` answers `unknown-address` (03 §7), the same answer a path that never existed at all would get, because right now it genuinely doesn't exist. §6.3a works through this for a `channel`, not just a `reading` — a struct/union-shaped `channel`'s fields are just as facet-addressable as a `reading`'s; only `SET`/`CALL` are never facet-resolved, on either shape.

Resolution tries the literal address against the endpoint table first; only when nothing claims it exactly does the dispatcher split on the *last* colon and walk the remainder as a schema path against the base's registered `schema`. This ordering means a driver whose own opaque tail happens to contain a colon for unrelated reasons is never misread as a facet address — a facet address exists only where no real endpoint already claims it outright, and only where the walk actually lands on something the schema declares.

A facet `GET` calls the handler with the *base* address, gets the decoded value back, and projects the named path — the handler never sees that a facet was requested. A facet `subscribe` subscribes to the base address's own `emit` stream and projects the same path out of every snapshot delivered on it, so subscribing to `DI.01:value` alone still delivers an event whenever `DI.01` emits, whether or not `value` itself differs from the last snapshot — simple, and harmless given 03 §6.3's coalescing buffer already treats a superseded snapshot as free. **An event delivered on any address — base, facet, or a wildcard-matched concrete one — always has the same value-shape a fresh `GET` on that same address would return.**

## 5c. Wildcards — one family of endpoints, one subscription

A `subscribe` address may use `*` for exactly one dot-segment — `DI.*` matching `DI.01`, `DI.02`, … — allowed only for a driver that passed `tailMode: 'dottedAddressing'` to `onRequest` (03 §4), reported at `$introspect`'s own root (§5a) so a consumer knows before it tries. Nothing forces this grammar on a driver that hasn't opted in; an `opaque` driver's tails are exact-match-only for subscribe, same as always. On a wildcard `subscribe`, the dispatcher expands the pattern against the driver's *current* endpoint table, subscribes to each match, and remembers the pattern itself so a later topology-generation bump re-expands it — a newly matching endpoint joins automatically, a removed one drops, with no re-subscribe from the caller. `unsubscribe`/`listSubscriptions`/`$subscriptions` operate on the literal pattern the caller used, never the expansion. A facet suffix composes with a wildcard the same way it composes with any base address (`DI.*:value`) — expand the wildcard first, then resolve the facet on each match.

An event delivered through a wildcard subscription always carries the concrete address that actually changed (`Event.address`, 03 §2) — never the pattern. Matching a wildcard is the subscriber's own bookkeeping; the event shape doesn't need to represent it.

Subscribing to a `Device`'s own tail — the literal tail, or one reached through a wildcard match — subscribes to every subscribeable field of that device, not just `@`: `DI.*` matching `DI.01` picks up `DI.01`'s own `@` stream and its `debounce`-style siblings alike, each still delivered under its own concrete tail (`DI.01` for `@`, `DI.01.debounce` for a sibling) per this section's rule above — never the device's bare tail, never the pattern. Nothing new is needed for this: a device's fields are ordinary bound tails (§6.3), so it falls out of wildcard expansion exactly the way any other sibling tail already would.

## 6. Endpoint types and binding

### 6.1. `Codec<T>`, `ValueSchema`, and the three shapes

Every endpoint author writes against a paired unit, never a bare `Codec` — a runtime `Codec<T>` plus a `ValueSchema` describing it, so the two can never drift apart:

```ts
// @evok-node/module-sdk
interface Codec<T> {
  decode(wire: Value): T;
  encode(value: T): Value;
  validate(wire: Value): boolean;
}

interface TypedCodec<T> { readonly codec: Codec<T>; readonly schema: ValueSchema; }
type Infer<C> = C extends TypedCodec<infer T> ? T : never;

type PrimitiveFormat =
  | 'bool' | 'string' | 'bytes'
  | 'int8' | 'int16' | 'int32' | 'int64'
  | 'uint8' | 'uint16' | 'uint32' | 'uint64'
  | 'float32' | 'float64'
  | 'timestamp'          // uint32 epoch seconds on the wire — same convention as readAt below — decodes to Date
  | 'tlv8' | 'json';     // json is the closed vocabulary's own escape hatch — 06 is the first user

interface Semantics {
  readonly unit?: string;                            // 'mV' | 'uA' | '%' ... — descriptive only, never enforced by validate()
  readonly min?: number;
  readonly max?: number;
  readonly step?: number;
  readonly maxLength?: number;                       // string/bytes length, or array length
  readonly enumValues?: readonly (string | number)[];
  readonly scaler?: number;                          // engineering value = raw wire number * scaler; omitted ⇒ 1
}

type ValueSchema = PrimitiveSchema | ArraySchema | StructSchema | UnionSchema;

interface PrimitiveSchema extends Semantics { readonly type: 'primitive'; readonly format: PrimitiveFormat; }
interface ArraySchema     extends Semantics { readonly type: 'array'; readonly items: ValueSchema; }
interface StructSchema                      { readonly type: 'struct'; readonly fields: Readonly<Record<string, ValueSchema>>; }
interface UnionSchema                       { readonly type: 'union'; readonly tag: string; readonly variants: Readonly<Record<string, ValueSchema>>; }
```

`Semantics` is advisory only — `min`/`max`/`step`/`enumValues` are for a generic consumer to render a control correctly (§6.3a's `AO`/`DO`), never a second validation layer a driver author has to keep in sync with limits the hardware already enforces itself. `int64`/`uint64` decode to `bigint`, never `number`: `Value` (03 §2) has no `bigint` arm, so their wire form is a decimal string, the same JSON-safe shape as everything else on this boundary — `BigInt(str)` is the whole decode, no big-number library needed. `timestamp` costs nothing new either: it reuses `readAt`'s own existing epoch-seconds convention, just typed as `Date` instead of a raw number callers had to interpret themselves.

`Codecs` is the one place every leaf format and every combinator lives, so an endpoint author never hand-writes a `Codec` or a `ValueSchema` separately — illustrative only, the mechanical parts of the generics are elided the same way §6.3's `DeviceType` example elides them:

```ts
// @evok-node/module-sdk — illustrative only
const Codecs: {
  readonly bool: (s?: Semantics) => TypedCodec<boolean>;
  readonly string: (s?: Semantics) => TypedCodec<string>;
  readonly bytes: (s?: Semantics) => TypedCodec<Uint8Array>;
  readonly int8: (s?: Semantics) => TypedCodec<number>;
  readonly int16: (s?: Semantics) => TypedCodec<number>;
  readonly int32: (s?: Semantics) => TypedCodec<number>;
  readonly int64: (s?: Semantics) => TypedCodec<bigint>;
  readonly uint8: (s?: Semantics) => TypedCodec<number>;
  readonly uint16: (s?: Semantics) => TypedCodec<number>;
  readonly uint32: (s?: Semantics) => TypedCodec<number>;
  readonly uint64: (s?: Semantics) => TypedCodec<bigint>;
  readonly float32: (s?: Semantics) => TypedCodec<number>;
  readonly float64: (s?: Semantics) => TypedCodec<number>;
  readonly timestamp: (s?: Semantics) => TypedCodec<Date>;
  readonly tlv8: (s?: Semantics) => TypedCodec<Uint8Array>;
  readonly json: (s?: Semantics) => TypedCodec<unknown>;
  readonly void: TypedCodec<void>;   // a `method` with nothing meaningful to return on success
  struct<F extends Record<string, TypedCodec<unknown>>>(fields: F): TypedCodec<{ readonly [K in keyof F]: Infer<F[K]> }>;
  array<T>(items: TypedCodec<T>, s?: Semantics): TypedCodec<readonly T[]>;
  union<V extends Record<string, TypedCodec<unknown>>>(tag: string, variants: V): TypedCodec<UnionOf<V>>;   // UnionOf<V> tags each Infer<V[K]> with { [tag]: K } — mechanical, omitted here
};
```

`union`'s decoded value always carries the discriminant itself, merged in — `Codecs.union('mode', { voltage10: Codecs.struct({...}) })` decodes to `{mode: 'voltage10', ...}`, never a bare variant the caller has to re-tag by hand. §6.3a works through a full example. Every driver-declared value type comes from composing `Codecs`' members — never a bare object literal claiming a `schema` it doesn't back with a real `Codec`, and never a `Codec` written by hand without the matching `schema`. `bindDevice()` (§6.4) has no way to check the two agree; keeping them paired through `TypedCodec` rather than authored separately is what actually prevents drift, same tier of concern as `basics/02-Coding.md` §1.1's branding rule.

Three shapes, discriminated, each with its methods and `effect` fully implied rather than declared:

```ts
// @evok-node/module-sdk
interface ReadingType<T> {
  readonly shape: 'reading';       // GET (+SUBSCRIBE if `subscribe`); effect: 'none', implied
  readonly kind: string;           // must resolve in the endpoint manifest — §6.4
  readonly subscribe: boolean;
  readonly codec: Codec<T>;
  readonly schema: ValueSchema;    // §5a — carried into introspection, not just kept locally
}

interface ChannelType<T, TSet = T> {
  readonly shape: 'channel';       // GET+SET (+SUBSCRIBE if `subscribe`); effect: 'mutates', implied
  readonly kind: string;
  readonly subscribe: boolean;
  readonly codec: Codec<T>;
  readonly schema: ValueSchema;
  readonly setCodec?: Codec<TSet>;    // only when SET's payload/echo genuinely differs from T
  readonly setSchema?: ValueSchema;   // present iff setCodec is
}

interface MethodType<R, A = void, E extends string = never> {
  readonly shape: 'method';        // CALL only
  readonly kind: string;
  readonly effect: 'none' | 'mutates';   // the one shape where this still varies
  readonly resultCodec: Codec<R>;
  readonly resultSchema: ValueSchema;
  readonly argsCodec?: Codec<A>;    // omitted ⇒ no payload
  readonly argsSchema?: ValueSchema;  // present iff argsCodec is
  readonly errorKinds?: readonly E[];   // the closed, endpoint-owned vocabulary `onCall` (§6.4) may
                                         // resolve as `domainErrorKind` — absent ⇒ `E` is `never`, so
                                         // `CallOutcome`'s domain-error arm isn't constructible at all
                                         // for this endpoint. Not offered on `reading`/`channel` —
                                         // those answer from held state, which either exists or the
                                         // endpoint doesn't (03 §7's `unknown-address` already covers
                                         // that case); 06's `get` is the first user of this one.
}

type EndpointType<T = unknown, TSet = T, E extends string = never> = ReadingType<T> | ChannelType<T, TSet> | MethodType<T, TSet, E>;
```

A `channel`'s `SET` always returns exactly what it was given — `TSet` — never something narrower or nothing at all. A bus that can't confirm a write still trivially has the value it was just asked to set; that's what retires the old open question about write acknowledgement.

### 6.2. Building one without repeating the type

`T` is meant to come from the `codec` argument, inferred, so these interfaces are rarely written as raw object literals:

```ts
// @evok-node/module-sdk
function reading<T>(kind: string, codec: TypedCodec<T>, opts?: { subscribe?: boolean }): ReadingType<T>;
function channel<T, TSet = T>(kind: string, codec: TypedCodec<T>, opts?: { subscribe?: boolean; set?: TypedCodec<TSet> }): ChannelType<T, TSet>;
function method<R, A = void, E extends string = never>(kind: string, effect: 'none' | 'mutates', result: TypedCodec<R>, args?: TypedCodec<A>, opts?: { errorKinds?: readonly E[] }): MethodType<R, A, E>;
```

`channel('RO', Codecs.bool())` infers `ChannelType<boolean, boolean>` entirely from the second argument, `schema` included; nobody writes `<boolean>` or a schema literal anywhere.

### 6.3. `DeviceType<Fields>` — one tail, several fields, one registered kind

Some device concepts need more than one address to be themselves — a digital input reading paired with a separately-writable debounce `channel` is the recurring example, and `SET` is never facet-resolved (§5b), so debounce can't just be a field of the reading. A `Device` groups them under one tail as a single registered kind — reusable across drivers and transports, the same way an `EndpointType`'s own `kind` already is (§6.4). Most kinds don't need this; it exists only for the composite ones:

```ts
// @evok-node/module-sdk
interface DeviceType<Fields extends Record<string, EndpointType | OptionalEndpointType>> {
  readonly kind: string;    // resolves in the device manifest (§6.4) — fatal at bindDevice() if it doesn't
  readonly fields: Fields;  // '@' is the reserved root key, answering GET/SET/CALL on the device's own tail with no suffix; every other key is a sibling field, addressed at `<tail>.<key>`
}

function device<F extends Record<string, EndpointType | OptionalEndpointType>>(kind: string, fields: F): DeviceType<F>;
function optional<T extends EndpointType>(type: T): OptionalEndpointType<T>;   // marks a field a driver may leave unbound — §6.4
```

```ts
// di-device.ts — package.json-exposed, reusable by any driver that has this hardware shape
const DIDevice = device('DI', {
  '@':          reading('DI', Codecs.struct({ value: Codecs.bool(), counter: Codecs.uint32(), readAt: Codecs.timestamp(), stale: Codecs.bool() }), { subscribe: true }),
  debounce:     channel('DI.debounce', Codecs.uint16({ unit: 'ms' })),
  directSwitch: optional(channel('DI.directSwitch', Codecs.bool())),   // not every DI channel supports a forced override
});
```

Two rules a `device()` builder checks when the `DeviceType` itself is built, not only once some driver binds it — a `DeviceType` failing either is a packaging mistake, same tier as a `Codec`/`ValueSchema` mismatch (§6.1):

- `@`'s own `schema` is `struct`-shaped ⇒ none of its field names may collide with a sibling field's key. `DI.01:value` (a facet of `@`, §5b) and `DI.01.debounce` (a sibling field) are syntactically distinct addresses, but a `@` struct field and a sibling field sharing a name is confusing enough to reject outright.
- `@`'s own `schema` is `primitive`/`array`-shaped ⇒ the device may declare no sibling fields at all. A bare scalar/array `@` has nothing to group; a device wanting siblings needs a `struct` `@` — or no `@` at all, since a `DeviceType` isn't required to declare one.

`DI.01.debounce` addresses a sibling exactly like any other bound endpoint's tail — nothing new there; what's new is that it can no longer be bound loose, outside a `DeviceType`'s own declared fields, once something has claimed `DI.01` as a device (§6.4's fatal check).

A `Device` is mandatory, not an opt-in convenience: there is no separate way to bind a single, sibling-less endpoint. `device('AO', { '@': AO })` — one field, no fatal checks even relevant since there's nothing for `@` to collide with — is the normal shape for that case, not a special case kept around for the ergonomics of skipping this section. A `DeviceType` also isn't required to declare `'@'` at all: a device that's purely a bundle of siblings, with no single field answering the bare tail, is equally legal (07's raw Modbus function codes are the example — eight sibling fields, no root).

### 6.3a. One endpoint, several mutually exclusive shapes — `union`

Some devices genuinely change datatype depending on runtime state — an analog output wired for voltage or current but never both, a digital output that's either a plain bit or a PWM triple. The tail stays fixed either way — `ao1`, `do1` — because the physical channel is one thing regardless of mode; what varies is which arm of a `Codecs.union` is populated. Introspection (§5a) is unaffected by a mode change: it always describes the *whole* union, every variant it could ever take, because that is a static property of the registered `EndpointType`, resolved once through `kind` — never a per-instance, per-moment thing that would need re-announcing every time the mode flips. What a mode change actually changes is the *value* — plain `GET`/`subscribe` data, exactly the mechanism 03 §6.3 already has for anything else that changes.

```ts
// AO — one channel, three mutually exclusive value shapes
const AOValue = Codecs.union('mode', {
  voltage10:  Codecs.struct({ value: Codecs.uint16({ unit: 'mV', min: 0, max: 10_000, scaler: 1 }) }),
  voltage2_5: Codecs.struct({ value: Codecs.uint16({ unit: 'mV', min: 0, max: 2_500,  scaler: 1 }) }),
  current20:  Codecs.struct({ value: Codecs.uint16({ unit: 'uA', min: 4_000, max: 20_000, scaler: 1 }) }),
});
const AO = channel('AO', AOValue, { subscribe: true });

// DO — bool, or a PWM triple written as one unit (duty/prescaler/cycle are computed together — never three separate writes)
const PwmValue = Codecs.struct({
  duty:      Codecs.uint16({ min: 0, max: 65_535 }),
  prescaler: Codecs.uint16({ min: 0, max: 65_535 }),
  cycle:     Codecs.uint16({ min: 0, max: 65_535 }),
});
const DOValue = Codecs.union('mode', {
  bool: Codecs.struct({ value: Codecs.bool() }),
  pwm:  Codecs.struct({ value: PwmValue }),
});
const DO = channel('DO', DOValue, { subscribe: true });
```

Binding is one `bindDevice()` call, same as any other `channel` wrapped as a single-field device (§6.3) — no `unbind`/rebind dance when the mode changes, because it never stopped being the same endpoint:

```ts
const AODevice = device('AO', { '@': AO });
kit.bindDevice(tail, AODevice, {
  '@': {
    onGet: () => this.readCurrentModeAndValue(),                 // { mode: 'voltage10', value: 3200 }
    onSet: (v) => {
      if (v.mode !== this.hwMode) throw new RejectedPayload(`AO is in ${this.hwMode} mode`);   // §6.4
      this.writeHw(v.value);
      return v;
    },
  },
});
```

`$introspect` carries `AOValue`'s schema verbatim (§5a) — a generic consumer renders a mode-tagged control (a mode selector plus a bounded numeric field, unit and range read straight off the active variant) without knowing anything about this hardware:

```json
{
  "tail": "ao1", "kind": "AO",
  "schema": {
    "type": "union", "tag": "mode",
    "variants": {
      "voltage10":  { "type": "struct", "fields": { "value": { "type": "primitive", "format": "uint16", "unit": "mV", "min": 0, "max": 10000, "scaler": 1 } } },
      "voltage2_5": { "type": "struct", "fields": { "value": { "type": "primitive", "format": "uint16", "unit": "mV", "min": 0, "max": 2500,  "scaler": 1 } } },
      "current20":  { "type": "struct", "fields": { "value": { "type": "primitive", "format": "uint16", "unit": "uA", "min": 4000, "max": 20000, "scaler": 1 } } }
    }
  }
}
```

A live `GET`/`subscribe` value tells a client which arm is populated right now; `ao1:mode` (§5b) answers just the tag, for a consumer that only cares which mode is active and not the value. Mode itself is never settable independently of a value in this shape — SET always names both `mode` and the fields that mode needs, atomically, the same discipline §6.1's `channel` SET always had (return exactly `TSet`, never something narrower). A device whose mode change needs its own action distinct from writing a value — one with real switching latency, say — exposes that as a `method` instead (§6.1), never by making `mode` its own facet-writable field; §5b's facet mechanism stays `GET`/`subscribe`-only on every shape, no exception here.

### 6.4. `bindDevice`, `unbindDevice`, and the fatal duplicate

```ts
// @evok-node/driver-kit
interface BoundEndpoint<T, E extends string = never> {
  readonly tail: Tail;
  emit(value: T): void;
}

interface BoundEndpointInfo {
  readonly tail: Tail;
  readonly kind: string;
}

/** What `onCall` (only) resolves with — never the raw `Response` (03 §2), never a bare `T` either,
 * since a bare value has no room to say "this failed, but not as a bug." One arm per expected
 * outcome; `internal-error` is never constructed here — it's what driver-kit answers if the handler
 * throws instead of resolving (§2, and the paragraph below). */
type CallOutcome<R, E extends string = never> =
  | { readonly ok: true; readonly result: R }
  | { readonly ok: false; readonly kind: 'domain-error'; readonly domainErrorKind: E; readonly detail: string; readonly info?: unknown }
  | { readonly ok: false; readonly kind: 'unreachable' | 'timeout'; readonly detail: string; readonly info?: unknown };

interface BindHandlers<T, TSet, E extends string = never> {
  onGet?(req: Request): T | Promise<T>;
  onSet?(value: TSet, req: Request): TSet | Promise<TSet>;
  onCall?(payload: TSet, req: Request): Promise<CallOutcome<T, E>>;
}

interface DriverKit {
  bindDevice<F extends Record<string, EndpointType | OptionalEndpointType>>(
    tail: Tail,
    type: DeviceType<F>,
    handlers: { readonly [K in keyof F]?: BindHandlers<...> }   // one entry per field actually being bound; omit an optional() field entirely to leave it unbound
  ): { readonly [K in keyof F]?: BoundEndpoint<...> };
  unbindDevice(tail: Tail): void;
  list(): readonly BoundEndpointInfo[];          // every field of every bound device, flattened — '@' reported under the device's own tail, a sibling under `<tail>.<key>`
  find<T = unknown, E extends string = never>(tail: Tail): BoundEndpoint<T, E> | undefined;
  onGet<T>(ep: BoundEndpoint<T>, fn: (req: Request) => T | Promise<T>): void;
  onSet<T, TSet>(ep: BoundEndpoint<T>, fn: (value: TSet, req: Request) => TSet | Promise<TSet>): void;
  onCall<R, E extends string, A>(ep: BoundEndpoint<R, E>, fn: (payload: A, req: Request) => Promise<CallOutcome<R, E>>): void;
  attach(): void;                              // §6.7
}
```

`bindDevice` is the only way to bind anything — there is no separate `bind()` for a lone endpoint (§6.3: a single-`'@'`-field `DeviceType` is that case, not a special one). It's fatal in any of the following, all the same tier — a packaging or driver-author mistake, never a business-logic case worth degrading gracefully for:

- `type.kind` doesn't resolve in the device manifest.
- Any field's own `EndpointType.kind` doesn't resolve in the endpoint manifest (02 §4) — a cheap, local table lookup against the manifest every process gets at spawn (02 §6), checked per field before anything else happens. `channel`/`reading`/`method` (§6.2) produce an ordinary `EndpointType`, nothing more — the only way a driver author gets to bind one is if some package declared it as `kind: "endpoint"` in its own manifest entry, Unipi's own onboard I/O kinds included.
- A field declared without `optional()` (§6.3) is missing from `handlers`.
- The device's own `tail`, or any field's derived tail, duplicates one already bound — checked against the driver's own table only, never a global view, because addresses are driver-qualified and uniqueness is local by construction. This is the direct mitigation for the wrong-relay bug class research/04 documents: no purchasable Unipi device has enough channels of one type to reproduce the bank-stride half of that bug on hardware, so this assertion is the only thing that can still catch a wrong address table before it drives the wrong output. A driver assembling its own tails in a loop is exactly where this matters most — 07 has the concrete mitigation for Modbus's own register arithmetic.
- A second `bindDevice()` call whose tail falls inside an already-bound device's own tail — `DI.01.<anything>` once `DI.01` is a device — but isn't one of that device's declared field keys. A device's namespace is closed once bound; nothing else may graft onto it.

A `DeviceType` gaining a new required field in a later package version is, by the third rule above, a breaking change for anything still calling `bindDevice` without it — there's no separate versioning mechanism; the same fatal check just starts firing for drivers that haven't caught up. Wrapping a newly-added field in `optional()` instead keeps old callers working unchanged.

`unbindDevice` tears down whatever the dispatcher was holding for the device's own tail — every field, active subscriptions included, the same discipline `$getCallProgress.<id>` already applies to itself the moment its own call resolves (03 §6.4) — and bumps the introspection generation (§6.7) the same way `bindDevice` does.

Every handler's final argument is the `Request` it's answering — `origin`, `deadline`, `id`, the lot — for a handler that genuinely needs more than its own payload; 06's `get`/`has`/`set`/`delete` are the first to use it, reading `origin` to resolve a caller's namespace. A handler that doesn't need it just doesn't declare the parameter; nothing about the type requires touching it.

`handlers` on `bindDevice()` is sugar for the three `on*` calls below it, per field, nothing more — wiring at bind time is convenient when nothing else is going on, but `onGet`/`onSet`/`onCall` still exist on their own for wiring a field after the fact, or from a driver's own `configure()` rather than at the `bindDevice()` call site itself. A handler that doesn't match its field's own shape — `onSet` against a `reading` field, say — is a driver bug driver-kit rejects at `bindDevice()` time, the same `reportFatal` path as a duplicate `tail`, not a silent no-op.

One narrow exception to `onGet`/`onSet` never throwing (§2): a handler may throw `RejectedPayload(detail)` (from `driver-kit`) specifically to answer `bad-payload` for a structurally valid write its own business state can't accept right now. A `union`-shaped channel's SET naming a mode the device isn't currently in (§6.3a) is the motivating case — `Codec.validate` is stateless and can check the payload is *some* known variant but never which one this particular binding currently allows, so that check can only happen inside the handler. Driver-kit's dispatcher recognizes exactly this one thrown type and answers `bad-payload`, never `internal-error`; anything else thrown from `onGet`/`onSet` is still a bug, unchanged from §2.

`onCall`'s three `CallOutcome` shapes are the entire expected-failure channel for a `method` endpoint (§2's "never throws," restated at this layer): resolving `{ok:true, result}` answers a success `Response`; resolving `{ok:false, kind:'domain-error', domainErrorKind, ...}` answers `Response.ok:false, kind:'domain-error'` with that same `domainErrorKind` — driver-kit checks it against the endpoint's own declared `errorKinds` (§6.1) first, and a value outside that set is treated exactly like a handler-shape mismatch above: a driver bug, reported as `internal-error` rather than trusted, since it's data-dependent and can't be caught at `bindDevice()` time the way a shape mismatch can; resolving `{ok:false, kind:'unreachable'|'timeout', ...}` answers that `Response` kind directly, with no `domainErrorKind` — the one place a handler picks a built-in, non-`domain-error` kind itself, because whether the device answered *this* call is exactly the handler's own, synchronous knowledge (03 §7). A handler that actually throws is unchanged from §2: driver-kit's dispatcher catches it, answers `internal-error`, and logs and counts it — nothing above is something the handler opts into, it's the only way any of these three outcomes reach the wire.

`list`/`find` are driver-kit's own registry, already necessary internally for `$introspect` and for `unbindDevice`'s teardown — exposed so a driver doesn't keep a second, parallel map of what it's already told `bindDevice` about. What `list`/`find` can't replace is a driver's own business data attached to a tail (a DALI ballast's label, say) that was never part of the endpoint table to begin with.

### 6.5. Dynamic binding is user data, not config

Binding or unbinding an endpoint at runtime — in response to a `CALL`, say, rather than at `configure` — means whatever drove that decision has to survive a restart on its own; the endpoint table itself is never persisted, it's rebuilt by replaying whatever caused it. That "whatever" is user data (01 §2), the same category as an alias or a group, and belongs in the KV-store driver's own namespace for this driver (06) — reloaded at `configure`, written back on every change. 06 has the mechanism; this is only the reminder that a driver doing this has somewhere to put it.

### 6.6. REMOVED

Superseded by `DeviceType`/`bindDevice` (§6.3/§6.4): grouping is no longer a cosmetic prefix stamped onto otherwise-ordinary endpoints, it's a registered kind with a closed field set. A driver builds a device's own tail the same way it builds any other tail — `tail(...)`/`extendTail(...)` (03 §2) — and passes it straight to `bindDevice`.

### 6.7. `attach()` — the one `onRequest`

```ts
attach(): void;
```

No arguments — `createDriverKit(ctx)` already closed over `ctx` at construction. This is the one moment `ctx.messaging.onRequest(...)` is actually called, once, after every `bindDevice()` a driver wants at startup; facet resolution (§5b) and wildcard resolution (§5c) both live inside this same dispatcher, never reimplemented per driver. It also raises the driver's own introspection `generation` on every `bindDevice`/`unbindDevice` and emits it on `$introspect` — `SUBSCRIBE`-able for exactly this, 03 §5a — so a client watching for new endpoints never has to poll.

### 6.8. REMOVED

## 7. Sharing a driver-owned resource

01 §7's pattern, restated at the level a driver author actually acts on it: a resource one driver owns — a transport, a namespace — can be shared by other drivers that reach it through the owner's own request/response messaging, never by opening a second client on it themselves. The owning driver's own config says nothing about this on a dependent's behalf; the dependent declares the link itself (02 §4, 03 §8), and its own config carries whatever extra context the relationship needs — its address on that transport, say.

What the owner exposes for this is, so far, one recurring shape: a set of `CALL` endpoints mirroring the underlying protocol's own operations one-to-one, each declared with whatever `effect` that operation actually has — so a dependent can speak the protocol directly rather than the owner having to anticipate every device that might ever share it. 07 has the concrete shape for Modbus: eight methods, one per function code, rather than a single generic query/command pair — precise enough that a caller picks the exact wire operation instead of the transport guessing.

## 8. REMOVED

## 9. Testing

Tier 1 (unit; `basics/03-Testing.md`), against `driver-kit`'s own fixtures — a minimal fixture driver with a handful of registered endpoint kinds, no real transport:

- Facet resolution (§5b): `GET`/a `subscribe`d facet projects correctly, including a nested struct path and a union's `tag`; a literal address that collides with a real endpoint is never facet-resolved; a union facet path that doesn't match the endpoint's *current* variant answers `unknown-address`, not a stale or default value.
- Wildcard resolution (§5c): a `DI.*` subscription picks up a fixture endpoint added after subscribing (a topology-generation bump) and drops one removed, with no re-subscribe from the caller; rejected outright against a fixture driver that never passed `tailMode: 'dottedAddressing'`.
- `bindDevice()`'s checks (§6.4): a fixture single-`'@'`-field `DeviceType` whose field `kind` isn't in the endpoint manifest is fatal at `bindDevice()`, before `attach()`, and independently a `DeviceType` whose own `kind` isn't in the device manifest is fatal; a duplicate `tail` is fatal independently of whether either `kind` resolves.
- Introspection payload (§5a): `$introspect` on a fixture driver returns `{driverId, driverTypeName, type: 'driver-kit', tailMode, devices}`, each `DeviceEntry` exactly `tail`/`kind`/`fields`, each `FieldEntry` exactly `kind`/`shape`/`subscribe`/`effect?`/`schema`/`setSchema?`/`argsSchema?`; a fixture device with a single `'@'` field and no siblings still appears as an ordinary `DeviceEntry` — assert `codec`/`setCodec`/`argsCodec`/`resultCodec` themselves never leak onto the wire, only their serializable counterparts do.
- `RejectedPayload` (§6.4): a fixture `onSet` throwing it answers `bad-payload`, never `internal-error`; any other thrown error from `onGet`/`onSet` still answers `internal-error`, unchanged.
- `DeviceType`/`bindDevice` (§6.3/§6.4): a `struct`-shaped `@` whose field name collides with a sibling field is rejected when the `DeviceType` is built, before any driver binds it; a `primitive`/`array`-shaped `@` declared alongside any sibling field is rejected the same way; a required field missing from `bindDevice`'s `handlers` is fatal, while the same `DeviceType` binds successfully with only some `optional()` fields supplied; a second `bindDevice()` whose tail falls inside an already-bound device's namespace, outside its declared fields, is fatal; both handles from one `bindDevice()` call are independently addressable, and `unbindDevice`ing the device's own tail doesn't silently leave a sibling field bound.
- Wildcard over a device (§5c): a `DI.*` subscription against a fixture device with `@` plus one subscribeable sibling field delivers events for both, each carrying its own concrete tail, never the device's bare tail or the pattern.
