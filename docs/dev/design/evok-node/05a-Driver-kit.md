# 05a — Driver-kit

## 1. Scope

`driver-kit` — the package most drivers build on top of the contract 05 states: `bindDevice`/`unbindDevice` and the `$introspect` table they maintain, generic payload validation against a bound endpoint's own `Codec`, wildcard resolution, and `attach()`, the one `onRequest` a driver built on it ever calls. No generic scan-scheduling helper — see §2. It assumes 05's driver contract, 03's envelope/addressing/introspection schema, and 04's common services; it does not restate them.

## 2. Using `driver-kit`, or building bare

What it buys: `bindDevice`/`unbindDevice` and the `$introspect` table they maintain, generic payload validation against a bound endpoint's own `Codec`, wildcard resolution (§6). No generic scan-scheduling helper yet — that turned out to be transport-specific enough that `hw-modbus-kit` (design/07a) owns its own rather than this file guessing at a shared shape before a second scan-based driver exists to correct it against; revisit once one does. 03 §5 already covers the fallback — a driver not built on `driver-kit` answers `$introspect` itself, by hand, as ordinary `onRequest` logic; nothing about the address is privileged at the protocol level, only the convenience is. That trade is worth taking deliberately rather than by default: a driver with one endpoint and no interest in wildcards gains little from the machinery and can reasonably skip it.

## 3. Endpoint types and binding

### 3.1. `Codec<T>`, `ValueSchema`, and the three shapes

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

`Semantics` is advisory only — `min`/`max`/`step`/`enumValues` are for a generic consumer to render a control correctly (§3.4's `AO`/`DO`), never a second validation layer a driver author has to keep in sync with limits the hardware already enforces itself. `int64`/`uint64` decode to `bigint`, never `number`: `Value` (03 §2) has no `bigint` arm, so their wire form is a decimal string, the same JSON-safe shape as everything else on this boundary — `BigInt(str)` is the whole decode, no big-number library needed. `timestamp` costs nothing new either: it reuses `readAt`'s own existing epoch-seconds convention, just typed as `Date` instead of a raw number callers had to interpret themselves.

`Codecs` is the one place every leaf format and every combinator lives, so an endpoint author never hand-writes a `Codec` or a `ValueSchema` separately — illustrative only, the mechanical parts of the generics are elided the same way §3.3's `DeviceType` example elides them:

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

`union`'s decoded value always carries the discriminant itself, merged in — `Codecs.union('mode', { voltage10: Codecs.struct({...}) })` decodes to `{mode: 'voltage10', ...}`, never a bare variant the caller has to re-tag by hand. §3.4 works through a full example. Every driver-declared value type comes from composing `Codecs`' members — never a bare object literal claiming a `schema` it doesn't back with a real `Codec`, and never a `Codec` written by hand without the matching `schema`. `bindDevice()` (§3.5) has no way to check the two agree; keeping them paired through `TypedCodec` rather than authored separately is what actually prevents drift.

Three shapes, discriminated, each with its methods and `effect` fully implied rather than declared:

```ts
// @evok-node/module-sdk
interface ReadingType<T> {
  readonly shape: 'reading';       // GET (+SUBSCRIBE if `subscribe`); effect: 'none', implied
  readonly subscribe: boolean;
  readonly codec: Codec<T>;
  readonly schema: ValueSchema;    // §4 — carried into introspection, not just kept locally
}

interface ChannelType<T, TSet = T> {
  readonly shape: 'channel';       // GET+SET (+SUBSCRIBE if `subscribe`); effect: 'mutates', implied
  readonly subscribe: boolean;
  readonly codec: Codec<T>;
  readonly schema: ValueSchema;
  readonly setCodec?: Codec<TSet>;    // only when SET's payload/echo genuinely differs from T
  readonly setSchema?: ValueSchema;   // present iff setCodec is
}

interface MethodType<R, A = void, E extends string = never> {
  readonly shape: 'method';        // CALL only
  readonly effect: 'none' | 'mutates';   // the one shape where this still varies
  readonly resultCodec: Codec<R>;
  readonly resultSchema: ValueSchema;
  readonly argsCodec?: Codec<A>;    // omitted ⇒ no payload
  readonly argsSchema?: ValueSchema;  // present iff argsCodec is
  readonly errorKinds?: readonly E[];   // the closed, endpoint-owned vocabulary `onCall` (§3.5) may
                                         // resolve as `domainErrorKind` — absent ⇒ `E` is `never`, so
                                         // `CallOutcome`'s domain-error arm isn't constructible at all
                                         // for this endpoint. Not offered on `reading`/`channel` —
                                         // those answer from held state, which either exists or the
                                         // endpoint doesn't (03 §7's `unknown-address` already covers
                                         // that case); 06's `get` is the first user of this one.
}

type EndpointType<T = unknown, TSet = T, E extends string = never> = ReadingType<T> | ChannelType<T, TSet> | MethodType<T, TSet, E>;
```

A `channel`'s `SET` always returns exactly what it was given — `TSet` — never something narrower or nothing at all. A bus that can't confirm a write still trivially has the value it was just asked to set.

### 3.2. Building one without repeating the type

`T` is meant to come from the `codec` argument, inferred, so these interfaces are rarely written as raw object literals:

```ts
// @evok-node/module-sdk
function reading<T>(codec: TypedCodec<T>, opts?: { subscribe?: boolean }): ReadingType<T>;
function channel<T, TSet = T>(codec: TypedCodec<T>, opts?: { subscribe?: boolean; set?: TypedCodec<TSet> }): ChannelType<T, TSet>;
function method<R, A = void, E extends string = never>(effect: 'none' | 'mutates', result: TypedCodec<R>, args?: TypedCodec<A>, opts?: { errorKinds?: readonly E[] }): MethodType<R, A, E>;
```

`channel(Codecs.bool())` infers `ChannelType<boolean, boolean>` entirely from its argument, `schema` included; nobody writes `<boolean>` or a schema literal anywhere.

### 3.3. `DeviceType<Fields>` — one tail, several fields, one registered kind

Some device concepts need more than one address to be themselves — a digital input reading paired with a separately-writable debounce `channel` is the recurring example, and a `reading` has no `SET` at all (§3.1), so debounce can't just be a field of the reading. A `Device` groups them under one tail as a single registered kind — reusable across drivers and transports (§3.5). Most kinds don't need this; it exists only for the composite ones:

```ts
// @evok-node/module-sdk
interface DeviceType<Fields extends Record<string, EndpointType | OptionalEndpointType>> {
  readonly kind: string;    // resolves against a kind: "device" manifest entry's own deviceKind (§3.5) — fatal at bindDevice() if it doesn't resolve, or if the resolved module's own kind disagrees
  readonly fields: Fields;  // '@' is the reserved root key, answering GET/SET/CALL on the device's own tail with no suffix; every other key is a sibling field, addressed at `<tail>.<key>`
}

function device<F extends Record<string, EndpointType | OptionalEndpointType>>(kind: string, fields: F): DeviceType<F>;
function optional<T extends EndpointType>(type: T): OptionalEndpointType<T>;   // marks a field a driver may leave unbound — §3.5
```

```ts
// di-device.ts — package.json-exposed, reusable by any driver that has this hardware shape
const DIDevice = device('DI', {
  '@':          reading(Codecs.struct({ value: Codecs.bool(), counter: Codecs.uint32(), readAt: Codecs.timestamp(), stale: Codecs.bool() }), { subscribe: true }),
  debounce:     channel(Codecs.uint16({ unit: 'ms' })),
  directSwitch: optional(channel(Codecs.bool())),   // not every DI channel supports a forced override
});
```

One rule a `device()` builder checks when the `DeviceType` itself is built, not only once some driver binds it — a `DeviceType` failing it is a packaging mistake, same tier as a `Codec`/`ValueSchema` mismatch (§3.1):

- `@`'s own `schema` is `primitive`/`array`-shaped ⇒ the device may declare no sibling fields at all. A bare scalar/array `@` has nothing to group; a device wanting siblings needs a `struct` `@` — or no `@` at all, since a `DeviceType` isn't required to declare one.

`DI.01.debounce` addresses a sibling exactly like any other bound endpoint's tail — nothing new there; what's new is that it can no longer be bound loose, outside a `DeviceType`'s own declared fields, once something has claimed `DI.01` as a device (§3.5's fatal check).

