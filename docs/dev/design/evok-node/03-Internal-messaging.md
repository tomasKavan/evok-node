# 03 — Internal messaging

## 1. Scope

This file is the concrete shape of what 01 §5 leaves abstract: the envelope every driver and api actually exchanges, how it is addressed, how a request is answered or a subscription delivered, and how a failure crosses the boundary as a value rather than an exception. It also settles who opens a link and when — `main`, at spawn and at reload, never at message time (01 §2, §8) — and where a message's types and the handle a module calls through `InstanceContext` are published. It assumes 01's two-kind model, 02's manifest/reload machinery and 04's common services; it does not restate them.

## 2. Message shapes

Everything that crosses the boundary is one of three kinds — a **request**, a **response**, or an **event** — matching 01 §5. All three, and everything beneath them, are *typed* in `@evok-node/module-sdk`: there is no separate `messaging` package. `module-sdk` holds types, interfaces, and pure helper functions only — the fan-in helper below, address parsing (§6) — never a running implementation. The actual dispatcher, the socket handling, the subscription bookkeeping: that's `main`'s own code, built once and handed out through a runner (§9), the same split 04 §2 already draws for `Logger` (interface in `module-sdk`, real pino sinks only in `main`). `module-sdk` depends on nothing of ours; it is the root of the dependency graph, and the one package a plugin author needs both to build a module and to talk about one.

```ts
type DriverId  = Brand<string, 'DriverId'>;
type ApiId     = Brand<string, 'ApiId'>;
type Tail      = Brand<string, 'Tail'>;       // the part after the colon — a driver's own namespace, never valid outside it
type Address   = Brand<string, 'Address'>;    // "PLC:DI.2.01" — driverId:tail, tail opaque past the colon (01 §6)
type Seq       = Brand<number, 'Seq'>;
type MessageId = Brand<string, 'MessageId'>;
type Value     = string | number | boolean | null | readonly Value[] | { readonly [key: string]: Value };

function tail(...segments: string[]): Tail;                                  // the one audited join
function extendTail(base: Tail, ...segments: string[]): Tail;                // a sub-tail from an existing one
function address(driverId: DriverId, tail: Tail): Address;                   // the one place ':' gets inserted
function parseAddress(address: Address): { driverId: DriverId; tail: Tail }; // the dispatcher's own inverse — the prefix a handler never sees (§4)

/** Provenance, not routing — kept for logging/attribution even though nothing brokers on it. */
interface Origin {
  readonly instanceId: DriverId | ApiId;   // the api or driver that issued the request
  readonly client?: string;                // an api's own end-client id, opaque past it
}

type Method = 'GET' | 'SET' | 'CALL' | 'SUBSCRIBE' | 'UNSUBSCRIBE';

interface Request {
  readonly v: 1;
  readonly id: MessageId;
  readonly address: Address;
  readonly method: Method;
  readonly payload?: Value;
  readonly deadline: Deadline;   // 04 §6 — absolute, never "ms from now"
  readonly origin: Origin;
}

type Response =
  | { readonly v: 1; readonly id: MessageId; readonly re: MessageId; readonly ok: true; readonly body: Value }
  | { readonly v: 1; readonly id: MessageId; readonly re: MessageId; readonly ok: false;
      readonly error: { readonly kind: ErrorKind; readonly detail: string } };   // §7

interface Event {
  readonly v: 1;
  readonly from: DriverId;
  readonly address: Address;     // always the concrete address that changed — §6
  readonly seq: Seq;             // monotonic per driver — §6
  readonly value: Value;         // always a full snapshot, never a diff — §6
}

type Envelope = Request | Response | Event;
```

`Tail`/`Address` are never built by a raw template literal outside the four functions above — RPG-DRV-1's "one audited address function" (05 §6.4), generalized past Modbus register arithmetic to addressing itself.

`Request.deadline` is never the sender's raw value once a link is crossed — every link crosses one now (§10) — 04 §6.2a says how it's reconstructed fresh at each hop. The type above is what a module's own code always sees: already locally valid, nothing further to convert.

One shape for every method, not a discriminated union per method — a deliberate, narrow exception to `basics/02-Coding.md` §1.3: GET/SET/CALL/SUBSCRIBE/UNSUBSCRIBE are one thing with a varying payload, the way HTTP verbs share one request line. What each method requires of its payload is declared per-endpoint in introspection (§5) and checked once, generically, before a handler ever runs — not encoded in the type.

A batched, cross-driver read — an api asking for several qualified addresses in one logical call — is `module-sdk`'s fan-in helper, not a fourth envelope kind: it groups addresses by `DriverId`, sends one `Request` per driver over that driver's own link with its own slice of the caller's deadline, and merges partial `Response`s back keyed by the original address. A driver down does not fail the addresses that answered.

## 3. Addressing

`<driverId>:<tail>` (01 §6), case-sensitive, tail grammar owned entirely by the issuing driver. Four tails are reserved at the messaging layer, outside any driver's own grammar, and never reach a driver's `onRequest` handler:

