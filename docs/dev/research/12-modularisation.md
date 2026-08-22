# Driver/api/main modularisation

## What changes, and what does not

**The goal does not change.** Neither does the definition of 1.0: compatibility complete, every
bug disposition closed. What changes is the *path* — compat stops being the first thing built and
becomes the last consumer added.

**The cost of that is smaller than it looks.** Of the 29 findings, only seven are M4-only (2.3,
3.2, 3.4, 3.5, 3.6, 3.7, 3.10). The other 22 live in transport, addressing, definitions, the device
model and operability, and close on the same schedule as before. Several of the seven are
surface-agnostic mechanisms — WebSocket backpressure, keepalive and close semantics,
write-returns-post-write-value — so building them correctly in the nextgen API first makes the
compat versions projections of already-correct machinery.

**One caveat on the reasoning.** The risk of compat setting the project's constraints does not come
from compat being *early*; it comes from compat being *the model*. G-3 and RC-24 already say compat
emits a projection. Keeping that projection a pure, derived function is the real protection.
Ordering is the secondary safeguard, and the reason to still take it is that compat built last is
compat that *cannot* have leaked.

## Architecture

Three kinds of component over one messaging bus — but **two layers**: drivers act, APIs query, and
`main` is neither, because it sits on no request path.

- **main** — parses config, spawns and supervises drivers and APIs, handles reload. On no request
  path, ever.
- **driver** — owns exactly one transport endpoint. Polls, holds the only copy of state, answers
  queries from memory, exposes endpoints via introspection. A transport endpoint need not be a bus:
  the filesystem, a process-exec surface and a SQLite file all qualify, so system configuration and
  the user-data store are drivers too.
- **api** — a stateless translator between the internal bus and one public protocol. Holds no
  state, caches no readings.

There is no third component kind. Anything that would have been one is a driver whose transport
happens not to be Modbus.

### Decisions taken in discussion

| | Decision | Why |
|---|---|---|
| 1 | **One driver per transport endpoint**, not per device | Four drivers on one `/dev/ttyNS0` is the contention G-7 exists to prevent |
| 2 | **Single-threaded, single event loop** | Nothing here is compute-bound; `worker_threads` buys only timer isolation, and that is an M6 measurement, not a design input |
| 3 | **Drivers hold the only copy of state; APIs are stateless** | Two copies diverge invisibly, and the snapshot/sequence/gap machinery is a distributed-systems problem imported into one process voluntarily |
| 4 | **A driver's query path never blocks on I/O** | This is what makes 3 safe: a query is a memory read, so a timeout means the driver is genuinely wedged and an error is honest |
| 5 | **Fan-in uses per-driver deadlines and returns partial results** | All-or-nothing aggregation is how one missing 1-Wire sensor froze every sensor (2.5), and how a failing register block discarded a whole scan pass (2.6) |
| 6 | **Internal addresses are `<driverId>:<driver-defined tail>`**, case-sensitive | Routing becomes parsing; no routing table needed for the nextgen API |
| 7 | **Registration is declarative from config; reachability is a state** | Restates finding 2.1 correctly — see below |
| 8 | **Introspection is the source of compat's translate table** | Derived, not hand-maintained, so it cannot drift from what drivers expose |
| 9 | **An API's public schema is driver-agnostic — a new driver adds data, never schema** | This is what makes plugin drivers possible without an API release (G post-1.0), and it is what lets the nextgen surface be designed incrementally alongside the drivers instead of against every future one |
| 10 | **What an API exposes is the API's business.** `drivers:` is an administrator restriction, nothing more. A driver type an API does not understand is skipped, not refused | Exposure policy belongs to the surface doing the exposing, not to a label the driver author picks. And a second mechanism saying which types an API handles would duplicate what its projection table already says — RD-6 |

### Finding 2.1 is misnamed

Its title says "discovery is a one-shot startup step". The evidence says otherwise — #192
verbatim: *"If a device is defined in the configuration, a communication test is performed at
startup. If this test fails, the device is not registered."* Plus the code path:
`ModbusSlave.readboards()` catches `ConnectionException`, logs "No board detected", returns, no
retry.

