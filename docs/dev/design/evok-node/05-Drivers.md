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

What it buys: `bind`/`unbind` and the `$introspect` table they maintain, generic payload validation against a `returns` descriptor, facet and wildcard resolution, the scan-scheduling helper if §4 applies. 03 §5 already covers the fallback — a driver not built on `driver-kit` answers `$introspect` itself, by hand, as ordinary `onRequest` logic; nothing about the address is privileged at the protocol level, only the convenience is. That trade is worth taking deliberately rather than by default: a driver with one endpoint and no interest in facets or wildcards gains little from the machinery and can reasonably skip it.

## 6. Endpoint types and binding

### 6.1. `Codec<T>` and the three shapes

Every endpoint author writes against exactly one runtime object — a `Codec` — and its TS generic is inferred from it, never declared a second time alongside it:

```ts
// @evok-node/module-sdk
interface Codec<T> {
  decode(wire: Value): T;
  encode(value: T): Value;
  validate(wire: Value): boolean;
  describe(): TypeDescriptor;    // 03 §5's closed vocabulary — generated, never hand-typed
}
```

`module-sdk` ships the built-ins — `nativeCodec` for `boolean`/`number`/`string`/`Date`, `structCodec` for composing fields from other codecs, `arrayCodec` for a homogeneous list of any other codec, and `voidCodec` for a `method` with nothing meaningful to return on success. `nativeCodec`'s `Date` describes itself as `uint32` (epoch seconds, same convention as `readAt` in §6.8) — 03 §5's vocabulary is closed over wire type, never semantics, so `Date` gets no member of its own. A driver with no codec for its own value genuinely cannot bind an endpoint for it — the closed half of 03 §5, enforced structurally rather than by convention.

Three shapes, discriminated, each with its methods and `effect` fully implied rather than declared:

```ts
// @evok-node/module-sdk
interface ReadingType<T> {
  readonly shape: 'reading';       // GET (+SUBSCRIBE if `subscribe`); effect: 'none', implied
  readonly kind: string;           // open, namespaced outside this file's own catalog (§6.8)
  readonly subscribe: boolean;
  readonly codec: Codec<T>;
  readonly facets?: readonly (keyof T & string)[];
}

interface ChannelType<T, TSet = T> {
  readonly shape: 'channel';       // GET+SET (+SUBSCRIBE if `subscribe`); effect: 'mutates', implied
  readonly kind: string;
  readonly subscribe: boolean;
  readonly codec: Codec<T>;
  readonly setCodec?: Codec<TSet>; // only when SET's payload/echo genuinely differs from T
}

interface MethodType<R, A = void, E extends string = never> {
  readonly shape: 'method';        // CALL only
  readonly kind: string;
  readonly effect: 'none' | 'mutates';   // the one shape where this still varies
  readonly resultCodec: Codec<R>;
  readonly argsCodec?: Codec<A>;   // omitted ⇒ no payload
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
function reading<T>(kind: string, codec: Codec<T>, opts?: { subscribe?: boolean; facets?: readonly (keyof T & string)[] }): ReadingType<T>;
function channel<T, TSet = T>(kind: string, codec: Codec<T>, opts?: { subscribe?: boolean; setCodec?: Codec<TSet> }): ChannelType<T, TSet>;
function method<R, A = void, E extends string = never>(kind: string, effect: 'none' | 'mutates', resultCodec: Codec<R>, argsCodec?: Codec<A>, opts?: { errorKinds?: readonly E[] }): MethodType<R, A, E>;
```

`channel('RO', Codecs.bool)` infers `ChannelType<boolean, boolean>` entirely from the second argument; nobody writes `<boolean>` anywhere.

### 6.3. `CompositeEndpoint<Handles>` — composing more than one endpoint

Some device concepts need more than one address to be themselves — `DI` is a `reading` plus a wholly separate, writable debounce `channel`, and `SET` is never facet-resolved (03 §6.1), so debounce can't just be a field of the reading. Most kinds don't need this; it exists only for the composite ones:

```ts
interface CompositeEndpoint<Handles> {
  bind(kit: DriverKit, baseTail: Tail): Handles;
}
```

