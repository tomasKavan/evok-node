# 03 — Internal messaging

## 1. Scope

This file is the concrete shape of what 01 §5 leaves abstract: the envelope every driver and api actually exchanges, how it is addressed, how a request is answered or a subscription delivered, and how a failure crosses the boundary as a value rather than an exception. It also settles who opens a link and when — `main`, at spawn and at reload, never at message time (01 §2, §8) — and where a message's types and the handle a module calls through `InstanceContext` are published. It assumes 01's two-kind model, 02's manifest/reload machinery and 04's common services; it does not restate them.

## 2. Message shapes

Everything that crosses the boundary is one of three kinds — a **request**, a **response**, or an **event** — matching 01 §5. All three, and everything beneath them, are *typed* in `@evok-node/module-sdk`: there is no separate `messaging` package. `module-sdk` holds types, interfaces, and pure helper functions only — the fan-in helper below, address parsing (§6) — never a running implementation. The actual dispatcher, the socket handling, the subscription bookkeeping: that's `main`'s own code, built once and handed out through a runner (§9), the same split 04 §2 already draws for `Logger` (interface in `module-sdk`, real pino sinks only in `main`). `module-sdk` depends on nothing of ours; it is the root of the dependency graph, and the one package a plugin author needs both to build a module and to talk about one.

```ts
type DriverId  = Brand<string, 'DriverId'>;
type Address   = Brand<string, 'Address'>;    // "PLC:DI.2.01" — driverId:tail, tail opaque past the colon (01 §6)
type Seq       = Brand<number, 'Seq'>;
type MessageId = Brand<string, 'MessageId'>;
type Value     = string | number | boolean | null | readonly Value[] | { readonly [key: string]: Value };

/** Provenance, not routing — kept for logging/attribution even though nothing brokers on it. */
interface Origin {
  readonly instanceId: string;   // the api or driver that issued the request
  readonly client?: string;      // an api's own end-client id, opaque past it
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

One shape for every method, not a discriminated union per method — a deliberate, narrow exception to `basics/02-Coding.md` §1.3: GET/SET/CALL/SUBSCRIBE/UNSUBSCRIBE are one thing with a varying payload, the way HTTP verbs share one request line. What each method requires of its payload is declared per-endpoint in introspection (§5) and checked once, generically, before a handler ever runs — not encoded in the type.

A batched, cross-driver read — an api asking for several qualified addresses in one logical call — is `module-sdk`'s fan-in helper, not a fourth envelope kind: it groups addresses by `DriverId`, sends one `Request` per driver over that driver's own link with its own slice of the caller's deadline, and merges partial `Response`s back keyed by the original address. A driver down does not fail the addresses that answered.

## 3. Addressing

`<driverId>:<tail>` (01 §6), case-sensitive, tail grammar owned entirely by the issuing driver. Three tails are reserved at the messaging layer, outside any driver's own grammar, and never reach a driver's `onRequest` handler:

- `$introspect` — `GET` returns the driver's introspection payload (01 §6).
- `$subscriptions` — `GET` returns the caller's own active subscriptions on that driver.
- `$health` — a driver `emit`s here whenever its own reachability or degradation state changes (05's job to define the taxonomy); consumed like any other address, by `SUBSCRIBE`. `main` never inspects it — a driver's degradation is a business signal for whoever subscribes, not something `main` supervises (§11 covers what `main` actually reacts to).

All three are answered/fed generically (§5, §6), not hand-written per driver. There is no `$ping`: liveness is a property of the transport (§9), never a message a module sees.

## 4. Handling — `onRequest`

Nothing distinguishes a driver from an api at this layer; both get the same `MessagingHandle` through `InstanceContext` (§9). In practice only drivers ever register a handler — only a `DriverId` is addressable (§3), so nothing dials an api.

```ts
// @evok-node/module-sdk
interface OnRequestOptions {
  readonly tailMode?: 'opaque' | 'dottedAddressing';   // default 'opaque' — §6
}