- `$introspect` — `GET` returns the driver's introspection payload (01 §6); also `SUBSCRIBE`-able — §5a.
- `$subscriptions` — `GET` returns the caller's own active subscriptions on that driver.
- `$health` — a driver `emit`s here whenever its own reachability or degradation state changes (05's job to define the taxonomy); consumed like any other address, by `subscribe` (§4). `main` never inspects it — a driver's degradation is a business signal for whoever subscribes, not something `main` supervises (§11 covers what `main` actually reacts to).
- `$getCallProgress.<id>` — parameterized by a `CALL` `Request`'s own `MessageId`, not a fixed string; exists only while that call is in flight. Both `GET`-able and `subscribe`-able — §6.4.

All four are answered/fed generically (§5, §6), not hand-written per driver. There is no `$ping`: liveness is a property of the transport (§10), never a message a module sees.

## 4. Handling — `onRequest`

Nothing distinguishes a driver from an api at this layer; both get the same `MessagingHandle` through `InstanceContext` (§9). In practice only drivers ever register a handler — only a `DriverId` is addressable (§3), so nothing dials an api.

```ts
// @evok-node/module-sdk
interface OnRequestOptions {
  readonly tailMode?: 'opaque' | 'dottedAddressing';   // default 'opaque' — §6
}

interface CallHandle extends PromiseLike<Response> {
  // awaiting a CallHandle directly resolves with the final Response, exactly like get/set/introspect
  getProgress(): Promise<Response>;   // body: { progress: number; description?: string } — §6.4
}

interface MessagingHandle {
  get(address: Address, deadline?: Deadline): Promise<Response>;
  set(address: Address, payload: Value, deadline?: Deadline): Promise<Response>;
  call(address: Address, payload?: Value, deadline?: Deadline): CallHandle;
  introspect(driverId: DriverId): Promise<Response>;   // sugar over GET <driverId>:$introspect — §5
  subscribe(address: Address, onEvent: (event: Event) => void): void;   // upsert — subscribing an address already active replaces its handler
  unsubscribe(address: Address): void;
  listSubscriptions(): readonly Address[];   // this instance's own want-list — not the wire-level $subscriptions (§6.3)
  onRequest(handler: (req: Request) => Promise<Response>, options?: OnRequestOptions): void;
  emit(tail: string, value: Value): void;   // push a fresh snapshot of one base endpoint — §6 handles delivery
  reportProgress(callId: MessageId, progress: number, description?: string): void;   // fire-and-forget, clamped to [0,1] — §6.4
}
```

A handler's own `Response.id` and `re` are never load-bearing — the runtime mints the real `id` and sets `re: req.id` itself before anything reaches the wire, overwriting whatever the handler supplied. Keeping the full `Response` shape as the handler's return type, rather than a narrower success/failure pair, is deliberate: a handler that wants `id`/`re` for its own logging can still have them, even though nothing downstream trusts the values it chose.

`onRequest`'s handler only ever sees `GET`/`SET`/`CALL` against the module's own real, base-address endpoints — `$introspect`, `$subscriptions`, `$getCallProgress.<id>` (§6.4), and any facet or wildcard resolution (§6) are all intercepted before this point. `SUBSCRIBE`/`UNSUBSCRIBE` still exist as wire methods (§2) — the dispatcher needs them to talk to a driver's own live bookkeeping (§6.3) — but a module reaches every method only through its own dedicated `get`/`set`/`call`/`introspect`/`subscribe`/`unsubscribe`, never by constructing a `Request` by hand, so the durable want-list §6.3 describes and the per-call progress state §6.4 describes can't be bypassed. `send` isn't part of this interface at all — `get`/`set`/`call`/`introspect` share one primitive underneath, but that's `main`'s own implementation, the same split 04 §2 draws for `Logger` (§2). The handler never sees its own driver id in `address` either — the dispatcher strips it, since a handler only ever serves its own tail grammar and would just have to discard the prefix.

Until a module calls `onRequest`, *every* request — `GET`/`SET`/`CALL`, and any `SUBSCRIBE`/`UNSUBSCRIBE` a `subscribe`/`unsubscribe` call generates — answers `not-ready` (§7), never a hang, never a dropped connection. Nothing about subscriptions, facets or `tailMode` can be interpreted safely before this point either, since it's `onRequest`'s own call that supplies `tailMode` in the first place. This is a statement about the module's own startup (02 §5's two-phase `configure`/`start`, §9); `unreachable` (§7) is the separate, later signal for the device or bus that module owns.

Nothing here ever throws across the boundary. A handler that throws is a bug, not a business failure (`basics/02-Coding.md` §2.1); the dispatcher catches it, answers `internal-error`, and logs and counts it (§7) — the throw never reaches the caller, and never hangs one.

## 5. Introspection