### 6.4. `bind`, `unbind`, and the fatal duplicate

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
  bind<T, TSet, E extends string = never>(tail: Tail, type: EndpointType<T, TSet, E>, handlers?: BindHandlers<T, TSet, E>): BoundEndpoint<T, E>;
  unbind(tail: Tail): void;
  list(): readonly BoundEndpointInfo[];
  find<T = unknown, E extends string = never>(tail: Tail): BoundEndpoint<T, E> | undefined;
  device(id: string, kind: string, prefix?: string): Tail;   // §6.6
  onGet<T>(ep: BoundEndpoint<T>, fn: (req: Request) => T | Promise<T>): void;
  onSet<T, TSet>(ep: BoundEndpoint<T>, fn: (value: TSet, req: Request) => TSet | Promise<TSet>): void;
  onCall<R, E extends string, A>(ep: BoundEndpoint<R, E>, fn: (payload: A, req: Request) => Promise<CallOutcome<R, E>>): void;
  attach(): void;                              // §6.7
}
```

A duplicate `tail` at `bind()` is fatal — checked against the driver's own table only, never a global view, because addresses are driver-qualified and uniqueness is local by construction. This is the direct mitigation for the wrong-relay bug class research/04 documents: no purchasable Unipi device has enough channels of one type to reproduce the bank-stride half of that bug on hardware, so this assertion is the only thing that can still catch a wrong address table before it drives the wrong output. A driver assembling its own tails in a loop is exactly where this matters most — 07 has the concrete mitigation for Modbus's own register arithmetic.

`unbind` tears down whatever the dispatcher was holding for that tail — active subscriptions included, the same discipline `$getCallProgress.<id>` already applies to itself the moment its own call resolves (03 §6.4) — and bumps the introspection generation (§6.7) the same way `bind` does.

Every handler's final argument is the `Request` it's answering — `origin`, `deadline`, `id`, the lot — for a handler that genuinely needs more than its own payload; 06's `get`/`has`/`set`/`delete` are the first to use it, reading `origin` to resolve a caller's namespace. A handler that doesn't need it just doesn't declare the parameter; nothing about the type requires touching it.

`handlers` on `bind()` is sugar for the three `on*` calls below it, nothing more — wiring at bind time is convenient when nothing else is going on, but `onGet`/`onSet`/`onCall` still exist on their own for a `CompositeEndpoint` (§6.3), whose `bind()` only ever returns handles and leaves wiring to the driver's own `configure()`. A handler that doesn't match the type's own shape — `onSet` against a `reading`, say — is a driver bug driver-kit rejects at `bind()` time, the same `reportFatal` path as a duplicate `tail`, not a silent no-op.

`onCall`'s three `CallOutcome` shapes are the entire expected-failure channel for a `method` endpoint (§2's "never throws," restated at this layer): resolving `{ok:true, result}` answers a success `Response`; resolving `{ok:false, kind:'domain-error', domainErrorKind, ...}` answers `Response.ok:false, kind:'domain-error'` with that same `domainErrorKind` — driver-kit checks it against the endpoint's own declared `errorKinds` (§6.1) first, and a value outside that set is treated exactly like a handler-shape mismatch above: a driver bug, reported as `internal-error` rather than trusted, since it's data-dependent and can't be caught at `bind()` time the way a shape mismatch can; resolving `{ok:false, kind:'unreachable'|'timeout', ...}` answers that `Response` kind directly, with no `domainErrorKind` — the one place a handler picks a built-in, non-`domain-error` kind itself, because whether the device answered *this* call is exactly the handler's own, synchronous knowledge (03 §7). A handler that actually throws is unchanged from §2: driver-kit's dispatcher catches it, answers `internal-error`, and logs and counts it — nothing above is something the handler opts into, it's the only way any of these three outcomes reach the wire.

`list`/`find` are driver-kit's own registry, already necessary internally for `$introspect` and for `unbind`'s teardown — exposed so a driver doesn't keep a second, parallel map of what it's already told `bind()` about. What `list`/`find` can't replace is a driver's own business data attached to a tail (a DALI ballast's label, say) that was never part of the endpoint table to begin with.

### 6.5. Dynamic binding is user data, not config

Binding or unbinding an endpoint at runtime — in response to a `CALL`, say, rather than at `configure` — means whatever drove that decision has to survive a restart on its own; the endpoint table itself is never persisted, it's rebuilt by replaying whatever caused it. That "whatever" is user data (01 §2), the same category as an alias or a group, and belongs in the KV-store driver's own namespace for this driver (06) — reloaded at `configure`, written back on every change. 06 has the mechanism; this is only the reminder that a driver doing this has somewhere to put it.

### 6.6. `device()` — grouping, not a protocol addition

```ts
device(id: string, kind: string, prefix?: string): Tail;   // prefix nests one device under another; omitted ⇒ rooted at the driver's own top level
```

Prefixes every tail bound under it and stamps a `device: { id, kind }` field onto each of those endpoints' introspection entries, purely so a UI or API can group and label without parsing a tail. `prefix` takes a plain string or another `device()` call's own return value interchangeably — a `Tail` is a `string`, nothing more is needed to nest one device under another. Addressing, facets, everything else are unaffected — this is `driver-kit` convenience, not a new concept 03 needs to know about.

### 6.7. `attach()` — the one `onRequest`

```ts
attach(): void;
```

No arguments — `createDriverKit(ctx)` already closed over `ctx` at construction. This is the one moment `ctx.messaging.onRequest(...)` is actually called, once, after every `bind()` a driver wants at startup; facet and wildcard resolution inside it reuse 03 §6.1/§6.2 wholesale, never reimplemented per driver. It also raises the driver's own introspection `generation` on every `bind`/`unbind` and emits it on `$introspect` — `SUBSCRIBE`-able for exactly this, 03 §5a — so a client watching for new endpoints never has to poll.

### 6.8. The built-in catalog

Bare `kind` names are reserved for this catalog; everything else is namespaced (12 has the plugin convention). All of it lives in `@evok-node/module-sdk`, built from the same factories and codecs any driver or api uses:

```ts
export const RO = channel('RO', Codecs.bool);
export const DO = channel('DO', Codecs.bool);
export const AI = reading('AI', Codecs.float32);
export const AO = channel('AO', Codecs.float32);