interface MessagingHandle {
  send(address: Address, method: Method, payload?: Value, deadline?: Deadline): Promise<Response>;
  onRequest(handler: (req: Request) => Promise<Response>, options?: OnRequestOptions): void;
  emit(tail: string, value: Value): void;   // push a fresh snapshot of one base endpoint — §6 handles delivery
}
```

`onRequest`'s handler only ever sees `GET`/`SET`/`CALL` against the module's own real, base-address endpoints — `$introspect`, `$subscriptions`, `SUBSCRIBE`, `UNSUBSCRIBE`, and any facet or wildcard resolution (§6) are all intercepted before this point. The handler never sees its own driver id in `address` either — the dispatcher strips it, since a handler only ever serves its own tail grammar and would just have to discard the prefix.

Until a module calls `onRequest`, *every* request — `GET`/`SET`/`CALL` and `SUBSCRIBE`/`UNSUBSCRIBE` alike — answers `not-ready` (§7), never a hang, never a dropped connection. Nothing about subscriptions, facets or `tailMode` can be interpreted safely before this point either, since it's `onRequest`'s own call that supplies `tailMode` in the first place. This is a statement about the module's own startup (02 §5's two-phase `configure`/`start`, §9); `unreachable` (§7) is the separate, later signal for the device or bus that module owns.

Nothing here ever throws across the boundary. A handler that throws is a bug, not a business failure (`basics/02-Coding.md` §2.1); the dispatcher catches it, answers `internal-error`, and logs and counts it (§7) — the throw never reaches the caller, and never hangs one.

## 5. Introspection

Answered generically at `$introspect` from a driver's own declared endpoint table — building that table is `driver-kit`'s job (01 §11, "introspection assembly"), reusable by any driver built on it. A driver not built on `driver-kit` answers `$introspect` itself, as ordinary `onRequest` logic — nothing about the address is privileged at the protocol level, only in the convenience `driver-kit` provides.

Each endpoint declares, at minimum: `shape` (`channel` | reading | `method`), `kind` (closed enum, 01 §6), `effect` (mandatory, no default), `returns`, which methods it supports and whether each requires a payload, and — for a `struct`-returning endpoint — an optional `facets: readonly string[]` naming which of its fields are individually addressable (§6). A driver's `capabilities` array (already sketched in research/12) gains `'dotted-addressing'` when it opted into that `tailMode` (§6). The dispatcher checks a request's method and payload against this before calling the handler (`bad-payload`/`unsupported-method`, §7), so no handler re-checks what introspection already promised.

## 6. Facets, wildcards and subscriptions

Subscription follows the shape of what's actually addressable — one endpoint can be worth several addresses, and a driver may let a family of endpoints be addressed as a group. Both are resolved generically; a driver's own code never sees either.

### 6.1. Facets — a struct endpoint's fields, addressed on their own

An endpoint whose `returns` is `struct` and declares `facets` (§5) — say `DI.01` returning `{value, counter}` — is also reachable at `DI.01:value` and `DI.01:counter`, for `GET` and `SUBSCRIBE` only. Resolution tries the literal address against the endpoint table first; only when nothing claims it exactly does the dispatcher split on the *last* colon and check whether the base names a real endpoint with that facet. This ordering means a driver whose own opaque tail happens to contain a colon for unrelated reasons is never misread as a facet address — a facet address exists only where no real endpoint already claims it outright.

A facet `GET` calls the handler with the *base* address, gets the struct back, and projects the named field — the handler never sees the facet was requested. A facet `SUBSCRIBE` subscribes to the base address's own `emit` stream and projects the field out of every snapshot delivered on it, so subscribing to `DI.01:value` alone still delivers an event whenever `DI.01` emits, whether or not `value` itself differs from the last snapshot — simple, and harmless given 6.3's coalescing buffer already treats a superseded snapshot as free. **An event delivered on any address — base, facet, or a wildcard-matched concrete one — always has the same value-shape a fresh `GET` on that same address would return.** `SET` and `CALL` are never facet-resolved: a driver wanting field-level write exposes it as its own endpoint or method.

### 6.2. Wildcards — one family of endpoints, one subscription

A `SUBSCRIBE` address may use `*` for exactly one dot-segment — `DI.*` matching `DI.01`, `DI.02`, … — allowed only for a driver that passed `tailMode: 'dottedAddressing'` to `onRequest` (§4). Nothing forces this grammar on a driver that hasn't opted in; an `opaque` driver's tails are exact-match-only for subscribe, same as always. On a wildcard `SUBSCRIBE`, the dispatcher expands the pattern against the driver's *current* endpoint table, subscribes to each match, and remembers the pattern itself so a later topology-generation bump re-expands it — a newly matching endpoint joins automatically, a removed one drops, with no re-subscribe from the caller. `UNSUBSCRIBE` and `$subscriptions` operate on the literal pattern the caller used, never the expansion. A facet suffix composes with a wildcard the same way it composes with any base address (`DI.*:value`) — expand the wildcard first, then resolve the facet on each match.

An event delivered through a wildcard subscription always carries the concrete address that actually changed (`Event.address`, §2) — never the pattern. Matching a wildcard is the subscriber's own bookkeeping; the event shape doesn't need to represent it.

### 6.3. Delivery

`SUBSCRIBE`/`UNSUBSCRIBE` are ordinary requests, and `$subscriptions` lists what's active — but all of it, including facet and wildcard resolution, is handled by the same generic dispatcher that answers `$introspect`, never by the driver author's own `onRequest`. A driver's code only ever calls `emit(tail, value)` on its own base address when a value changes; the dispatcher fans that out to whoever is currently subscribed, at whatever address they actually asked for.

**Every event is a full snapshot, never a diff.** This one choice is what keeps the rest of subscription simple:

- **Gaps are harmless, and there is no resync protocol.** Each driver's events carry a monotonic `Seq`; a subscriber that notices a gap (`seq` jumped by more than one) already has the answer — issue a fresh `GET`, because the driver's in-memory state is always current regardless of how many intermediate snapshots were missed. Diffing would need a resync handshake; snapshots don't.
- **Backpressure is a per-address coalescing buffer, not a bounded FIFO.** At most one pending event per address, per subscriber; a fresher snapshot for an address already queued replaces it. Nothing meaningful is ever dropped, because a superseded snapshot was never meaningful once a newer one exists for the same address — true only because events are snapshots, not deltas.
- **Subscriptions are connection state, not persisted state.** They live in the dispatcher's own bookkeeping for that link — patterns, facets and all — and vanish when the link drops. A reconnecting api re-subscribes; this is 13's existing "translation state is rebuilt, not persisted" rule, applied to one more piece of state.

## 7. Failure

Expected failure is always a `Response` value; nothing on this boundary throws (`basics/02-Coding.md` §2.1, §2.2). `ErrorKind` is a string-literal union (§2.4), grouped by whose problem it is, mirroring HTTP's caller/environment/us split without borrowing its numeric codes — an api translates these to its own wire-level codes at its own boundary (13):

```ts
type ErrorKind =
  | 'unknown-address' | 'unsupported-method' | 'bad-payload' | 'not-subscribed'
  | 'not-ready' | 'unreachable' | 'timeout' | 'deadline-exceeded' | 'link-down' | 'internal-error';