Answered generically at `$introspect` from a driver's own declared endpoint table — building that table is `driver-kit`'s job (01 §11, "introspection assembly"), reusable by any driver built on it. A driver not built on `driver-kit` answers `$introspect` itself, as ordinary `onRequest` logic — nothing about the address is privileged at the protocol level, only in the convenience `driver-kit` provides.

Every endpoint declares `shape` (`reading` | `channel` | `method`) and `kind`; the rest follows from `shape` rather than being declared separately. A `reading` is `GET`-only, `effect: 'none'`, implied; a `channel` is `GET`+`SET`, `effect: 'mutates'`, implied — both add `subscribe: boolean` for whether `SUBSCRIBE` is available, and `returns` for the value's shape (05 has the `Codec`/`EndpointType` machinery `returns` comes from). A `channel` may also declare `setReturns`, only when `SET`'s echoed value is a narrower type than `GET`'s — defaults to `returns` when omitted. A `method` is `CALL`-only and, alone among the three, still declares its own `effect` (query versus command genuinely varies), plus `payload?` and `returns` for its own argument and result shapes. A `struct`-returning `reading`/`channel` may declare `facets: readonly string[]`, naming which fields are individually addressable (§6).

`kind` is open, not the closed enum an earlier draft of 01 §6 called it: any driver, built-in or plugin, can declare one nobody else has (`'unipi:DI'`, `'dali:BRIGHTNESS'`), namespaced by convention — driver-family prefix, colon, name — so two plugins introducing the same concept under different names don't collide in whatever groups or labels by `kind` (12 has the concrete plugin-authoring guidance for this). Nothing generic ever switches on `kind` exhaustively; it exists for grouping and display, never for correctness.

`returns` is the closed half, and correctness leans on it instead: a fixed vocabulary of value types — `bool`, `uint8`, `uint16`, `uint32`, `int8`, `int16`, `int32`, `float32`, `{ type: 'enum', values: readonly string[] }`, `{ type: 'struct', fields: Record<string, TypeDescriptor> }`, and `json` for data with no stable shape to declare (opaque past well-formedness — no generic validation, no generic rendering beyond a raw dump). Switching exhaustively on this vocabulary, rather than on `kind`, is what lets a brand-new plugin's endpoints render and validate correctly with zero code written for that plugin. Widening it later is additive and reviewed centrally — the same discipline research/12 already asked for when `returns` was scalars-plus-`struct` alone. In practice it comes from a `Codec`'s own `describe()` (05), never hand-typed by a driver author — one less place for the wire shape and the driver's own code to quietly disagree.

A driver's `capabilities` array (already sketched in research/12) gains `'dotted-addressing'` when it opted into that `tailMode` (§6). The dispatcher checks a request's method and payload against this before calling the handler (`bad-payload`/`unsupported-method`, §7), so no handler re-checks what introspection already promised.

## 5a. Introspection change notification

`$introspect` is also `SUBSCRIBE`-able, delivering `{ generation: Seq }` on every change to the driver's own endpoint table — a fresh bind, an unbind, never a change to an existing endpoint's own value, which is what its own address's events are for. Same precedent as `$health` (§3): a driver emits here itself, consumed like any other address, by `subscribe` (§4), through the exact same coalescing buffer and reconnect-replay §6.3 already describes — no new envelope kind, no new capability flag. The payload stays minimal on purpose: a client that sees the number change issues a fresh `introspect()` if it cares what changed, the same "a gap is harmless, re-`GET`" reasoning §6.3 already relies on everywhere else.

## 6. Facets, wildcards and subscriptions

Subscription follows the shape of what's actually addressable — one endpoint can be worth several addresses, and a driver may let a family of endpoints be addressed as a group. Both are resolved generically; a driver's own code never sees either.

### 6.1. Facets — a struct endpoint's fields, addressed on their own

An endpoint whose `returns` is `struct` and declares `facets` (§5) — say `DI.01` returning `{value, counter}` — is also reachable at `DI.01:value` and `DI.01:counter`, for `GET`/`subscribe` only. Resolution tries the literal address against the endpoint table first; only when nothing claims it exactly does the dispatcher split on the *last* colon and check whether the base names a real endpoint with that facet. This ordering means a driver whose own opaque tail happens to contain a colon for unrelated reasons is never misread as a facet address — a facet address exists only where no real endpoint already claims it outright.

A facet `GET` calls the handler with the *base* address, gets the struct back, and projects the named field — the handler never sees the facet was requested. A facet `subscribe` subscribes to the base address's own `emit` stream and projects the field out of every snapshot delivered on it, so subscribing to `DI.01:value` alone still delivers an event whenever `DI.01` emits, whether or not `value` itself differs from the last snapshot — simple, and harmless given 6.3's coalescing buffer already treats a superseded snapshot as free. **An event delivered on any address — base, facet, or a wildcard-matched concrete one — always has the same value-shape a fresh `GET` on that same address would return.** `SET`/`CALL` are never facet-resolved: a driver wanting field-level write exposes it as its own endpoint or method.