A `Device` is mandatory, not an opt-in convenience: there is no separate way to bind a single, sibling-less endpoint. `device('AO', { '@': AO })` — one field, no fatal checks even relevant since there's nothing for `@` to collide with — is the normal shape for that case, not a special case kept around for the ergonomics of skipping this section. A `DeviceType` also isn't required to declare `'@'` at all: a device that's purely a bundle of siblings, with no single field answering the bare tail, is equally legal (07's raw Modbus function codes are the example — eight sibling fields, no root).

### 3.4. One endpoint, several mutually exclusive shapes — `union`

Some devices genuinely change datatype depending on runtime state — an analog output wired for voltage or current but never both, a digital output that's either a plain bit or a PWM triple. The tail stays fixed either way — `ao1`, `do1` — because the physical channel is one thing regardless of mode; what varies is which arm of a `Codecs.union` is populated. Introspection (§4) is unaffected by a mode change: it always describes the *whole* union, every variant it could ever take, because that is a static property of the `DeviceType`'s own field — never a per-instance, per-moment thing that would need re-announcing every time the mode flips. What a mode change actually changes is the *value* — plain `GET`/`subscribe` data, exactly the mechanism 03 §6.3 already has for anything else that changes.

```ts
// AO — one channel, three mutually exclusive value shapes
const AOValue = Codecs.union('mode', {
  voltage10:  Codecs.struct({ value: Codecs.uint16({ unit: 'mV', min: 0, max: 10_000, scaler: 1 }) }),
  voltage2_5: Codecs.struct({ value: Codecs.uint16({ unit: 'mV', min: 0, max: 2_500,  scaler: 1 }) }),
  current20:  Codecs.struct({ value: Codecs.uint16({ unit: 'uA', min: 4_000, max: 20_000, scaler: 1 }) }),
});
const AO = channel(AOValue, { subscribe: true });

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
const DO = channel(DOValue, { subscribe: true });
```

Binding is one `bindDevice()` call, same as any other `channel` wrapped as a single-field device (§3.3) — no `unbind`/rebind dance when the mode changes, because it never stopped being the same endpoint:

```ts
const AODevice = device('AO', { '@': AO });
kit.bindDevice(tail, AODevice, {
  '@': {
    onGet: () => this.readCurrentModeAndValue(),                 // { mode: 'voltage10', value: 3200 }
    onSet: (v) => {
      if (v.mode !== this.hwMode) throw new RejectedPayload(`AO is in ${this.hwMode} mode`);   // §3.5
      this.writeHw(v.value);
      return v;
    },
  },
});
```

`$introspect` carries `AOValue`'s schema verbatim (§4) — a generic consumer renders a mode-tagged control (a mode selector plus a bounded numeric field, unit and range read straight off the active variant) without knowing anything about this hardware:

```json
{
  "tail": "ao1", "kind": "AO",
  "fields": {
    "@": {
      "shape": "channel", "subscribe": true,
      "schema": {
        "type": "union", "tag": "mode",
        "variants": {
          "voltage10":  { "type": "struct", "fields": { "value": { "type": "primitive", "format": "uint16", "unit": "mV", "min": 0, "max": 10000, "scaler": 1 } } },
          "voltage2_5": { "type": "struct", "fields": { "value": { "type": "primitive", "format": "uint16", "unit": "mV", "min": 0, "max": 2500,  "scaler": 1 } } },
          "current20":  { "type": "struct", "fields": { "value": { "type": "primitive", "format": "uint16", "unit": "uA", "min": 4000, "max": 20000, "scaler": 1 } } }
        }
      }
    }
  }
}
```

A live `GET`/`subscribe` value tells a client which arm is populated right now — reading `mode` off the decoded value is the only way to check it, since there's no field-level address (§4); a consumer that only cares which mode is active still gets the whole value back and reads `mode` out of it itself. Mode itself is never settable independently of a value in this shape — SET always names both `mode` and the fields that mode needs, atomically, the same discipline §3.1's `channel` SET always had (return exactly `TSet`, never something narrower). A device whose mode change needs its own action distinct from writing a value — one with real switching latency, say — exposes that as a `method` instead (§3.1), never by making `mode` independently settable.

