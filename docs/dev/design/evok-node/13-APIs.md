# 13 — APIs

## 1. Scope

What every api must be, whatever it speaks. Each api's own file — 15 WS API, 18 Home API, 20 Matter bridge API (today 16a) — specialises this one and does not restate it. This file is also the guide for writing an api of your own (§10).

```
client (published: wire types, TS client)
   ▲ types
ws-kit ── sessions, hello, relay to messaging, subscription fan-out, WS extensions      designed in 15
   ▲                                   ▲
api-ws ── every driver, serves the inspector     api-home ── home driver only, 12a §5 subset
api-matter-bridge ── on its own, not on ws-kit
api-<plugin> ── e.g. MQTT (§10)
```

**Not for:**

- A wire protocol. That is each api's own file.
- Authentication, users, roles, proof. That is 13a; this file only says where it sits (§5).

**Must not depend on:** `main`, any driver package except for a driver's published types (`DeviceType`s an api for one driver knows — 12a's for 18 and 20).

## 2. Terms

| Term | Means | Manifest `kind` |
|---|---|---|
| **api** | an instance under `apis:` in config | — |
| **API module** | the package code behind an api's `type` | `api` |
| **API plugin** | an API module we do not ship — same sense as a driver plugin (01 §10) | `api` |
| **WS extension** | a hook inside `ws-kit`: `onConnection` (auth, language), `onRequest` (ACL, localization) — 15 | `ws-extension` |
| **relay api** | speaks our messaging model on the wire: addresses, methods, `ResponseError` (WS API, Home API) | — |
| **mapping api** | translates to a foreign model (Matter, MQTT, a REST plugin) | — |

Packages are named `api-<name>`.

## 3. An API module

An API module is a module like a driver (02 §4): a `ModuleDescriptor`, a `ModuleInstance`, resolved through the manifest, hosted by the runner. Two differences:

- **Its links are `drivers:`** (03 §8), main's own field, stripped before the module's schema runs. Nothing else in its config says which drivers it reaches.
- **Nothing addresses it.** Only a `DriverId` is addressable (03 §3), so an api never calls `onRequest` (03 §4).

```yaml
apis:
  ws:     { type: ws,            drivers: [ONB, EXT1, home, kv, sys] }
  home:   { type: home-api,      drivers: [home, kv] }
  matter: { type: matter-bridge, drivers: [home, kv] }
  mqtt:   { type: mqtt,          drivers: [ONB], broker: { url: 'mqtt://nas:1883' } }
```

**Placement** (01 §3). `worker_thread` by default. `child_process` is recommended for an api that uses native code or computes for long stretches; it is a recommendation, nothing checks it. There is no "heavy" declaration: every instance already has its own event loop.

**Lifecycle**, an api's side of 02 §6:

| Step | The api |
|---|---|
| `configure` | builds its projection (§6); does not listen yet |
| `start` | listens or connects; a bind error (`EADDRINUSE`) rejects `start` with the port named (§9) |
| `drain` | takes no new client requests; requests in flight finish within their deadlines |
| `stop` | closes listeners and client connections |
| no `reload` | it is stopped and started again (02 §5.1); clients reconnect |

## 4. State

An api holds no device state (01 §2). Everything it holds is one of two kinds:

| Kind | Examples | Where | After a restart |
|---|---|---|---|
| **Translation state** | sessions, client subscriptions, the projection (§6), schema cache, the MQTT topic ↔ address map | memory | rebuilt |
| **Protocol identity state** | Matter fabric table, operational keys, IPK, ACLs, fabric-scoped bindings, the tail → endpoint-number map, message counters (16a); a TLS key and certificate | KV, namespace `api.<id>` (06 §2); secrets as sensitive keys (06 §5a) | kept |
| ~~Device state~~ | values, last known values | a driver | — |

**The test.** Delete it and restart the api:

- clients only reconnect → translation state;
- clients lose pairing or trust → protocol identity state;
- anything else → device state, so it belongs in a driver.

Rules:

- An api has no user data besides its identity state. Settings are config; which devices to expose is a driver's (12a's `exposed`).
- An api with identity state lists the KV driver in `drivers:`.
- Renaming an api's id is a new namespace (06 §2): a Matter bridge is paired again.
- The opposite case — evok-node as a protocol **client**, e.g. 12a's own Matter controller (12a §4a) — is a driver, and its fabric is that driver's user data.