### 6.2. Wildcards — one family of endpoints, one subscription

A `subscribe` address may use `*` for exactly one dot-segment — `DI.*` matching `DI.01`, `DI.02`, … — allowed only for a driver that passed `tailMode: 'dottedAddressing'` to `onRequest` (§4). Nothing forces this grammar on a driver that hasn't opted in; an `opaque` driver's tails are exact-match-only for subscribe, same as always. On a wildcard `subscribe`, the dispatcher expands the pattern against the driver's *current* endpoint table, subscribes to each match, and remembers the pattern itself so a later topology-generation bump re-expands it — a newly matching endpoint joins automatically, a removed one drops, with no re-subscribe from the caller. `unsubscribe`/`listSubscriptions`/`$subscriptions` operate on the literal pattern the caller used, never the expansion. A facet suffix composes with a wildcard the same way it composes with any base address (`DI.*:value`) — expand the wildcard first, then resolve the facet on each match.

An event delivered through a wildcard subscription always carries the concrete address that actually changed (`Event.address`, §2) — never the pattern. Matching a wildcard is the subscriber's own bookkeeping; the event shape doesn't need to represent it.

### 6.3. Delivery

`subscribe`/`unsubscribe` (§4) are how a module asks for events; underneath, they still travel as ordinary `SUBSCRIBE`/`UNSUBSCRIBE` requests, and all of it — including facet and wildcard resolution — is handled by the same generic dispatcher that answers `$introspect`, never by the driver author's own `onRequest`. A driver's code only ever calls `emit(tail, value)` on its own base address when a value changes; the dispatcher fans that out to whoever is currently subscribed, at whatever address they actually asked for.

**Every event is a full snapshot, never a diff.** This one choice is what keeps the rest of subscription simple:

- **Gaps are harmless, and there is no resync protocol.** Each driver's events carry a monotonic `Seq`; a subscriber that notices a gap (`seq` jumped by more than one) already has the answer — issue a fresh `GET`, because the driver's in-memory state is always current regardless of how many intermediate snapshots were missed. Diffing would need a resync handshake; snapshots don't.
- **Backpressure is a per-address coalescing buffer, not a bounded FIFO.** At most one pending event per address, per subscriber; a fresher snapshot for an address already queued replaces it. Nothing meaningful is ever dropped, because a superseded snapshot was never meaningful once a newer one exists for the same address — true only because events are snapshots, not deltas.

**Two different records of "what's subscribed," on purpose.** The *provider*'s own bookkeeping — who's currently listening, right now, over which live connection — is connection state: it lives entirely in that driver's own dispatcher and is gone the instant the link drops, for any reason (§11), rebuilt only from whatever reconnects. `$subscriptions` (§3) reads this one — "who does the driver currently see," a live, ephemeral view, of no use across a restart.

The *consumer*'s own want-list is different, and it's the one that makes re-subscribing not the module author's problem. Every `subscribe(address, onEvent)` call writes into a small map the consumer's own `MessagingHandle` keeps for the life of the instance — address to handler, upsert semantics, so calling `subscribe` again on an address already present just replaces the handler (§4) — and sends the wire `SUBSCRIBE` immediately if the link happens to be up. `unsubscribe(address)` removes the entry and sends `UNSUBSCRIBE` the same way; `listSubscriptions()` reads this same map back, synchronously, with no round trip. None of this depends on the link being connected at the moment it's called — a module can `subscribe` before its link has finished connecting for the first time, or while it's mid-reconnect after the provider crashed, and nothing is lost.

**Every successful (re)connect replays the whole want-list.** The first time a link comes up, this is a no-op past whatever was already `subscribe`d before that point; after a provider crashes and a fresh instance reconnects (§10, §11), it's what restores every subscription automatically, with no cooperation from either module's own code. A subscription that survives a reconnect this way is treated as new, not resumed — the provider's `Seq` for that address starts over, so the consumer resets whatever it was tracking for gap detection rather than reading the restart as one giant gap. If a replayed (or first-time) `SUBSCRIBE` comes back with an error — `unknown-address`, say, for a typo'd tail — there's still no promise to reject, since `subscribe` returns nothing; the messaging layer logs it (04 §3.6) instead, so it's diagnosable without making the module author handle it.

### 6.4. Call progress

A `CALL` can take longer than a caller wants to wait blind for one final answer, so `call()` (§4) doesn't return a bare `Promise<Response>` — it returns a `CallHandle`, thenable to that same eventual `Response` but also carrying `getProgress()`. Nothing new is needed at the envelope level to support it: a `CALL` in flight gets one more reserved address for exactly its own lifetime, `<driverId>:$getCallProgress.<id>` where `id` is that `CALL` `Request`'s own `MessageId` (§3) — created the instant the dispatcher hands the request to the handler, torn down the instant the matching `Response` is sent. While it exists it's both `GET`-able and `subscribe`-able, exactly like a real endpoint, reusing §6.3's delivery wholesale rather than inventing a second one.