### 3.5. `bindDevice`, `unbindDevice`, and the fatal duplicate

```ts
// @evok-node/module-sdk
interface BoundEndpoint<T, E extends string = never> {
  readonly tail: Tail;
  emit(value: T): void;
}

interface BoundDevice<F extends Record<string, EndpointType | OptionalEndpointType> = Record<string, EndpointType>> {
  readonly tail: Tail;
  readonly kind: string;                                              // DeviceType.kind
  readonly fields: { readonly [K in keyof F]?: BoundEndpoint<...> };  // only fields actually bound — an unbound optional() field is absent
}

/** What `onCall` (only) resolves with — never the raw `Response` (03 §2), never a bare `T` either,
 * since a bare value has no room to say "this failed, but not as a bug." One arm per expected
 * outcome; `internal-error` is never constructed here — it's what driver-kit answers if the handler
 * throws instead of resolving (§2, and the paragraph below). Lives in `module-sdk`, not `driver-kit`,
 * because `RemoteMethod` (§3.8a) resolves with it too, on the consumer side of a link this package
 * never runs on. */
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
  ): BoundDevice<F>;
  unbindDevice(tail: Tail): void;
  resolveDeviceKind(kind: string): Promise<DeviceType>;    // for a driver that only has a string, e.g. a definition-declared kind it never imported directly — see below
  list(): readonly BoundDevice[];                // one entry per bound device
  find<F extends Record<string, EndpointType | OptionalEndpointType>>(tail: Tail, type: DeviceType<F>): BoundDevice<F> | undefined;   // kind-checked, typed — see below
  find(tail: Tail): BoundDevice | undefined;    // untyped
  onGet<T>(ep: BoundEndpoint<T>, fn: (req: Request) => T | Promise<T>): void;
  onSet<T, TSet>(ep: BoundEndpoint<T>, fn: (value: TSet, req: Request) => TSet | Promise<TSet>): void;
  onCall<R, E extends string, A>(ep: BoundEndpoint<R, E>, fn: (payload: A, req: Request) => Promise<CallOutcome<R, E>>): void;
  attach(): void;                              // §3.8
  remote<E extends EndpointType>(address: Address, field: E): RemoteEndpoint<E>;                                                       // sugar over module-sdk's own remote(ctx, ...) — §3.8a
  remoteDevice<F extends Record<string, EndpointType | OptionalEndpointType>>(address: Address, type: DeviceType<F>): RemoteDevice<F>;  // sugar over remoteDevice(ctx, ...) — §3.8a
}
```

`bindDevice` itself stays synchronous, and still takes an already-resolved `DeviceType` — resolving one from a bare `kind` string is always a separate, earlier step, never something `bindDevice` does on a caller's behalf. Most drivers never need that step: `07a`'s own built-in kinds (`unipi.di`, `unipi.ao`, …) are `import`ed directly, the same way `DIDevice` above is, and go straight into `bindDevice` with no resolution at all. `resolveDeviceKind(kind)` exists for the other case — a `kind` string with no compile-time import behind it, known only from a definition or a plugin's own runtime data (`07a`'s generic walk, resolving a YAML feature's `kind`, is the concrete caller). It's a thin wrapper over `ctx.plugins.resolve('device', kind)` (02 §4, 03 §9), and this is where `isDeviceType` actually lives — registered once, against `PluginRegistry`'s `'device'` kind, at `driver-kit`'s own module-load time, before any instance built on it can call either method:

```ts
// @evok-node/module-sdk, module-load time, once
// Duck-typed, same reasoning as isModuleDescriptor (02 §4): a plugin may bundle its own
// copy of module-sdk's types, and there's no `instanceof` to rely on across that boundary.
function isDeviceType(mod: unknown, deviceKind: string): DeviceType {
  if (typeof mod !== 'object' || mod === null
      || typeof (mod as DeviceType).kind !== 'string'
      || typeof (mod as DeviceType).fields !== 'object' || (mod as DeviceType).fields === null) {
    throw new Error(`type "${deviceKind}": not a valid DeviceType`);
  }
  if ((mod as DeviceType).kind !== deviceKind) {
    throw new Error(`type "${deviceKind}": exported DeviceType.kind is "${(mod as DeviceType).kind}"`);
  }
  return mod as DeviceType;
}
pluginRegistry.registerKindGuard('device', isDeviceType);
```

`bindDevice` is the only way to bind anything — there is no separate `bind()` for a lone endpoint (§3.3: a single-`'@'`-field `DeviceType` is that case, not a special one). It's fatal in any of the following, all the same tier — a packaging or driver-author mistake, never a business-logic case worth degrading gracefully for:

- `type.kind` doesn't resolve in the device manifest — a cheap, local table lookup against the `deviceKind → {path, export}` table every process gets at spawn (02 §6) — or the object `bindDevice` was actually handed fails the same `isDeviceType` check above. This is `bindDevice`'s own, independent re-check — it runs unconditionally, whether `type` arrived by direct import or by an earlier `resolveDeviceKind` call, because a direct import never goes through `resolveDeviceKind` at all and still needs catching if it's wrong. It's the same `isDeviceType` function above, called directly rather than through `PluginRegistry` — `bindDevice` already has the object in hand, so there's nothing to `import()`, only the guard's own shape/`kind`-agreement check left to run:

  ```ts
  isDeviceType(type, type.kind);   // throws synchronously on shape mismatch — bindDevice lets it propagate, unchanged
  ```

  This is the only registration check at this tier — a field's own `EndpointType` needs no separate declaration; it arrives already resolved as part of the `DeviceType` that owns it.