```

| Kind | Meaning | Whose problem |
|---|---|---|
| `unknown-address` | tail doesn't exist on this driver, and doesn't resolve as a facet either (§6.1) | caller |
| `unsupported-method` | endpoint doesn't support this method | caller |
| `bad-payload` | failed the endpoint's declared payload check | caller |
| `not-subscribed` | `UNSUBSCRIBE` on something never subscribed | caller |
| `not-ready` | module hasn't called `onRequest` yet | timing |
| `unreachable` | driver is up, its device/bus isn't answering (05's degradation state) | environment |
| `timeout` | driver tried, no answer within its own budget | environment |
| `deadline-exceeded` | caller's own deadline elapsed before any response arrived; manufactured locally, may never have reached the target | nobody, structurally |
| `link-down` | the peer process/thread itself is gone | infrastructure |
| `internal-error` | handler threw | our bug |

`unreachable` and `link-down` are kept apart deliberately: one is a device/bus degradation a driver reports about itself, the other is the driver's own host being gone — different operator response, different signal to `main`'s own supervision (§11).

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

1. For every instance: `runner.configure(config)` — spawn the hosting environment if one is needed, wire `ctx` (a socket bound where §10 says one is needed), `createInstance(ctx)`, then `instance.configure(config)`. Every instance's `configure` completes before any instance's `start` begins.
2. For every instance: `runner.start()` — `instance.start()`.

Binding a listening socket happens at step 1, as plumbing, independent of how slow that instance's own `configure`/`start` is — a dependent can connect immediately. What it can't yet get is a real answer, which is `not-ready` (§4, §7), bounded by the caller's own deadline like everything else. The barrier reduces how often that happens; it isn't what makes it safe — `not-ready` and deadline-bounded retry are.

**Reload** slots into 02 §5.1's existing prepare/commit barrier without adding a new one:

- **Prepare**: the runner closes whatever the new `declaredLinks`/`drivers:` no longer needs — exactly `prepareReload`'s already-stated job, "releases what nextConfig won't need," applied to links the same way it applies to anything else a module's own `prepareReload` releases.
- **Commit**: the runner opens whatever links are newly declared, then calls `instance.reload(config)` (or spawns fresh, if prepare stopped it). `ctx.messaging` is the same object throughout — only its open links changed.

A link whose declaration didn't change is untouched by either endpoint's own in-place reload — same socket path, same process, nothing to close and reopen. It only moves when the declaration itself changes, or when an endpoint is torn down and respawned rather than reloaded — in which case the surviving side's connection simply drops and reconnects (§10), the same mechanism that handles a cold-start ordering race.

This needs one addition to 02 §8.5's `computeReloadPlan`: for an id in the "changed" bucket, a second, finer diff — old `declaredLinks`/`drivers:` against new — decides which links move. `isConfigEqual` true already guarantees that diff is empty, since both are pure functions of `Config`.

## 10. Transport per placement

One mechanism for every cross-boundary pair, and one trivial special case:

- **Both ends `single_thread`** — a direct in-process call. No serialisation; 01 §3's discipline (no callbacks, no class instances, no shared mutable state) is what keeps this honest, not a wire format.
- **Everything else** — a Unix domain socket, uniformly, regardless of which two placements are actually involved. `main` binds one listening socket per driver that has at least one dependent whose link isn't purely `single_thread`↔`single_thread`, at `/run/evok-node/links/<driverId>.sock`; every dependent opens its own client connection to it. One accepted connection *is* one link — there is no envelope-level demultiplexing to design, the OS connection boundary already does that job. Framing is length-prefixed JSON; research/08 already showed software overhead is nowhere near the bottleneck, so there's no case yet for a binary codec.

The rule for who listens and who connects is the same as §8's declaration rule: **the depended-on driver listens, whoever declared the link connects.** A connection that drops — cold-start ordering, or a peer torn down and respawned — is retried with backoff by the connecting side, bounded by the same `Clock`/`Deadline` machinery as everything else (04 §6), never a bespoke retry loop. One reconnect mechanism covers both "never connected yet" and "was connected, peer came back."

## 11. Lifecycle: start, stop, reload, fatal

`readyToStop` is `drain()`'s own promise resolving — `main` already awaits it (02 §4, §6); there is no separate signal to add. `health` is ordinary event traffic on the reserved `$health` address (§3) — a business signal for whoever subscribes, not something `main` consumes. Only genuine escalation to `main` needed a new primitive: `ctx.reportFatal(detail)` (§9), fire-and-forget, for the case 04 §3.6 already names — "the instance cannot continue" — discovered after `start()` has already resolved, with no other call in flight to reject.

Pseudocode below, not a literal API — it exists to make the ordering unambiguous. `Runner`, `ModuleDescriptor`, `ModuleInstance`, `DriverId` and `computeReloadPlan` are 02's/03's own defined types; the rest (`Instance`, `ConfigById`, `runners`, `registry`, `wireContext`, `closeLinks`/`openLinks`) are this sketch's own scratch names, not new surface.

```ts
// main, cold start (02 §5 step 6) — two barriers, no third
async function startAll(instances: Instance[]): Promise<void> {
  const runners = instances.map(i => runnerFactory.spawn(i.descriptor, i.id, i.run, i.links));
  await Promise.all(runners.map((r, i) => r.configure(instances[i].config)));   // barrier 1
  await Promise.all(runners.map(r => r.start()));                              // barrier 2
}