A handler that wants to report progress calls `reportProgress(req.id, progress, description?)` (§4) any number of times while its own promise for that request is still pending — `req.id` is already in scope, since it's the id of the request the handler is currently handling. `progress` is clamped to `[0,1]`; the call is fire-and-forget, the same shape as `emit`, because it *is* `emit` in substance: it updates the dispatcher's own cached "latest progress" for that id — what a `GET` on `$getCallProgress.<id>` reads back, since there's no live handler behind this address to call the way a real endpoint's `GET` would — and pushes an `Event` to anyone currently `subscribe`d to it, the same coalescing buffer and everything else in §6.3 applying unmodified. A handler that never calls it isn't wrong — plenty of `CALL`s resolve too fast to bother reporting anything — a `GET`/subscription against its `$getCallProgress.<id>` just reads back a default `{progress: 0}` until either a real report arrives or the call resolves.

This is why the mechanism needs no new `Envelope` kind, no new `ErrorKind`, and no change to `Request`/`Response`/`Event` (§2): wanting a snapshot is `GET`, wanting a push instead of a poll is `subscribe`, and asking about a call that's already resolved is `unknown-address` — the address genuinely doesn't exist anymore, exactly what that kind already means (§7). The dispatcher tears down `$getCallProgress.<id>` and drops any subscriptions to it the moment the real `Response` goes out, so nothing lingers and nobody needs to remember to unsubscribe — the same "developers shouldn't bother with this" stance §6.3's reconnect-replay already takes.

## 7. Failure

Expected failure is always a `Response` value; nothing on this boundary throws (`basics/02-Coding.md` §2.1, §2.2). `ErrorKind` is a string-literal union (§2.4), grouped by whose problem it is, mirroring HTTP's caller/environment/us split without borrowing its numeric codes — an api translates these to its own wire-level codes at its own boundary (13):

```ts
type ErrorKind =
  | 'unknown-address' | 'unsupported-method' | 'bad-payload' | 'not-subscribed'
  | 'not-ready' | 'unreachable' | 'timeout' | 'deadline-exceeded' | 'link-down' | 'internal-error';
```

| Kind | Meaning | Whose problem |
|---|---|---|
| `unknown-address` | tail doesn't exist on this driver, doesn't resolve as a facet either (§6.1), or names a `$getCallProgress` id for a call that's already resolved (§6.4) | caller |
| `unsupported-method` | endpoint doesn't support this method | caller |
| `bad-payload` | failed the endpoint's declared payload check | caller |
| `not-subscribed` | `unsubscribe` on something never subscribed | caller |
| `not-ready` | module hasn't called `onRequest` yet | timing |
| `unreachable` | driver is up, its device/bus isn't answering (05's degradation state) | environment |
| `timeout` | driver tried, no answer within its own budget | environment |
| `deadline-exceeded` | caller's own deadline elapsed before any response arrived; manufactured locally, may never have reached the target | nobody, structurally |
| `link-down` | the peer process/thread itself is gone | infrastructure |
| `internal-error` | handler threw | our bug |

`unreachable` and `link-down` are kept apart deliberately: one is a device/bus degradation a driver reports about itself, the other is the driver's own host being gone — different operator response, different signal to `main`'s own supervision (§11). Every link now crosses a real process/thread boundary (§10), so `link-down` is the *only* outcome of a crash — there is no in-process case left where a dependent could still get an application-level answer instead.

## 8. Links: declared, not discovered

A link is opened once, by `main`, never by a module and never at message time (01 §2, §8, §9). Two mechanisms feed one topology, because they answer to two different owners:

- **An api's links are `main`'s own, generic, parsed field** — `drivers:` on an `apis:` entry (02 §3), sibling to `type`/`run`. 01 §9 frames "an api declares which driver ids it consumes" as a rule for every api, not a per-api convention, so the field is standardized at `main`'s level.
- **A driver's links are its own descriptor's business** — `ModuleDescriptor.declaredLinks(config)` (02 §4), because 01 §7 already frames a shared-transport declaration as living inside the depending driver's own schema, bundled with whatever else that relationship needs (its own address on the shared bus, say). A generic field couldn't carry that extra context without `main` having to understand it, which is exactly what stays opaque.

```ts
// @evok-node/module-sdk
declaredLinks?(config: Config): { readonly drivers: readonly DriverId[] };   // absent ⇒ none
```

Pure and synchronous, callable by `main` on a parsed `Config` before any instance exists — same shape as `isConfigEqual`, for the same reason: `main` needs this before it can spawn anything, and spawning is exactly what it must not do until every config is validated (02 §5).