So the bug is **registration gated on a one-shot reachability probe**. Registration was always
declarative. Retitle it, and reconsider its disposition: if the endpoint list is a `readonly`
structure derived from frozen config (RC-4) and health is a separate field, "unreachable ⇒
unregistered" is not expressible. That is a `construction` candidate closing at driver-kit rather
than a `test` at M5 — flagged as a candidate, since bug-dispositions rule 2 puts the call on the
reviewer.

Consequence: real discovery exists only on buses that have it. Make change-notification a
**declared capability**, so an API subscribes to topology events only from drivers that have them.

## Package layout

Four of the current nine survive untouched and `client` keeps its role. `core/` and `server/`
dissolve, `protocol/` splits, `inspector` is renamed.

| Package | Change | Contents |
|---|---|---|
| `messaging` | from `protocol` | envelope contract, codec, correlation, deadlines, fan-in helper |
| `hw-definitions` | unchanged | platform facts; now a `main`-only dependency |
| `modbus` | unchanged | transport; now a driver-only dependency |
| `main` | **new** | config parse, resource-exclusivity validation, spawn, supervise, reload |
| `driver-kit` | **new** | scan scheduling, readings with `readAt`/`stale`, handshake, deadlines, introspection assembly |
| `driver-onboard` | **new** | the controller's own I/O sections, over Modbus TCP to `unipitcp` |
| `driver-extension` | **new** | Unipi RTU extensions on one RS-485 line; one instance per line |
| `api-nextgen` | **new** | WS then HTTP; owns its own public schema |
| `api-compat` | **new** | EVOK 3.x REST, JSON, bulk, WS, webhook, JSON-RPC; owns the projection table |
| `simulator` | unchanged | ADR-0011 stands |
| `client` | unchanged role | retargets `api-nextgen`'s schema |
| `ui` | renamed from `inspector` | the SPA; served by `api-nextgen` at `/`. Open question 5 unaffected |
| `rig` | unchanged | RC-11 stands |

Thirteen packages, against nine today. Arriving later, one per milestone: `driver-onewire`,
`driver-system` (system configuration over the filesystem and process-exec) and `driver-store`
(user data over SQLite) — all three drivers, per the two-layer rule, not a third kind of component.

Declaring all thirteen now is not the same as building them now — the build order is the milestone
table below. The reason to declare them anyway is that RC-10's partition and the
`dependency-cruiser` DAG should be written once, against the finished shape, rather than rewritten
at each driver. The cost is that `driver-kit`'s surface gets guessed from one implementation before
`driver-extension` exists to correct it; N7's exit criteria should therefore include revisiting that
boundary explicitly rather than assuming it held.

### Naming

`driver-plc` was dropped: the whole box *is* the PLC and extensions attach to it, so "the PLC driver"
reads as covering everything — precisely what it does not do. `driver-onboard` and
`driver-extension` are a hardware distinction rather than a transport one, so they survive the local
path gaining a non-TCP route. Both are domain terms, satisfying RC-23.