```ts
// api-matter-bridge, start()
const fabrics = await kv.get('fabrics')        // api.matter — the KV driver derives it from Origin
if (fabrics === null) openCommissioningWindow()
```

## 5. The gate

**Every message to a driver has passed an api's authentication and ACL.** A driver trusts the call it gets. There is no user model shared by all apis: each api authenticates in its own way (13a for apis on `ws-kit`, fabrics for Matter, whatever a plugin brings).

- `Origin.client` (03 §2) is for logs and debugging. Nothing decides on it.
- A refusal by the gate is the api's own wire error, not an `ErrorKind` (03 §7): the driver never sees the call.

**A driver that needs the user** — a door lock recording who opened it (12c-09 §1.2) — takes it as a method argument, annotated so that no client can choose it:

```ts
// @evok-node/module-sdk
interface Actor {
  readonly realm: string;    // whose user namespace: 'idp' (13a's identity provider), 'matter', a plugin's own
  readonly id?: string;      // the user in that namespace; absent = no user known
  readonly name?: string;
}
Codecs.actor(): TypedCodec<Actor | undefined>   // an optional struct member, schema annotated `actor: true` (05a §3.1a)

// a method that needs the user and proof — 12c-09
unlock: method('mutates', Codecs.void, Codecs.struct({ by: Codecs.actor() }), { errorKinds: ['blocked'], proof: true }),
```

| Annotation | On | The api |
|---|---|---|
| `actor` | a struct member of a method's arguments | **always overwrites it** with its own caller: realm and user; or removes it. What the client sent there is never relayed. |
| `proof` | a method (`MethodType`, 05a §3.1) | gets the extra proof its auth asks for (13a: a PIN, a confirmation) before relaying; an api that cannot obtain proof refuses the call |

| Caller | `actor` reaches the driver as |
|---|---|
| WS or Home API, logged-in user | `{ realm: 'idp', id: 'u-42', name: 'Tomas' }` |
| WS or Home API, PIN | the user the PIN resolves to (13a) |
| Matter bridge | `{ realm: 'matter' }`, plus the user when Matter supplies one |
| MQTT plugin with no users | `{ realm: 'mqtt' }` |
| a rule or another driver | what that caller passes; a rule passes none |

A driver forwarding the call passes the argument on as it got it — 12c-09's `lock-from-2n` hands `by` to the 2N driver's `grantaccess`, whose argument is annotated `actor` too. A driver that maps users accepts only realms it knows (12e maps `idp`).

For a relay api, `actor` and `proof` are handled by WS extensions (15): the auth extension knows the session's user, the ACL extension reacts to `proof`.

## 6. Consuming drivers

```ts
// 03 §4
ctx.messaging.links()                  // [{ driver: 'ONB', up: true }, { driver: 'home', up: false }]
ctx.messaging.onLink((driver, up) => …)
```

- **The api's drivers are `links()`**, live across a reload. `reload(config)` never carries `drivers:`, so an api learns about an added or removed driver only here.
- **The projection is built from introspection** with `followIntrospection` (05a §4b), one per linked driver. It is translation state (§4).
- **A generic api acts on the value-type vocabulary only** and never switches on `kind` (01 §6). An api for one driver — Home API, Matter bridge — may know that driver's kinds.
- **A driver the api does not understand is skipped**, not refused (01 §9). A Matter bridge linked to `ONB` exposes nothing from it and logs it once.
- **One internal subscription per address**, fanned out to every client that wants it; the api does not cache its values.
- Cross-driver reads go through `module-sdk`'s fan-in helper (03 §2); typed access through `remote`/`remoteDevice` (05a §3.8a).

## 7. Driver loss and return

What 03 already does underneath, and what the api adds:

| Internally | Already done (03) | The api |
|---|---|---|
| driver crashes | calls in flight answer `link-down` (§7); subscriptions stay in the want-list (§6.3) | `onLink(d, false)` → tells its clients `d` is down |
| driver back | want-list replayed, `Seq` restarts (§6.3); `followIntrospection` gets `full` with a new `epoch` (§5a) | `onLink(d, true)` → `GET` each subscribed address, sends the values |
| reload with a new endpoint table | `$introspect` change (§5a) | updates its projection; tails that vanished end their client subscriptions |
| device `unreachable` | the driver answers `unreachable` | relays it; never an old value |
| the api itself restarts | client connections drop | clients reconnect and subscribe again (`client` does it) |