`main` assembles the full `instanceId → DriverId[]` graph while resolving cross-instance concerns (02 §5, §7): every referenced id must exist in `drivers:`, and a cycle is fatal at parse — a genuine mutual dependency between two drivers' own transports is a configuration mistake, not something the runtime should have to survive. Link existence is consumer-declared; whether a driver needs a *listening* socket at all (§10) is inferred by `main` from the reverse edges of this same graph, never declared by the driver being depended on.

## 9. `InstanceContext` and the runner

```ts
// @evok-node/module-sdk
interface InstanceContext {
  readonly log: Logger;                 // 04 §3
  readonly clock: Clock;                // 04 §4
  readonly messaging: MessagingHandle;  // §4
  reportFatal(detail: string): void;    // fire-and-forget — never awaited, never throws — §11
}
```

`ctx.messaging` is the same object, same shape, for the life of the instance — never replaced, only mutated underneath by the runner as links come and go. This follows straight from 02 §4: `createInstance(ctx)` receives `ctx` exactly once, synchronously, and no later call receives it again, so whatever `ctx.messaging` is has to survive every reload without changing identity.

**Startup** is two barriers, reusing the shape reload already has rather than inventing a second one (02 §5, §6; pseudocode in §11):

1. For every instance: `runner.configure(config)` — spawn the hosting environment, wire `ctx` (a socket bound where §10 says one is needed), `createInstance(ctx)`, then `instance.configure(config)`. Every instance's `configure` completes before any instance's `start` begins.
2. For every instance: `runner.start()` — `instance.start()`.

Binding a listening socket happens at step 1, as plumbing, independent of how slow that instance's own `configure`/`start` is — a dependent can connect immediately. What it can't yet get is a real answer, which is `not-ready` (§4, §7), bounded by the caller's own deadline like everything else. The barrier reduces how often that happens; it isn't what makes it safe — `not-ready` and deadline-bounded retry are.

**Reload** slots into 02 §5.1's existing prepare/commit barrier without adding a new one:

- **Prepare**: the runner closes whatever the new `declaredLinks`/`drivers:` no longer needs — exactly `prepareReload`'s already-stated job, "releases what nextConfig won't need," applied to links the same way it applies to anything else a module's own `prepareReload` releases.
- **Commit**: the runner opens whatever links are newly declared, then calls `instance.reload(config)` (or spawns fresh, if prepare stopped it). `ctx.messaging` is the same object throughout — only its open links changed.

A link whose declaration didn't change is untouched by either endpoint's own in-place reload — same socket path, same process, nothing to close and reopen. It only moves when the declaration itself changes, or when an endpoint is torn down and respawned rather than reloaded — in which case the surviving side's connection simply drops and reconnects (§10), the same mechanism that handles a cold-start ordering race and a crash (§11).

This needs one addition to 02 §8.5's `computeReloadPlan`: for an id in the "changed" bucket, a second, finer diff — old `declaredLinks`/`drivers:` against new — decides which links move. `isConfigEqual` true already guarantees that diff is empty, since both are pure functions of `Config`.

## 10. Transport

One mechanism, unconditionally, now that every instance runs in its own `worker_thread` or `child_process` (01 §3) — there is no in-process case left to special-case. Every link is a Unix domain socket. `main` binds one listening socket per driver that has at least one dependent, at `/run/evok-node/links/<driverId>.sock`; every dependent opens its own client connection to it. One accepted connection *is* one link — there is no envelope-level demultiplexing to design, the OS connection boundary already does that job. Framing is length-prefixed JSON; research/08 already showed software overhead is nowhere near the bottleneck, so there's no case yet for a binary codec. A `Request`'s `deadline` never travels as the sender's raw value — 04 §6.2a says how it's reconstructed at each end.

The rule for who listens and who connects is the same as §8's declaration rule: **the depended-on driver listens, whoever declared the link connects.** A connection that drops — cold-start ordering, a peer torn down and respawned, or a crash (§11) — is retried with backoff by the connecting side, bounded by the same `Clock`/`Deadline` machinery as everything else (04 §6), never a bespoke retry loop. One reconnect mechanism covers all three; the caller doesn't need to know which one it is, only that the socket isn't there yet.

## 11. Lifecycle: start, stop, reload, fatal, and a crash

Two of the memo's original open items turn out not to need new machinery. `readyToStop` is `drain()`'s own promise resolving — `main` already awaits it (02 §4, §6); there is no separate signal to add. `health` is ordinary event traffic on the reserved `$health` address (§3) — a business signal for whoever subscribes, not something `main` consumes. Only genuine escalation to `main` needed a new primitive: `ctx.reportFatal(detail)` (§9), fire-and-forget, for the case 04 §3.6 already names — "the instance cannot continue" — discovered after `start()` has already resolved, with no other call in flight to reject.

A module that never calls `reportFatal` isn't unsafe, just uncovered by its own choice. If something throws uncaught, the `worker_thread`/`child_process` hosting it (01 §3) simply dies, and `main`'s runner finds out the same way it finds out about anything else it didn't ask for: the `'error'`/`'exit'` listener it attached at spawn (02 §6). A crash and an explicit `reportFatal` end at the same cleanup, `onInstanceLost` below — `reportFatal` just gets one extra, best-effort step first, since the code calling it is, by definition, still alive enough to be asked nicely. Neither path is retried automatically; same stance 02 §5 already takes for a `start()` that rejected during commit.