const DIReading  = reading('DI', Codecs.struct({ value: Codecs.bool, counter: Codecs.uint32, readAt: Codecs.uint32, stale: Codecs.bool }),
  { facets: ['value', 'counter'] });
const DIDebounce = channel('DI.debounce', Codecs.uint16, { subscribe: false });
export const DI: CompositeEndpoint<{ reading: BoundEndpoint<...>; debounce: BoundEndpoint<number> }> = {
  bind(kit, baseTail) {
    return { reading: kit.bind(baseTail, DIReading), debounce: kit.bind(extendTail(baseTail, 'debounce'), DIDebounce) };
  },
};
```

`DO` and `RO` are identical past `kind` — a relay and a transistor output carry the same value and the same operations; the distinction is purely semantic, which is exactly what `kind` being separate from `returns` (03 §5) is for. `DI` alone needs `CompositeEndpoint` (§6.3): its debounce is a real, separately-writable endpoint, bound alongside the reading under one call, never a facet.

## 7. Sharing a driver-owned resource

01 §7's pattern, restated at the level a driver author actually acts on it: a resource one driver owns — a transport, a namespace — can be shared by other drivers that reach it through the owner's own request/response messaging, never by opening a second client on it themselves. The owning driver's own config says nothing about this on a dependent's behalf; the dependent declares the link itself (02 §4, 03 §8), and its own config carries whatever extra context the relationship needs — its address on that transport, say.

What the owner exposes for this is, so far, one recurring shape: a set of `CALL` endpoints mirroring the underlying protocol's own operations one-to-one, each declared with whatever `effect` that operation actually has — so a dependent can speak the protocol directly rather than the owner having to anticipate every device that might ever share it. 07 has the concrete shape for Modbus: eight methods, one per function code, rather than a single generic query/command pair — precise enough that a caller picks the exact wire operation instead of the transport guessing.

## 8. REMOVED