- A field declared without `optional()` (§3.3) is missing from `handlers`.
- The device's own `tail`, or any field's derived tail, duplicates one already bound — checked against the driver's own table only, never a global view, because addresses are driver-qualified and uniqueness is local by construction. This is the direct mitigation for the wrong-relay bug class research/04 documents: no purchasable Unipi device has enough channels of one type to reproduce the bank-stride half of that bug on hardware, so this assertion is the only thing that can still catch a wrong address table before it drives the wrong output. A driver assembling its own tails in a loop is exactly where this matters most — 07 has the concrete mitigation for Modbus's own register arithmetic.
- A second `bindDevice()` call whose tail falls inside an already-bound device's own tail — `DI.01.<anything>` once `DI.01` is a device — but isn't one of that device's declared field keys. A device's namespace is closed once bound; nothing else may graft onto it.
- A `DeviceType` whose `kind` is already bound in this driver under a different `DeviceType` object. One kind is one schema for the life of the process: `$introspect` writes each kind's schema once (§4), so two objects claiming the same kind could disagree. A 07a alias binder is unaffected — it binds the real `DeviceType` and reports the real kind.

A `DeviceType` gaining a new required field in a later package version is, by the second rule above, a breaking change for anything still calling `bindDevice` without it — there's no separate versioning mechanism; the same fatal check just starts firing for drivers that haven't caught up. Wrapping a newly-added field in `optional()` instead keeps old callers working unchanged.

`unbindDevice` tears down whatever the dispatcher was holding for the device's own tail — every field, active subscriptions included, the same discipline `$getCallProgress.<id>` already applies to itself the moment its own call resolves (03 §6.4) — and bumps the introspection generation (§3.8) the same way `bindDevice` does.

Every handler's final argument is the `Request` it's answering — `origin`, `deadline`, `id`, the lot — for a handler that genuinely needs more than its own payload; 06's `get`/`has`/`set`/`delete` are the first to use it, reading `origin` to resolve a caller's namespace. A handler that doesn't need it just doesn't declare the parameter; nothing about the type requires touching it.

`handlers` on `bindDevice()` is sugar for the three `on*` calls below it, per field, nothing more — wiring at bind time is convenient when nothing else is going on, but `onGet`/`onSet`/`onCall` still exist on their own for wiring a field after the fact, or from a driver's own `configure()` rather than at the `bindDevice()` call site itself. A handler that doesn't match its field's own shape — `onSet` against a `reading` field, say — is a driver bug driver-kit rejects at `bindDevice()` time, the same `reportFatal` path as a duplicate `tail`, not a silent no-op.

One narrow exception to `onGet`/`onSet` never throwing (§2): a handler may throw `RejectedPayload(detail)` (from `driver-kit`) specifically to answer `bad-payload` for a structurally valid write its own business state can't accept right now. A `union`-shaped channel's SET naming a mode the device isn't currently in (§3.4) is the motivating case — `Codec.validate` is stateless and can check the payload is *some* known variant but never which one this particular binding currently allows, so that check can only happen inside the handler. Driver-kit's dispatcher answers it `bad-payload`, never `internal-error`.

A second exception, just as narrow: an `onSet` that forwards the write to a source it doesn't own — another driver's device (§3.8a), a networked device — throws `SourceUnreachable(detail)` (from `driver-kit`) when that source can't take the write now. The dispatcher answers `unreachable` (03 §7), never `internal-error`. The write is never queued for later: replaying it once the source returns could act on a state someone has changed meanwhile. These two are the only thrown types the dispatcher recognizes; anything else thrown from `onGet`/`onSet` is still a bug, unchanged from §2.

`onCall`'s three `CallOutcome` shapes are the entire expected-failure channel for a `method` endpoint (§2's "never throws," restated at this layer): resolving `{ok:true, result}` answers a success `Response`; resolving `{ok:false, kind:'domain-error', domainErrorKind, ...}` answers `Response.ok:false, kind:'domain-error'` with that same `domainErrorKind` — driver-kit checks it against the endpoint's own declared `errorKinds` (§3.1) first, and a value outside that set is treated exactly like a handler-shape mismatch above: a driver bug, reported as `internal-error` rather than trusted, since it's data-dependent and can't be caught at `bindDevice()` time the way a shape mismatch can; resolving `{ok:false, kind:'unreachable'|'timeout', ...}` answers that `Response` kind directly, with no `domainErrorKind` — the one place a handler picks a built-in, non-`domain-error` kind itself, because whether the device answered *this* call is exactly the handler's own, synchronous knowledge (03 §7). A handler that actually throws is unchanged from §2: driver-kit's dispatcher catches it, answers `internal-error`, and logs and counts it — nothing above is something the handler opts into, it's the only way any of these three outcomes reach the wire.