Pseudocode below, not a literal API — it exists to make the ordering unambiguous. `Runner`, `ModuleDescriptor`, `ModuleInstance`, `DriverId` and `computeReloadPlan` are 02's/03's own defined types; the rest (`Instance`, `ConfigById`, `runners`, `registry`, `wireContext`, `closeLinks`/`openLinks`, `env`, `onInstanceLost`, and so on) are this sketch's own scratch names, not new surface.

```ts
// main, cold start (02 §5 step 6) — two barriers, no third
async function startAll(instances: Instance[]): Promise<void> {
  const runners = instances.map(i => runnerFactory.spawn(i.descriptor, i.id, i.run, i.links));
  await Promise.all(runners.map((r, i) => r.configure(instances[i].config)));   // barrier 1
  await Promise.all(runners.map(r => r.start()));                              // barrier 2
}

// RunnerFactory.spawn — starts the hosting environment and, up front, the one thing
// that lets main learn about a crash it didn't ask for (02 §6).
function spawn(descriptor, id, placement, links): Runner {
  const env = placement === 'worker_thread' ? new Worker(bootstrapPath) : fork(bootstrapPath);
  const runner = new Runner(id, placement, env, links);
  env.on('error', () => onInstanceLost(runner, 'crashed'));
  env.on('exit', (code) => { if (code !== 0) onInstanceLost(runner, 'crashed'); });
  return runner;
}

// Runner.configure — runs inside the worker_thread/child_process bootstrap, over
// postMessage/IPC; only the underlying transport differs between the two placements.
async function configure(this: Runner, config: Config): Promise<void> {
  this.ctx = wireContext(this.links);            // bind sockets §10, build the MessagingHandle
  this.instance = this.descriptor.createInstance(this.ctx);
  await this.instance.configure(config);         // may call onRequest, may await readiness on a peer
}

// Runner.stop — the graceful path, main-initiated, nothing wrong with the instance
async function stop(this: Runner): Promise<void> {
  if (this.state === 'stopped' || this.state === 'stopping') return;   // idempotent
  this.state = 'stopping';
  await this.instance.drain();    // "ready to stop" IS this resolving
  await this.instance.stop();
  closeLinks(this.links);
  this.state = 'stopped';
}

// main, reload (02 §5.1) — one barrier, link diff folded into prepare/commit
async function reload(newConfig: ConfigById): Promise<void> {
  const plan = computeReloadPlan(oldConfig, newConfig, registry);   // + link diff, §9

  await Promise.all([
    ...plan.removed.map(id => runners[id].stop()),
    ...plan.changed.map(id => runners[id].prepareReload(newConfig[id])),   // closes stale links
  ]);   // barrier: every prepare/stop above resolves before any commit below starts

  await Promise.all([
    ...plan.added.map(async id => {
      const r = runnerFactory.spawn(descriptorOf(id), id, runOf(id), plan.links[id]);
      await r.configure(newConfig[id]);
      await r.start();
      runners[id] = r;
    }),
    ...plan.changed.map(id => runners[id].commitReload(newConfig[id])),    // opens new links, then reload
  ]);
}

// Runner.prepareReload
async function prepareReload(this: Runner, nextConfig: Config): Promise<void> {
  closeLinks(diff(this.links, declaredLinksOf(nextConfig)).removed);
  if (this.instance.prepareReload) await this.instance.prepareReload(nextConfig);
  else if (!this.instance.reload) { await this.stop(); this.survivedPrepare = false; }
}

// Runner.commitReload
async function commitReload(this: Runner, nextConfig: Config): Promise<void> {
  openLinks(diff(this.links, declaredLinksOf(nextConfig)).added);
  this.links = declaredLinksOf(nextConfig);
  if (this.survivedPrepare === false) {
    this.ctx = wireContext(this.links);
    this.instance = this.descriptor.createInstance(this.ctx);
    await this.instance.configure(nextConfig);
    await this.instance.start();
  } else {
    await this.instance.reload!(nextConfig);
  }
}

// Shared tail for a dead instance, whichever way it died. Never retried automatically.
async function onInstanceLost(runner: Runner, reason: 'crashed' | 'reported-fatal'): Promise<void> {
  closeLinks(runner.links);       // every dependent's connection drops — link_down, then reconnect-with-backoff (§10)
  unlinkStaleSocket(runner.id);   // so a respawned instance can bind the same path again
  runner.state = 'failed';        // distinct from a clean 'stopped' — 02 §6's existing state set
  log.fatal(`instance lost (${reason})`, { instanceId: runner.id });
}

// Attached once, at spawn (above) — this is how a crash reaches main at all; nothing
// negotiated, nothing to call on an instance that's already gone.
// (see spawn's env.on('error'/'exit', ...) above)

// Instance → runner, any time after construction — never awaited by the instance itself
ctx.reportFatal('duplicate endpoint address DI.01');
// runner's own reaction — the one thing that distinguishes this from a crash: a bounded,
// best-effort attempt at a clean shutdown before the exact same tail runs.
async function onReportFatal(runner: Runner, detail: string): Promise<void> {
  await raceWithDeadline(runner.instance.stop(), deadlineFrom(runner.clock, 2000 as Millis));
  await runner.env.terminate();   // worker.terminate() / child.kill()
  await onInstanceLost(runner, 'reported-fatal');
}
```