// Runner.configure — single_thread; worker_thread/child_process do the same steps
// inside their bootstrap, over postMessage/IPC instead of a direct call.
async function configure(this: Runner, config: Config): Promise<void> {
  this.ctx = wireContext(this.links);            // bind sockets §10, build the MessagingHandle
  this.instance = this.descriptor.createInstance(this.ctx);
  await this.instance.configure(config);         // may call onRequest, may await readiness on a peer
}

// Runner.stop — any placement
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

// Instance → runner → main, any time after construction — never awaited by the instance itself
ctx.reportFatal('duplicate endpoint address DI.01');
// runner: logs at `fatal` (04 §3.6), tagged with this instance's id, then:
this.state = 'failed';   // distinct from a clean 'stopped' — 02 §6's existing state set
await this.stop();       // no restart, no daemon crash; main moves on, same as a rejected start()
```

## 12. Testing

Tier 1 (unit; `basics/03-Testing.md`), split by where the code actually lives.

**`module-sdk`** — pure functions and data only, no runner, no socket:

- Every `Envelope` variant round-trips through JSON unchanged (property test) — the discipline the old standalone `messaging` package's README asked for, now this package's own.
- Address parsing: `driverId:tail` split, facet-suffix split (`<base>:<facet>`, exact-match-first per §6.1), single-segment wildcard matching (`DI.*` against a fixed address list, including a tail that itself contains a stray `:` or `*` for unrelated reasons — must not be misread).
- The fan-in helper: partial results merge correctly, keyed by address, when one driver's per-link deadline expires and another's doesn't.

**`main`** — the dispatcher and transport, extending 02 §8's runner/reload fixtures rather than duplicating them:

- `not-ready` before `onRequest`, for every method including `SUBSCRIBE`/`UNSUBSCRIBE`.
- `internal-error` on a handler that throws — logged and counted (`basics/02-Coding.md` §2.3), never propagated, never hanging the caller past its deadline.
- `$introspect`/`$subscriptions`/`$health` answered, or fed, without reaching the fixture handler.
- Facet resolution (§6.1): `GET`/`SUBSCRIBE` on a declared facet projects correctly; a literal address that collides with a real endpoint is never facet-resolved.
- Wildcard resolution (§6.2): a `DI.*` subscription picks up a fixture endpoint added after subscribing (a topology-generation bump) and drops one removed, with no re-subscribe from the caller.
- Subscription delivery (§6.3): gap detection via `Seq`, and the per-address coalescing buffer under backpressure — deliver-latest-only, never a superseded snapshot.
- Transport per placement: `single_thread` is a direct call — assert non-cloneable data survives, proof it never left the process; `worker_thread`/`child_process` round-trip a `Request`/`Response`/`Event` over the real channel; the Unix-socket path specifically — bind path, listen/connect roles, reconnect-with-backoff after the listener restarts mid-test.
- The two-phase startup barrier (§11): no instance's `start()` fires before every instance's `configure()` has resolved.
- Reload's link diff (§9, §11): closes exactly what changed and nothing else; a link whose declaration didn't change survives an in-place `reload()` untouched — assert the same connection object, never closed and reopened.
- `reportFatal` (§11): a fixture instance calling it ends its runner in `failed`, never `stopped`, and never brings down the daemon process.
