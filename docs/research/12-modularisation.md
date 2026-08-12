# Driver/api/main modularisation — the 2026-08-12 re-steer

**Status: accepted 2026-08-12 and landed**, in one change across `GOALS.md`, `roadmap.md`,
`bug-dispositions.md`, `rules/code.md`, `CLAUDE.md`, `STATUS.md` and the package skeleton — together,
because these documents cross-reference heavily and a half-migrated state is worse than either end.

Recorded as [ADR-0001](../adr/0001-drivers-apis-and-main.md) through
[ADR-0004](../adr/0004-single-threaded.md). **Read the ADRs to know what was decided; read this to
know why, and why not the alternatives** — it keeps the arguments that did not survive scrutiny,
which the ADRs only name.

One item here was **not** settled and needs Tomas: G-7's `unipitcp` clause. See §Genuinely open
below, and open question 1 in [`STATUS.md`](../plan/STATUS.md).

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

All three are **config-parse checks needing no handshake**, which is the point: they fail before
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
    transport: { kind: modbus-tcp, host: 127.0.0.1, port: 502 }
    scan:  { fast: 50ms, slow: 1s }
    retry: { initial: 500ms, max: 30s }        # unreachable-but-configured

  EXT:
    type: extension
    transport: { kind: modbus-rtu, port: /dev/ttyNS0, baud: 19200, parity: none }
    units:
      xS11: { unit: 1, model: xS11 }
      xG18: { unit: 2, model: xG18 }

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

## Milestone changes

Old M0–M6 becomes eleven smaller milestones. More milestones, each under a page, which is what RP-5
asks for anyway.

| New | Was | Goal |
|---|---|---|
| N0 | M0 | Re-steer + scaffolding fix |
| N1 | M1 | Fixtures & simulator — **still before any driver**; it is the only test substrate |
| N2 | — | `messaging` + `main`: config, spawn, supervise, reload, envelope round-trip tests |
| N3 | M2 | Transport |
| N4 | M3 | Definitions & device model |
| N5 | — | `driver-kit` + `driver-onboard`, with introspection, verified against the simulator, no API. **Nextgen envelope drafted here**, against real introspection rather than in the abstract |
| N6 | — | `api-nextgen` — WS, then HTTP. Hardens the N5 draft; adds no driver-specific shape |
| N7 | — | `driver-extension` + nextgen support; **`driver-kit`'s boundary revisited** now a second implementation exists |
| N8 | — | `driver-onewire` |
| N9 | M4 | `api-compat` — where the seven M4-only findings close |
| N10 | M5+M6 | Operability, hardening, `0.1.0-beta` |

**N2 before N3 is deliberate.** Main can be built and tested against a stub driver, which forces
the driver contract to be defined against a stub rather than inheriting `driver-onboard`'s accidental
shape.

**N1 stays before the drivers.** "PLC driver and proper testing" needs generated address tables and
the simulator; there is no hardware to test against. The rig is human- and purchase-blocked (the
second M527 is not ordered), so it runs as a parallel track and cannot be a gate — RP-7.

**The capture trip stays urgent.** Demoting compat is a tempting reason to defer it. The
transcripts are unrecoverable once EVOK leaves those Patrons; they are simply consumed later.

### Task this proposal creates

Written in the RP task format, to be placed in `milestones/N5.md` with a real number and issue when
this lands. It exists because the envelope becomes public at N6, and N5 is the last milestone at
which changing it is free.