## 12. Testing

Tier 1 (unit; `basics/03-Testing.md`), split by where the code actually lives.

**`module-sdk`** — pure functions and data only, no runner, no socket:

- Every `Envelope` variant round-trips through JSON unchanged (property test) — the discipline the old standalone `messaging` package's README asked for, now this package's own.
- Address parsing: `driverId:tail` split, facet-suffix split (`<base>:<facet>`, exact-match-first per §6.1), single-segment wildcard matching (`DI.*` against a fixed address list, including a tail that itself contains a stray `:` or `*` for unrelated reasons — must not be misread).
- The fan-in helper: partial results merge correctly, keyed by address, when one driver's per-link deadline expires and another's doesn't.

**`main`** — the dispatcher and transport, extending 02 §8's runner/reload fixtures rather than duplicating them:

- `not-ready` before `onRequest`, for `GET`/`SET`/`CALL` and for any `subscribe`/`unsubscribe` call made before it.
- `internal-error` on a handler that throws — logged and counted (`basics/02-Coding.md` §2.3), never propagated, never hanging the caller past its deadline.
- `$introspect`/`$subscriptions`/`$health` answered, or fed, without reaching the fixture handler.
- Facet resolution (§6.1): `GET`/a `subscribe`d facet projects correctly; a literal address that collides with a real endpoint is never facet-resolved.
- Wildcard resolution (§6.2): a `DI.*` subscription picks up a fixture endpoint added after subscribing (a topology-generation bump) and drops one removed, with no re-subscribe from the caller.
- Subscription bookkeeping (§6.3): the per-address coalescing buffer under backpressure — deliver-latest-only, never a superseded snapshot; `subscribe` on an already-active address replaces the handler rather than adding a second one; `listSubscriptions()` reflects the consumer's own want-list exactly, distinct from a provider's `$subscriptions`.
- `get`/`set`/`call`/`introspect` (§4): each delegates to the same underlying request path as the others and to `subscribe`/`unsubscribe`/`onRequest` where relevant — no behavior difference from what the old single `send` produced for the same method, `introspect(driverId)` produces exactly the `Request` a hand-built `GET <driverId>:$introspect` would.
- Call progress (§6.4): `getProgress()` reads back the default `{progress: 0}` before a fixture handler ever calls `reportProgress`; a `reportProgress` call updates both a subsequent `getProgress()` poll and fires an `Event` to an existing `subscribe`r on `$getCallProgress.<id>`, through the same coalescing buffer as §6.3; `getProgress()` (poll or subscribe) answers `unknown-address` once the matching `Response` has been sent; no subscription to `$getCallProgress.<id>` survives past that point — assert it's actually gone from the provider's bookkeeping, not just silent.
- Reconnect and resubscribe (§6.3, below): sever a link mid-test (kill the fixture worker), assert dependents see `link-down`, then bring a fresh instance up at the same socket path and assert every previously-`subscribe`d address is replayed automatically, events resume with no fixture code calling `subscribe` again, and `Seq` for each address restarts rather than being read as a gap.
- Transport (§10): every link round-trips a `Request`/`Response`/`Event` over a real Unix socket — bind path, listen/connect roles, reconnect-with-backoff after the listener restarts mid-test.
- Deadline reconstruction (04 §6.2a): a `Request` sent with a near-expired deadline from one process still carries a sane, independently-clamped `Deadline` on arrival at the other — assert it's derived from the *receiver's* clock, not a raw copy of the sender's.
- The two-phase startup barrier (§9): no instance's `start()` fires before every instance's `configure()` has resolved.
- Reload's link diff (§9): closes exactly what changed and nothing else; a link whose declaration didn't change survives an in-place `reload()` untouched — assert the same connection object, never closed and reopened.
- Crash detection (above): kill a fixture worker/child directly, not via `reportFatal`; assert `main`'s `'error'`/`'exit'` listener fires, that runner ends in `failed`, its links are closed and its socket path is freed for a respawn, and the daemon process itself is unaffected.
- `reportFatal` (above): a fixture instance calling it gets a bounded attempt at `instance.stop()` first (assert the mock's `stop` was actually invoked, within the deadline), then ends its runner in `failed` — same outcome as a crash, one extra step first.