`list`/`find` work per device, never per field — a field handle is reached through its device, `kit.find(tail, DIDevice)?.fields.debounce?.emit(50)`; a field's own tail is `` key === '@' ? tail : `${tail}.${key}` ``. `find` on a field tail answers `undefined`. The typed `find(tail, type)` checks the bound device's `kind` against `type.kind`; a mismatch is a driver bug and throws, never a silent cast. `list`/`find` are driver-kit's own registry, already necessary internally for `$introspect` and for `unbindDevice`'s teardown — exposed so a driver doesn't keep a second, parallel map of what it's already told `bindDevice` about. What `list`/`find` can't replace is a driver's own business data attached to a tail (a DALI ballast's label, say) that was never part of the endpoint table to begin with.

### 3.5a. Multi-field GET/SET: `options.returnFields`

A device's own tail answers `GET`/`SET` for `'@'` alone (§3.3); `returnFields` is how a caller folds one or more sibling fields' current values into that same round trip instead of issuing one request per field:

```ts
// @evok-node/module-sdk
type ReturnFields = readonly string[] | '*';   // 03 §2's Request.options, narrowed to this one key
function getReturnFields(req: Request): ReturnFields | undefined;   // throws RejectedPayload(detail) on a malformed options.returnFields (§3.5) — never silently ignored
```

Semantics, enforced by `attach()`'s dispatcher (§3.8) identically for every `driver-kit`-built driver:

- `GET`/`SET` only — `options.returnFields` on `CALL`/`SUBSCRIBE`/`UNSUBSCRIBE` is `bad-payload`, since nothing there interprets it.
- An explicit array is strict: every named key must exist on the bound device and must support the method being answered — naming a field that doesn't exist, or a `CALL`-only field, is `bad-payload`, never a silently dropped entry.
- `'*'` resolves dynamically against the device's *current* table to every GET-able field, never failing the whole request over an unrelated `CALL`-only sibling the way an explicit array naming it would.
- On `SET`, a named sibling is read-only in the response: driver-kit echoes its current value, it never routes any part of the `SET` payload to it. `'@'` remains the only field actually written.
- Response shape: with no `returnFields`, `Response.body` is exactly today's bare `'@'` value, unchanged. With `returnFields` present (array or `'*'`), `Response.body` becomes `Readonly<Record<string, Value>>` — one key per returned field, `'@'` included when the device has one, each already decoded to that field's own `schema` shape.
- A device with no `'@'` (§3.3 permits one): its bare tail answers `GET` only with `returnFields`, and the body holds the named fields alone. A `GET` without `returnFields`, or any `SET`, on that tail is `unknown-address` — nothing lives there. `RemoteDevice.getFields`/`getAll` (§3.8a) depend on this; 12a's device types, which never declare `'@'`, are the first users.

### 3.6. Dynamic binding is user data, not config

Binding or unbinding an endpoint at runtime — in response to a `CALL`, say, rather than at `configure` — means whatever drove that decision has to survive a restart on its own; the endpoint table itself is never persisted, it's rebuilt by replaying whatever caused it. That "whatever" is user data (01 §2), the same category as an alias or a group, and belongs in the KV-store driver's own namespace for this driver (06) — reloaded at `configure`, written back on every change. 06 has the mechanism; this is only the reminder that a driver doing this has somewhere to put it.

### 3.7. REMOVED

### 3.8. `attach()` — the one `onRequest`

```ts
attach(): void;
```

No arguments — `createDriverKit(ctx)` already closed over `ctx` at construction. This is the one moment `ctx.messaging.onRequest(...)` is actually called, once, after every `bindDevice()` a driver wants at startup; wildcard resolution (§6) lives inside this same dispatcher, never reimplemented per driver. It also owns the driver's introspection `Generation` (03 §5a): `epoch` made once, in memory, by `createDriverKit(ctx)`; `n` raised by one on every `bindDevice`/`unbindDevice`, and each change emitted on `$introspect` as a `DriverKitChange` (§4) — so a client watching for new endpoints never has to poll.

**Change log.** driver-kit keeps the last 16 table changes in memory, one entry per `bindDevice`/`unbindDevice`, and answers `GET $introspect` with `options.since` (03 §5a) from it:

```ts
since.epoch !== epoch  → full
n - since.n > 16       → full     // older than the log
since.n > n            → full     // can't happen within one epoch; full is the safe answer
otherwise              → change from since to now: entries since.n+1 … n merged per tail, last one wins
```

16 is a constant, not config. A gap longer than that is a bulk change — a commissioning run, a reload — where `full` costs about the same as a merged change. `options.since` on any other address or method, or not a well-formed `Generation`, is `bad-payload`, enforced the same way as `returnFields` (§3.5a).

### 3.8a. Reaching another driver: `RemoteEndpoint`/`RemoteDevice`

`bindDevice`/`BoundDevice` (§3.5) is the producer side of a link — a real `emit()` closing over this driver's own handler. The other end of 03 §10's socket never gets to hold one of those; something reading or calling across to another driver's endpoint needs a handle that only ever talks over `ctx.messaging` (03 §9), never a local function reference. `RemoteEndpoint`/`RemoteDevice` are that handle, typed off the exact same `EndpointType`/`DeviceType` the producer bound against — the consumer-side mirror of §3.1's and §3.3's shapes, not a new vocabulary:

```ts
// @evok-node/module-sdk
interface RemoteReading<T> {
  readonly address: Address;
  get(deadline?: Deadline): Promise<T>;
  subscribe(onChange: (value: T) => void): () => void;   // unsubscribe
}

interface RemoteChannel<T, TSet = T> extends RemoteReading<T> {
  set(value: TSet, deadline?: Deadline): Promise<TSet>;
}

interface RemoteMethod<R, A = void, E extends string = never> {
  readonly address: Address;
  call(args: A, deadline?: Deadline): Promise<CallOutcome<R, E>>;
}

type RemoteEndpoint<E extends EndpointType> =
  E extends ReadingType<infer T> ? RemoteReading<T> :
  E extends ChannelType<infer T, infer TSet> ? RemoteChannel<T, TSet> :
  E extends MethodType<infer R, infer A, infer Err> ? RemoteMethod<R, A, Err> :
  never;

function remote<E extends EndpointType>(ctx: InstanceContext, address: Address, field: E): RemoteEndpoint<E>;
```

`RemoteEndpoint<E>` is conditional on `E`'s own shape, not one flat interface with a `set()` that throws at runtime for a `reading` — the same reasoning as `BindHandlers` rejecting a shape mismatch at `bindDevice()` time (§3.5), just caught on the other side of the link: a `reading`'s consumer handle has no `set` to call at all, a compile error, never a runtime one. `field` is always the same `EndpointType` value the producing driver bound against — imported directly or reached through its `DeviceType`, never redeclared by the consumer, so there's nowhere for the two sides to disagree about its shape.

`get`/`set`/`call` sit above `ctx.messaging.get`/`set`/`call` (03 §4), decoding `Response.body` through `field`'s own `codec` (§3.1) and surfacing a failed response as the matching `CallOutcome` arm or a rejected promise — never a blind `as`. `subscribe` is sugar over `ctx.messaging.subscribe`, decoding each `Event.value` the same way. None of this depends on `driver-kit`, `ctx.plugins`, or anything else specific to a driver process — `remote` takes a bare `InstanceContext`, so an api reaches another driver's endpoint exactly the way a driver does (01 §9).

A whole device, typed against its `DeviceType` rather than field by field:

```ts
// @evok-node/module-sdk
type Unwrap<T> = T extends OptionalEndpointType<infer U> ? U : T extends EndpointType ? T : never;
type GetResult<E extends EndpointType> = E extends ReadingType<infer T> | ChannelType<infer T, any> ? T : never;   // never for a method field — nothing to GET

interface RemoteDevice<F extends Record<string, EndpointType | OptionalEndpointType>> {
  readonly address: Address;
  readonly fields: { readonly [K in keyof F]: RemoteEndpoint<Unwrap<F[K]>> };
  get(deadline?: Deadline): Promise<GetResult<Unwrap<F['@']>>>;                                                                    // shortcut for fields['@'].get() — a compile error when F has no '@', never a runtime one
  getFields<K extends keyof F>(keys: readonly K[], deadline?: Deadline): Promise<{ readonly [P in K]: GetResult<Unwrap<F[P]>> }>;  // one round trip, via §3.5a's returnFields — naming a method-shaped key is a compile error, not bad-payload
  getAll(deadline?: Deadline): Promise<{ readonly [K in keyof F as GetResult<Unwrap<F[K]>> extends never ? never : K]: GetResult<Unwrap<F[K]>> }>;   // every GET-able field, via returnFields: '*' — a method-only field is absent from the result type, not present as never
}

function remoteDevice<F extends Record<string, EndpointType | OptionalEndpointType>>(ctx: InstanceContext, address: Address, type: DeviceType<F>): RemoteDevice<F>;
```

`get()` on a `RemoteDevice<F>` whose `F` has no `'@'` key doesn't compile — `F` is the exact literal type `device()` inferred (§3.3), never widened to a bare `Record`, so `F['@']` is already the error, before `GetResult` runs at all. `getFields`/`getAll` are both one round trip over `ctx.messaging.get` with `options.returnFields` (§3.5a), never one request per field. There is no `setFields`: once §3.5a's SET-side rule holds (a named sibling is echoed, never written), a multi-field write has nothing analogous to batch, so setting more than one field is still one `set()` call per field.

`DriverKit.remote`/`.remoteDevice` (§3.5) are forwarding sugar only — `kit.remote(address, field)` is exactly `remote(ctx, address, field)` with the `ctx` a driver already has in scope closed over, the same convenience `attach()` already is over a bare `ctx.messaging.onRequest` call.

### 3.9. REMOVED

## 4. Introspection payload

`driver-kit` is what fills in the rest of both forms — `IntrospectionBase` (03 §5) and `IntrospectionChangeBase` (03 §5a) — once `type: 'driver-kit'` is on them:

```ts
// @evok-node/module-sdk
interface DriverKitIntrospection extends IntrospectionBase {   // form: 'full'
  readonly type: 'driver-kit';
  readonly kinds: Readonly<Record<string, KindEntry>>;   // one entry per kind with at least one bound device
  readonly devices: readonly DeviceRef[];               // every bound tail — a lone endpoint is a single-'@' device (§3.3), not a special wire case
}

interface DriverKitChange extends IntrospectionChangeBase {   // form: 'change' — 03 §5a
  readonly type: 'driver-kit';
  readonly devices: Readonly<Record<Tail, DeviceRef | null>>;   // null = unbound; a DeviceRef = bound, new or re-bound
  readonly kinds?: Readonly<Record<string, KindEntry>>;          // only kinds first bound after `from`
}

interface KindEntry {
  readonly fields: Readonly<Record<string, FieldEntry>>;   // every field the DeviceType declares, optional() ones included; '@' present whenever the tail itself answers GET/SET/CALL with no suffix; a sibling field is addressed at `<tail>.<key>`
}

interface DeviceRef {
  readonly tail: Tail;
  readonly kind: string;                  // the DeviceType's own kind (§3.3) — key into `kinds`
  readonly unbound?: readonly string[];   // optional() fields this device left unbound
}

interface FieldEntry {
  readonly shape: 'reading' | 'channel' | 'method';
  readonly subscribe: boolean;
  readonly effect?: 'none' | 'mutates';   // method only
  readonly schema: ValueSchema;         // duplicated from the field's own EndpointType (§3.1) — see below for why
  readonly setSchema?: ValueSchema;     // channel only, present iff the field's type has one
  readonly argsSchema?: ValueSchema;    // method only, present iff the field's type has one
}
```

Each kind's schema is written once per payload, never once per device: one kind is one `DeviceType` (§3.5), so every device of that kind shares it. A driver with hundreds of devices of a few kinds stays small.

```json
{
  "driverId": "ext1", "driverTypeName": "extension", "type": "driver-kit",
  "form": "full", "generation": { "epoch": "k3f9q2", "n": 42 },
  "kinds": {
    "DI": {
      "fields": {
        "@": {
          "shape": "reading", "subscribe": true,
          "schema": {
            "type": "struct",
            "fields": {
              "value":   { "type": "primitive", "format": "bool" },
              "counter": { "type": "primitive", "format": "uint32" },
              "readAt":  { "type": "primitive", "format": "timestamp" },
              "stale":   { "type": "primitive", "format": "bool" }
            }
          }
        },
        "debounce":     { "shape": "channel", "subscribe": false, "schema": { "type": "primitive", "format": "uint16", "unit": "ms" } },
        "directSwitch": { "shape": "channel", "subscribe": false, "schema": { "type": "primitive", "format": "bool" } }
      }
    }
  },
  "devices": [
    { "tail": "DI.01", "kind": "DI", "unbound": ["directSwitch"] },
    { "tail": "DI.02", "kind": "DI" }
  ]
}
```

A later change — `DI.03` bound, `DI.02` unbound:

```json
{
  "driverId": "ext1", "type": "driver-kit", "form": "change",
  "from": { "epoch": "k3f9q2", "n": 42 }, "to": { "epoch": "k3f9q2", "n": 44 },
  "devices": { "DI.03": { "tail": "DI.03", "kind": "DI" }, "DI.02": null }
}
```

`DI.01` lists `directSwitch` in `unbound`: an `optional()` field (§3.3) this binding didn't supply. The kind still describes it; this device just doesn't have it — 05 §2's "no value yet" rule extended to a field that may never exist for this device at all. A change never removes a kind; a kind no `DeviceRef` points to is harmless. A device with a single `'@'` field — 06's `get`, say — is the same shape, with one key in its kind's `fields`.

`shape`, `subscribe`, and `effect` travel on the wire alongside `schema`, not just its declarative data — enough of an `EndpointType`'s own contract to route a request correctly from the wire alone: a browser UI or third-party API client that never imported this plugin's package has no other way to get it. `Codec` itself — the actual `decode`/`encode`/`validate` — stays behind: a function genuinely cannot cross this boundary; only its declarative twin, `schema`, does (§3.1).

This isn't a wire-only normalization — `bindDevice()` (§3.5) is the only way to bind anything at all, so `$introspect`'s single `devices[]` list follows directly from what's actually bound, rather than needing to reconcile two binding primitives into one shape.

A struct/array/union-shaped endpoint's `GET` and `subscribe` always deliver the whole decoded value — `DI.01`'s reading answers `{value, counter, readAt, stale}` in one payload, never `value` alone. There's no field-level address on the wire; a consumer that wants just one field reads it out of the full snapshot itself.

## 4a. Validating another driver's introspection

A `remote`/`remoteDevice` caller (§3.8a) that doesn't fully trust its own assumptions about the far side — the address might not even be a `driver-kit`-built driver, or might be one running an older, incompatible table — checks before decoding, the same tier of guard §3.5's `isDeviceType` already is for a locally-imported `DeviceType`, now applied to a `$introspect` response instead:

```ts
// @evok-node/module-sdk
function isDriverKitIntrospection(body: Value): body is DriverKitIntrospection;   // shape only — type 'driver-kit', form 'full', kinds/devices well-formed, every DeviceRef.kind present in kinds; never checks a specific kind
function isDriverKitChange(body: Value): body is DriverKitChange;
function isDeviceRef(value: Value): value is DeviceRef;
function isFieldEntry(value: Value): value is FieldEntry;
function matchesDeviceType<F extends Record<string, EndpointType | OptionalEndpointType>>(ref: DeviceRef, kind: KindEntry, type: DeviceType<F>): boolean;   // ref.kind === type.kind, plus every field type asks for present in kind, shape-compatible, and not in ref.unbound
```

Each guard is duck-typed, the same reasoning as `isDeviceType`/`isModuleDescriptor` (§3.5, 02 §4): a `$introspect` response crossed a wire, so an `as DriverKitIntrospection` would have nothing behind it to enforce. `matchesDeviceType` is the structural check a `remoteDevice()` caller wants before trusting its own `DeviceType` against a driver it doesn't control the version of — it never replaces `remote`/`remoteDevice`'s own runtime decode against `field`'s `codec` (§3.8a), it's the earlier question: is this address even shaped the way `type` claims, before a single `get`/`set`/`call` is attempted.

## 4b. Following introspection for change

`$introspect` is `SUBSCRIBE`-able (03 §5a) so a consumer can follow a driver's table continuously rather than check it once at startup — the driver behind a `RemoteDevice` can be reloaded with a new, incompatible table while something still holds that handle. Two helpers, both built only on `IntrospectionSource` — never on `ctx`/`InstanceContext` directly — so the same logic works for a driver, an api, or a browser script talking to `api-nextgen` (15):

```ts
// @evok-node/module-sdk
interface IntrospectionSource {
  get(since?: Generation): Promise<IntrospectAnswer>;           // GET $introspect, options.since
  watch(onAnswer: (a: IntrospectAnswer) => void): () => void;   // SUBSCRIBE $introspect; returns unsubscribe
}

function followIntrospection(
  source: IntrospectionSource,
  onAnswer: (a: IntrospectAnswer) => void,   // a 'full' first, then each 'change' — 'full' again after a restart or a gap the log can't cover
): () => void;                               // unsubscribe from source

function watchDevice(
  source: IntrospectionSource,
  tail: Tail,
  check: (ref: DeviceRef | null, kind: KindEntry | undefined) => boolean,   // e.g. (r, k) => r !== null && k !== undefined && matchesDeviceType(r, k, type) — §4a
  onResult: (ok: boolean) => void,   // once immediately, then only when the result flips
): () => void;
```

`followIntrospection` is 03 §5a's client rule, written once. It calls `watch` before `get()`, so no change can fall between the two; it keeps the last `Generation`, and on a gap calls `get(since)`. That generation is the only state it holds.

`watchDevice` is built on `followIntrospection` and keeps only its own tail's `DeviceRef` and that ref's `KindEntry`. It re-runs `check` only for an answer that touches `tail` — a `full`, or a `change` naming it — never for every change. A `change` that re-binds `tail` to a kind it doesn't hold and doesn't carry makes it call `get()` for a `full`.

A driver's own `IntrospectionSource` is a handful of lines over `ctx.messaging.introspect`/`subscribe('$introspect', ...)` (03 §4); nothing here constructs that adapter — there's no reason to name it as its own type.

## 5. REMOVED

## 6. Wildcards — one family of endpoints, one subscription

A `subscribe` address may use `*` for exactly one dot-segment — `DI.*` matching `DI.01`, `DI.02`, … — available unconditionally for any `driver-kit`-built driver: a driver's own tail is always dot-structured by construction (`tail()`/`extendTail()`, 03 §2, plus `device()`/`bindDevice()`, §3.3/§3.5), so there's no per-driver opt-in to check. Whether this grammar applies at all is just `IntrospectionBase.type === 'driver-kit'` (§2, §4) — a driver answering `$introspect` by hand outside `driver-kit` never gets wildcard matching regardless. On a wildcard `subscribe`, the dispatcher expands the pattern against the driver's *current* endpoint table, subscribes to each match, and remembers the pattern itself so a later topology-generation bump re-expands it — a newly matching endpoint joins automatically, a removed one drops, with no re-subscribe from the caller. `unsubscribe`/`listSubscriptions`/`$subscriptions` operate on the literal pattern the caller used, never the expansion.

An event delivered through a wildcard subscription always carries the concrete address that actually changed (`Event.address`, 03 §2) — never the pattern. Matching a wildcard is the subscriber's own bookkeeping; the event shape doesn't need to represent it.

Subscribing to a `Device`'s own tail — the literal tail, or one reached through a wildcard match — subscribes to every subscribeable field of that device, not just `@`: `DI.*` matching `DI.01` picks up `DI.01`'s own `@` stream and its `debounce`-style siblings alike, each still delivered under its own concrete tail (`DI.01` for `@`, `DI.01.debounce` for a sibling) per this section's rule above — never the device's bare tail, never the pattern. This is the only way to observe more than one endpoint of a device from a single subscription — never a way to observe less than a full endpoint, since there's no field-level addressing (§4) to narrow to. Nothing new is needed for the fan-out itself: a device's fields are ordinary bound tails (§3.3), so it falls out of wildcard expansion exactly the way any other sibling tail already would.

## 7. Testing

Tier 1 (unit; `basics/03-Testing.md`), against `driver-kit`'s own fixtures — a minimal fixture driver with a handful of fixture `DeviceType`s, no real transport:

- Wildcard resolution (§6): a `DI.*` subscription picks up a fixture endpoint added after subscribing (a topology-generation bump) and drops one removed, with no re-subscribe from the caller.
- `bindDevice()`'s checks (§3.5): a fixture `DeviceType` whose own `kind` isn't in the device manifest is fatal at `bindDevice()`, before `attach()`; independently, a fixture `DeviceType` whose exported `kind` disagrees with its manifest entry's `deviceKind` is fatal; a duplicate `tail` is fatal independently of either; binding a second, different `DeviceType` object under a `kind` already bound in this driver is fatal.
- `resolveDeviceKind()` (§3.5): resolves a fixture `deviceKind` string to the same `DeviceType` a direct import of that fixture would give, and the result binds identically either way; a second call for the same `deviceKind` returns the memoized value, asserted by the fixture's own load-side-effect counter staying at 1; an unregistered `deviceKind` rejects, naming it, before `bindDevice()` ever runs.
- Introspection payload (§4): `$introspect` on a fixture driver returns `{driverId, driverTypeName, type: 'driver-kit', form: 'full', generation, kinds, devices}`; each kind appears once in `kinds` however many devices use it; each `KindEntry` lists every declared field, `optional()` ones included; each `FieldEntry` is exactly `shape`/`subscribe`/`effect?`/`schema`/`setSchema?`/`argsSchema?`; a device that leaves an `optional()` field unbound lists it in `unbound`; a fixture device with a single `'@'` field still appears as an ordinary `DeviceRef` — assert `codec`/`setCodec`/`argsCodec`/`resultCodec` themselves never leak onto the wire, only their serializable counterparts do.
- Change log (§3.8): each `bindDevice`/`unbindDevice` raises `n` by one and emits a `DriverKitChange` whose `from` is the previous generation; `GET` with `since` inside the last 16 changes answers one merged `change` (bind then unbind of one tail → `null`); `since` 17 changes back, or with another epoch, answers `full`; a `change` carries a `KindEntry` only for a kind first bound after `from`; `options.since` on another address or method, or malformed, is `bad-payload`.
- `RejectedPayload` (§3.5): a fixture `onSet` throwing it answers `bad-payload`, never `internal-error`; a fixture `onSet` throwing `SourceUnreachable` answers `unreachable`; any other thrown error from `onGet`/`onSet` still answers `internal-error`, unchanged.
- `DeviceType`/`bindDevice` (§3.3/§3.5): a `primitive`/`array`-shaped `@` declared alongside any sibling field is rejected when the `DeviceType` is built, before any driver binds it; a required field missing from `bindDevice`'s `handlers` is fatal, while the same `DeviceType` binds successfully with only some `optional()` fields supplied; a second `bindDevice()` whose tail falls inside an already-bound device's namespace, outside its declared fields, is fatal; every field handle in one `bindDevice()` call's `BoundDevice` is independently addressable, and `unbindDevice`ing the device's own tail doesn't silently leave a sibling field bound.
- `list`/`find` (§3.5): `list()` returns one `BoundDevice` per bound device, with only bound fields in `fields`; `find()` on a field tail returns `undefined`; typed `find(tail, type)` with a `type` whose `kind` differs from the bound device's throws.
- Wildcard over a device (§6): a `DI.*` subscription against a fixture device with `@` plus one subscribeable sibling field delivers events for both, each carrying its own concrete tail, never the device's bare tail or the pattern.
- `returnFields` (§3.5a): a strict array naming an unknown field, or a `CALL`-only field, is `bad-payload`; `'*'` on a device with a mixed `GET`/`CALL` sibling set returns every GET-able field and silently skips the `CALL`-only one; `options.returnFields` on `CALL`/`SUBSCRIBE`/`UNSUBSCRIBE` is `bad-payload`; a `SET` naming a sibling echoes its current value in the response without the sibling's own handler ever firing. On a fixture device with no `'@'`: `GET` with `returnFields` returns only the named fields; `GET` without it, and any `SET`, answer `unknown-address`.
- `RemoteEndpoint`/`RemoteDevice` (§3.8a): `remote`/`remoteDevice` against a fixture driver's own bound device round-trips `get`/`set`/`call` through `field`'s `codec`, never a cast; a `RemoteMethod`'s `call` surfaces a fixture `onCall`'s `domain-error`/`unreachable`/`timeout` arms unchanged; `getFields`/`getAll` issue exactly one request each, via `returnFields`, never one per field, and `getAll`'s result omits a method-shaped field entirely rather than typing it `never`. Compile-time only, never run: a `RemoteDevice<F>` fixture whose `F` has no `'@'` key fails to typecheck on `.get()`, asserted the same way `basics/03-Testing.md` asserts any other type-level contract.
- `isDriverKitIntrospection`/`isDriverKitChange`/`isDeviceRef`/`isFieldEntry`/`matchesDeviceType` (§4a): each guard rejects a malformed or foreign-shaped body without throwing; `isDriverKitIntrospection` rejects a `DeviceRef` whose `kind` is missing from `kinds`; `matchesDeviceType` flags a ref whose `kind` matches but whose kind's field `schema` doesn't, one whose `kind` disagrees outright, and one listing a field the type requires in `unbound`.
- `followIntrospection` (§4b): delivers a `full` first, then each `change` in order; against a fixture source that drops a change, it calls `get(since)` and delivers the merged `change`; after a fixture restart (new epoch), it delivers a `full`.
- `watchDevice` (§4b): calls `onResult` once, immediately; again exactly once when a later answer flips `check`'s result; never re-runs `check` for a `change` that doesn't name its tail.