Alternatives considered and rejected: `driver-section` is the most Unipi-native term (sysfs
`iogroup[1-3]`, research/02's "sections") but opaque to a newcomer; `driver-unipi-tcp` /
`driver-unipi-rtu` name the transport, which matches decision 1 honestly, but would lie the moment
the transport changes.

`driver-kit` is serviceable; `driver-runtime` is more precise, since its contents are a scan loop and
a lifecycle rather than a collection of helpers. Weak preference only.

**Why `core/` cannot survive as a package.** Its four responsibilities go to four places: registry
and aliases up to main and a `driver-store`, device model and scheduler down into drivers. Nothing
is left in the middle, and a package there would recreate the layer being removed.

**Why one package per API surface.** `api-compat` cannot leak our groups, labels or ordering into
an EVOK payload if it does not import anything that has them. G-3 and RC-24 stop being review rules
and become a missing edge in the dependency graph.

**Why `protocol` must split.** ADR-0001 has it holding the internal envelope contract *and* the
public wire schemas. One package containing both is precisely the channel through which internal
metadata reaches a compat shape.

**What main validates, and what it does not.** Driver-qualified addressing removes almost all of
it: driver ids are unique because they are YAML map keys, circuit uniqueness inside a driver is
local to that driver's own address tables (RC-18), the nextgen API routes by parsing rather than by
lookup, and compat's injectivity check belongs to `api-compat`. There is no global address
namespace left to assemble, so **startup is single-phase** — parse, validate, spawn drivers, spawn
APIs. No collect-declarations-then-validate round trip.

What survives is **resource exclusivity**, which no single component can check because each one
sees only its own config:

- two drivers configured on the same transport endpoint — the same `/dev/ttyNS0`, or the same TCP
  host and port. This is how decision 1 and G-7 are actually enforced
- two APIs configured on the same listen port
- an API's `drivers:` list naming a driver absent from the `drivers:` map
- **`autogen: true` together with `devices:` or `transport:` on the same driver** — the generated
  inventory supplies both, so this is a configuration error, not a precedence rule. "Which one won?" is
  the question ADR-0006 exists never to ask again (added 2026-08-13, ADR-0014)
- **`autogen:` on any driver other than `onboard` or `onewire`** — the only two the inventory generator
  emits sections for. A parse error rather than a silently ignored key (added 2026-08-13, ADR-0014)

All of them are **config-parse checks needing no handshake**, which is the point: they fail before
anything is spawned or any port is bound. That is also finding 2.7's fix — its evidence is port
conflicts causing systemd restart storms, detected at bind time instead of at parse time. It closes
at N2 rather than M5.

**Main must have no static import of any driver or API.** Otherwise it is a potential conduit, and
that is not statically detectable. Drivers and APIs are resolved from config by id through a
manifest. Costs compile-time knowledge of what is spawned; buys enforceability, and the plugin
loading mechanism G-6 needs arrives as a side effect rather than a retrofit.

## Config sketch

Driver and API ids are map keys, so uniqueness is free from YAML. Constrain them to
`[A-Za-z0-9_-]+` at parse: an id containing `:` or `.` makes address parsing ambiguous, and that is
unfixable later.

```yaml
# /etc/evok-node/config.yaml
drivers:
  PLC:
    type: onboard
    autogen: true                              # /etc/evok-node/autogen.yaml supplies transport
    scan:  { fast: 50ms, slow: 1s }             # and devices both — ADR-0014
    retry: { initial: 500ms, max: 30s }        # unreachable-but-configured

  EXT:
    type: extension
    transport: { kind: modbus-rtu, port: /dev/ttyNS0, baud: 19200, parity: none }
    units:
      xS11: { unit: 1, definition: modbus/unipi/xs11 }
      xG18: { unit: 2, definition: modbus/unipi/xg18 }

  OW1:
    type: onewire
    transport: { kind: owserver, host: 127.0.0.1, port: 4304 }
    discovery: { interval: 60s }               # only drivers that have it

  ADMIN:
    type: system                               # "bus" is the filesystem + process-exec
    read: [network, services, resources]

apis:
  next:
    type: nextgen
    listen:  { host: 0.0.0.0, port: 8081 }
    drivers: [PLC, EXT, OW1, ADMIN]
    ui:      true                              # served at /; no path, no root — see below

  compat:
    type: evok-compat
    listen:  { host: 0.0.0.0, port: 8080 }
    drivers: [PLC, EXT, OW1]                   # ADMIN omitted by the administrator; had it been
                                               # listed, compat would skip it — decision 10
```

Visibility scoping ships as the mechanism now — an id list at spawn; per-driver ACLs are deferred.
It also makes compat's at-most-one-onboard requirement *satisfiable* rather than merely checkable:
if two onboard drivers ever existed, showing compat only one is a config answer rather than a dead
end.

## Internal message structure

Sketch, to be settled in `messaging`. Discriminated unions throughout (RC-3), error kinds as
string literals (RC-9), expected failure as a value (RC-6).

```ts
type DriverId = Brand<string, 'DriverId'>;
type Address  = Brand<string, 'Address'>;   // "PLC:DI.2.01" — opaque outside its driver
type Seq      = Brand<number, 'Seq'>;

/** Provenance, so write arbitration can be added without a schema break (ADR-0001). */
type Origin = { readonly api: string; readonly client?: string };

type Request =
  | { readonly op: 'introspect'; readonly since?: Seq }        // since ⇒ diff
  | { readonly op: 'read';   readonly addresses: readonly Address[] }
  | { readonly op: 'write';  readonly address: Address; readonly value: Value }
  | { readonly op: 'invoke'; readonly address: Address; readonly args?: Value }
  | { readonly op: 'subscribe' | 'unsubscribe'; readonly addresses: readonly Address[] };

type Event =
  | { readonly ev: 'readings'; readonly changes: readonly Reading[] }   // always array — RC-21
  | { readonly ev: 'topology'; readonly generation: Seq }
  | { readonly ev: 'health';   readonly reachable: boolean };

type Envelope =
  | { readonly v: 1; readonly id: MessageId; readonly to: DriverId;
      readonly deadline: Millis; readonly origin: Origin; readonly req: Request }
  | { readonly v: 1; readonly id: MessageId; readonly re: MessageId;
      readonly ok: true;  readonly body: Value }
  | { readonly v: 1; readonly id: MessageId; readonly re: MessageId;
      readonly ok: false; readonly error: { readonly kind: ErrorKind; readonly detail: string } }
  | { readonly v: 1; readonly id: MessageId; readonly from: DriverId;
      readonly seq: Seq;  readonly event: Event };
```

`deadline` sits in the envelope rather than in each call site, which makes RC-14 structural for the
whole message path instead of a rule to remember. `seq` per driver makes a dropped event
detectable rather than silent.

## Introspection example

An **endpoint** is anything addressable: a channel, a structured reading, or a method. Each carries
a shape descriptor and a mandatory `effect`.

```json
{
  "driver": "OW1",
  "type": "onewire",
  "generation": 7,
  "capabilities": ["topology-events", "diff-introspect"],
  "endpoints": [
    {
      "address": "OW1:TEMP.2895DCD509000035",
      "shape":   "channel",
      "kind":    "TEMP",
      "effect":  "none",
      "returns": "float32",
      "unit":    "degC",
      "writable": false
    },
    {
      "address": "OW1:DISCOVER",
      "shape":   "method",
      "effect":  "mutates",
      "returns": "struct"
    }
  ]
}
```

Three notes.

**`effect` is mandatory in the schema, and the API decides what to do with it.** A driver can
misdeclare, but cannot omit; the API layer reads it and chooses. Worth having as a field rather
than a convention because `run` (dev id 30) and `nv_save` (id 31) existing as EVOK dev types is
what "enforcement on the driver designer" produced upstream.

**`returns` starts as a closed keyword set** in `messaging` — scalars plus `struct`. Widening it to
schema references later is additive internally, and exhaustive switching turns every affected site
into a compile error. The consequence to state plainly: with one `struct` keyword, `api-nextgen` is
generic over scalars and hand-written over structures. The keyword set must not leak verbatim into
`api-nextgen`'s *public* schema, or widening it later becomes a public break.

**There is no `compat` block, deliberately.** If a driver declared its own EVOK projection, EVOK's
vocabulary would be back inside every driver — the exact coupling this re-steer removes.
`api-compat` owns the table and derives `(dev, circuit)` from `(driver type, kind, address tail)`.
That does impose one convention on Unipi drivers: the address tail must be mechanically projectable
(`PLC:DI.2.01` → `2_01`, `EXT:DI.xS11.02` → `xS11_02`). Non-Unipi plugin drivers carry no such
obligation — nothing marks them as excluded, compat's table simply has no entry for them.

**Projectability is never a property a driver declares.** A driver publishes its endpoints
neutrally; whether any of them reaches the compat surface is decided entirely by `api-compat`'s
table. Decision 10, applied to endpoints rather than to whole drivers.