```markdown
### T5.x — Nextgen envelope expressiveness check     `#TBD` `area/protocol` `risk/high`
Validate that the driver-agnostic envelope drafted at N5 can already express every shape research
documents, using `driver-onboard`'s real introspection plus the map corpus for the rest.
**Done when:** a fixture-backed table maps each of — per-channel mode sets and per-model mode enums
(the N4 Edge obligation), a reading whose value is a structure, several readings under one device id
(1-Wire's `humidity`/`vdd`/`vad` on one ROM id), AI/AO scaling and units, and an effectful method —
onto the envelope with **no driver-specific field** (decision 9). Every gap either closes in the
same PR or is recorded as a deliberate exclusion with a reason.
**Refs:** research/01 §2 and §4, research/05 §8.3, decision 9, RC-20
```

## Impact on completed M0 work

Cheap now — STATUS records every package entrypoint as a placeholder export.

| Task | Impact |
|---|---|
| T0.1 workspaces, nine packages, READMEs | **Rework.** Rename, split, rewrite the "must not depend on" notes |
| T0.2 strict TS base | **Keep entirely** |
| T0.3 eslint + dependency-cruiser DAG | eslint keeps; **the DAG is rewritten** with RC-10 |
| T0.4 vitest projects, coverage floors | **Mechanical remap** of package names |
| T0.5 CI workflows | **Keep**; required-check names unchanged |
| T0.6 hygiene + licence · T0.8 `verify` | Not started — unaffected |
| T0.7 ADRs for the settled decisions | **Not started, which is lucky.** Written once against the new design instead of twice |

## Rule changes

| Rule | Change |
|---|---|
| **RC-10** | Rewrite. `core`/`server` no longer exist. New form: no driver imports an API, no API imports a driver, `main` statically imports neither, everything crossing is a serialisable envelope. Stronger than today's one-directional rule — it is a partition, and fully checkable |
| **RC-24** | Rewrite. Translation moves from `@evok-node/protocol` to `api-compat` alone, derived from introspection. Add: no driver declares EVOK vocabulary |
| **RC-12** | Internal schemas live in `messaging`; each API package owns its own public wire schema |
| **RC-1** | Add `DriverId`, `Address`, `Seq`, `MessageId` brands. `Circuit` becomes compat-side only |
| **RC-18** | Splits in two: per-driver local uniqueness, fatal at driver init; compat projection injectivity, fatal at API start but **non-fatal on hot-plug** — keep the old table and report loudly, since a colliding extension must not take down a running API |
| **RC-20** | Note that a reading's value may be a structure, not only a scalar. Read-only `netconf` is a structured reading, which is why G-5 needs no new category |
| **new RC** | Every request envelope carries a deadline; there is no way to send one without |
| **new RC** | An introspection descriptor's `effect` field is mandatory, with no default |
| **new RC** | **An API's public schema names no driver type.** Decision 9. Adding a driver must not require an API release — checkable in review, and largely greppable |
| **new RC** | An API skips a driver type it does not understand, and **says so once at startup** naming the driver and its type. Skipping is correct; silent skipping is finding 3.5's shape |
| **new RC** | `api-compat` requires **at most one** onboard driver — zero is the Gate, which must serve an empty API rather than erroring (research/09 §Gate), and two would make its flat namespace ambiguous |

Also asymmetric and worth writing down: config validation failing at **boot** is fatal; failing at
**reload** is not — keep running the current configuration and report the rejected one. Same validation,
opposite failure behaviour, and the natural implementation shares the code path and inherits the
wrong one.

## GOALS and ADR changes

Smaller than expected, because the goal is unchanged.

- **G-1** — amend from core↔API to N drivers ↔ M APIs. The substance holds.
- **G-2 / ADR-0009** — no change in substance; add a note that it is now structural for a better
  reason than configuration. `api-compat` can only emit what its projection table describes, and the
  table has no entry for a `system` driver — so admin cannot reach the compat surface even if an
  administrator lists it.
- **G-5 / ADR-0005** — **no change.** Read-only device config is a structured reading. The gap
  reopens only if writing device config arrives, which is deliberately later.
- **G-7** — no change; decision 1 above is how it is enforced.
- **ADR-0001** — amend, do not supersede. Add driver identification, visibility scoping, and
  confirm the envelope's provenance requirement is met by `Origin`.
- **New ADRs:** driver/api/main modularisation · the addressing scheme · introspection as the
  source of compat's table · main is never in the data path · **single-threaded, and why not
  `worker_threads`** (recording the reasoning so it is not relitigated).

## Settled in review, and what is left open

Most of what started as open questions closed during the discussion. Recorded here with the
reasoning, since it is the reasoning that gets relitigated.

- Nextgen WS API: a new surface rather than an extension of EVOK's, forced by G-2 and RC-24 rather
  than chosen for taste. **Settled** — it is designed incrementally alongside the drivers, and
  decision 9 is what makes that safe. Its one residual question is T5.x above, not an open item.
- **Serving the `ui`.** Settled: `api-nextgen` serves the built assets at `/`, same origin, one
  boolean `ui: true|false`. No path and no root — if an operator wants it elsewhere they set
  `ui: false` and deploy the SPA themselves pointed at nextgen.
  Reasons, in order: a greenfield install must work with no EVOK ever present (the drop-in
  guarantee), and generating an nginx site is finding 4.7's exact failure class, ten "fix
  autodetection nginx" commits deep; same origin means no CORS and no endpoint configuration; and the
  SPA does control and configuration, so its trust boundary should be `api-nextgen`'s rather than an
  nginx config we already know goes wrong.
  **Consequences of `/`.** The SPA becomes the catch-all fallback, so API routes take precedence and
  no collision check is needed — but nextgen's reserved route prefixes then cannot change later
  without breaking SPA deep links. Worth choosing them once, at N6.
  **Asset location is a packaging constant, not a config key** — the Debian package places the
  assets, `api-nextgen` serves that path, and the dev tree resolves to `packages/ui/dist`. That
  resolution belongs in the config module, since RC-16 bans `process.env` elsewhere. Keeping it a
  *path* rather than a bundled import is what avoids a workspace edge from an API package to a UI
  package, so nothing imports `ui` and open question 5 stays untouched.
  **Narrowing worth naming:** the shipped SPA is single-instance by construction. G-4's
  aggregate-several-instances case is served either by a user adding instance URLs at runtime — that
  is user data, client-side, not foreclosed — or by the `ui: false` deploy-your-own path.
- **Two vocabulary collisions to settle before code, not after.**
  `data_point` is already a specific EVOK type (id 24, `<device_name>_<register_address>`); if it
  also means "any addressable value" internally, that will bite. This proposal uses **endpoint** for
  the generic sense.
  The second one is **resolved**: `inspector` becomes `ui`, since `introspect` is load-bearing in the
  message contract and `inspector` was a package name nothing depended on yet. Two words one letter
  apart, one a package and one a message op, was a collision waiting to happen.
- 1-Wire: **not a grammar question after all.** Decision 6 already makes the tail driver-defined, so
  `driver-onewire` answers at both levels — the device, and each reading as a suffix under it. Only
  the envelope half stays in T5.x: it must be able to carry a device with several readings beneath it.
  The driver declares both levels neutrally; **`api-compat` picks**. EVOK's 1-Wire payload is
  device-level with the readings as fields of one object, so compat's table selects the device
  endpoint and simply does not map the reading-level ones — which is why it must not map both, or it
  would invent circuits EVOK never had (G-3, RC-24).
- Retry for a never-yet-reachable device and backoff for a flapping one are the same machinery, and
  finding 4.2 is precisely that machinery resetting on any success.

### Genuinely open — and one contradiction to resolve

- **G-7 versus `driver-onboard`.** G-7's startup preflight "refuses loudly if evok or `unipitcp` is
  active". But EVOK never speaks SPI: local I/O *is* Modbus TCP to `unipitcp` on `127.0.0.1:502`
  (raw-hardware-research §166, and the `en:sw:02-apis:02-modbus-tcp` KB page). So `driver-onboard`
  needs `unipitcp` running, and G-7 as written forbids exactly that. One of the two is wrong.
  Most likely G-7 means the RS-485 ttys and `evok` itself, and `unipitcp` was swept in by mistake —
  but this is a GOALS amendment, so it is Tomas's call, not an agent's. **Resolve before N5**, since
  it decides whether `driver-onboard` has a transport at all.
- `driver-kit` versus `driver-runtime` as a name: weak preference for the latter, since its contents
  are a scan loop and a lifecycle rather than a collection of helpers. Not worth blocking on.
- Whether `T5.x`'s exclusions list ends up needing an ADR of its own, or fits as a note in the
  addressing ADR.