`onLink(d, true)` fires after the want-list replay is sent, so the `GET`s see the subscriptions in place.

**What a client is promised:**

1. A gap is always reported — down, then up.
2. After up, a fresh value for every subscription.
3. A write is never re-sent.
4. Nothing is served while the driver is gone: the api holds no values.

## 8. Errors

| Api | Sends |
|---|---|
| relay | `ResponseError` (03 §2) as it is: `kind`, `domainErrorKind`, `detail`, `info` |
| mapping | its own codes, mapped from `kind` — guidance below; each api's file has its table |

**One rule for both:** for `internal-error`, `detail` and `info` do not leave the daemon. The api logs them with a reference and sends the reference.

```json
{ "ok": false, "error": { "kind": "domain-error", "domainErrorKind": "blocked", "detail": "switch locked out" } }
{ "ok": false, "error": { "kind": "internal-error", "ref": "a81f3c" } }
```

Mapping guidance:

| `ErrorKind` | Category | HTTP |
|---|---|---|
| `unknown-address` | not found | 404 |
| `unsupported-method` | not allowed | 405 |
| `bad-payload` | invalid | 400 |
| `domain-error` | rejected, with `domainErrorKind` | 409 |
| `not-ready`, `unreachable`, `link-down` | unavailable | 503 |
| `timeout`, `deadline-exceeded` | timeout | 504 |
| `internal-error` | internal | 500 |

## 9. Listening

- **Defaults, not config.** Transport and port are each api's own (15, 18, 20); `listen` in config is optional and only overrides the port, host or TLS.
- **No declaration to `main`.** A port clash reports itself: `bind` fails, `start` rejects naming the port, `main` logs it. 02 §7's parse-time warning stays for drivers, whose serial lines do not refuse a second opener.
- Two apis cannot share one port.

## 10. Writing an api

The minimum is a `ModuleDescriptor` (02 §4). Worked example, MQTT — publish state, accept commands, topics from introspection:

```ts
export default {
  schema: MqttConfig,
  isConfigEqual: deepEqual,
  createInstance(ctx) {
    const offs: (() => void)[] = []
    let cfg: MqttConfig
    return {
      async configure(c) { cfg = c },
      async start() {
        const broker = mqtt.connect(cfg.broker.url)
        const follow = (d: DriverId) =>
          offs.push(followIntrospection(sourceOf(ctx, d), a => project(d, a)))   // tail ↔ evok/<driver>/<tail>
        ctx.messaging.links().forEach(l => follow(l.driver))
        offs.push(ctx.messaging.onLink((d, up) => {
          broker.publish(`evok/${d}/$up`, String(up), { retain: true })
          if (up) refresh(d)                                                     // GET every subscribed address — §7
        }))
        broker.on('message', (topic, msg) => write(topic, msg))                  // evok/<driver>/<tail>/set → SET, CALL
      },
      async drain() { offs.forEach(off => off()) },
      async stop()  { /* close the broker connection */ },
    }
  },
} satisfies ModuleDescriptor<MqttConfig>

// IntrospectionSource (05a §4b) over ctx.messaging — a few lines
const sourceOf = (ctx, d) => ({
  get: since => ctx.messaging.introspect(d, since).then(bodyOrThrow),
  watch: on => (ctx.messaging.subscribe(address(d, tail('$introspect')), e => on(e.value)),
               () => ctx.messaging.unsubscribe(address(d, tail('$introspect')))),
})
```

| Do | Don't |
|---|---|
| Build the projection from introspection (§6) | switch on `kind` in a generic api |
| One internal subscription per address, fan out | cache values for clients |
| Overwrite `actor`, honour `proof` (§5) | relay what a client put in an `actor` member |
| Map errors; keep `internal-error` inside (§8) | send tails or stacks in errors |
| Log with 04's logger | retry writes |
| Reach drivers only through `ctx.messaging` | open a driver's resource yourself (01 §7) |

MQTT is an example here, not a shipped package.

## 11. Testing

Tier 1 (basics/03), with fixture drivers from 03 §12:

- **Gate:** a client value in an `actor` member never reaches the fixture; a `proof` method without proof never reaches it.
- **Loss and return:** kill the fixture worker — clients see down; respawn — clients see up and a fresh value per subscription; a write in flight is not re-sent.
- **Errors:** `internal-error` leaves with a reference only; the log holds the detail under it.
- **Unknown driver:** a linked driver of an unknown introspection `type` is skipped, the api starts.
