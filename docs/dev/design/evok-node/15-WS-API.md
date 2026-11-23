# 15 — WS API

## 1. Scope

The WS API (`api-ws`, config `type: ws`) is evok-node's own api. It relays internal messaging (03) over a WebSocket to the Inspector UI (16), the shell app (13b), other PLCs (05a §3.8b, 12a §4b) and scripts. It is a relay api (13 §2): this file specialises 13 and does not restate it.

`ws-kit` is its base, and the Home API's (18): connection, messages, relay, subscriptions and the extension host. §2–§7 are `ws-kit`; what belongs only to the WS API says so.

**Not here:**

- Who the caller is and what they may do — 13a, the `auth` and `acl` extensions.
- Session language and resolving `LocalizedText` — 13c, the `l10n` extension.
- Which package holds which part — M3.15.

```yaml
apis:
  ws:
    type: ws                        # listens on 8401; TLS by listen.tls (13 §9)
    drivers: ['*', main]
    publicUrl: https://byt3.t86.cz:8401
    extensions:
      - { use: auth, config: { idp: auth } }
      - { use: acl,  config: { idp: auth } }
      - { use: l10n, config: { defaultLang: cs } }   # after acl — 13c §5
```

## 2. Connection

```
client                                        ws-kit
 ── HTTP upgrade (Origin checked) ──────────▶
 ── { type: 'hello', v: 1, … } ─────────────▶
                                              onConnection of each extension, in list order
 ◀────── an extension's own messages ──────▶   e.g. 13a §9.1: auth_required, auth, auth_ok
 ◀── { type: 'hello', v: 1, apiId, … } ─────   the session is open
 ── requests ───────────────────────────────▶
```

- **Origin.** An upgrade with an `Origin` header must match `publicUrl`'s origin, else HTTP 403. An upgrade without one (another PLC, a script) passes; it is not a browser.
- **The client hello** is the first message, within 10 s. ws-kit reads `v` and `client`; other keys belong to the extensions that document them (13c's `lang`).
- **Extensions in list order.** Each `onConnection` may exchange its own control messages with the client (§7) and may reject. A rejection closes the connection with the extension's code; the following extensions do not run.
- **The server hello** opens the session. Nothing but control messages before it.

```ts
// @evok-node/client — wire types
interface ClientHello {
  readonly type: 'hello';
  readonly v: 1;                        // wire protocol version (§12)
  readonly client?: string;             // e.g. 'inspector/1.4.0' — for logs only
  readonly [key: string]: Value;        // the extensions' keys, e.g. lang (13c)
}

interface ServerHello {
  readonly type: 'hello';
  readonly v: 1;
  readonly apiId: ApiId;                // the SPA warns before a change reloads this api (02a §7)
  readonly evokNodeVersion: string;     // a remote's version, checked by 12a §4b
  readonly session: string;             // the session id, sent inside as Origin.client (§5)
  readonly limits: Limits;
}

interface Limits {
  readonly maxMessageBytes: number;     // 1 MiB — a message from the client
  readonly maxSubscriptions: number;    // 10 000 per session
  readonly defaultTimeoutMs: number;    // 5 000
  readonly maxTimeoutMs: number;        // 600 000
}
```

ws-kit's close codes. An extension's codes are in its own doc (13a §9.1).

| Code | When |
|---|---|
| 1001 | the api drains or stops (13 §3) |
| 1003 | a binary frame |
| 1009 | a message above `maxMessageBytes` |
| 4400 | not JSON; not a message of §3; no hello first; a request before the server hello |
| 4408 | no hello within 10 s (13a uses it for `auth` too) |
| 4426 | `v` not supported (§12) |
| 4429 | the client does not read its events (§6.3) |

## 3. Messages

The messages of 03 §2, as JSON text frames, with three differences:

| Field | Inside (03 §2) | On the wire |
|---|---|---|
| `origin` | stamped by `main` | not sent; the api builds it (§5) |
| `deadline` | absolute | `timeoutMs`, relative — the client's clock may differ |
| `v` | on every message | once, in the hello |

```ts
// @evok-node/client — wire types
type ApiAddress = `$${string}`;                                   // §4

interface WireRequest {
  readonly id: string;
  readonly address: Address | ApiAddress;
  readonly method: Method;
  readonly payload?: Value;
  readonly options?: Readonly<Record<string, Value>>;
  readonly timeoutMs?: number;
}

type WireResponse =
  | { readonly re: string; readonly ok: true;  readonly body: Value }
  | { readonly re: string; readonly ok: false; readonly error: WireError };

interface WireEvent {
  readonly address: Address | ApiAddress;
  readonly seq?: Seq;                                             // absent: the api's own read (§6.2)
  readonly value?: Value;
  readonly error?: WireError;                                     // only on the api's own read
}

interface Control { readonly type: string; readonly [key: string]: Value }   // hello, extensions' messages

type WireError =
  | ResponseError                                                 // a driver's, as it is (13 §8)
  | { readonly kind: 'internal-error'; readonly ref: string }     // 13 §8
  | { readonly kind: string; readonly code: string; readonly detail?: string };  // a refusal: 'ws' below, or an extension's ('auth', 13a)
```

```jsonc
→ { "id": "7", "address": "ONB:2.unipi.ro.04", "method": "SET", "payload": true, "timeoutMs": 3000 }
← { "re": "7", "ok": true, "body": true }
← { "address": "ONB:2.unipi.ro.04", "seq": 812, "value": true }
```

- **Kinds by their fields,** as inside: `type` → control, `method` → request, `re` → response, else an event.
- **`id`** is the client's, unique among its requests in flight.
- **Order.** Responses in any order. Events for one address in order.
- **`maxMessageBytes`** limits what the client sends. What the api sends is not limited: an introspection can be larger.

| `{ kind: 'ws', code }` | When |
|---|---|
| `duplicate-id` | `id` of a request still in flight |
| `too-many-subscriptions` | above `maxSubscriptions` (§6.1) |

## 4. Api addresses

An address that starts with `$` and has no `:` belongs to the api, not to a driver. Only ws-kit defines them. The hooks (§7) run on them as on any address.

| Address | Methods | |
|---|---|---|
| `$links` | GET, SUBSCRIBE | `[{ driver, up }]` — the drivers this api relays; not `kv`, not private links (§5) |
| `$upload` | CALL | a ref for one HTTP upload (§9) |

```jsonc
→ { "id": "1", "address": "$links", "method": "SUBSCRIBE" }
← { "re": "1", "ok": true, "body": null }
← { "address": "$links", "value": [{ "driver": "ONB", "up": true }, { "driver": "home", "up": true }] }
← { "address": "$links", "seq": 2, "value": [{ "driver": "ONB", "up": true }, { "driver": "home", "up": false }] }
```

- `$links` changes on `onLink` (13 §6). Its `seq` is the api's own counter.
- **A driver going down in `$links` is the only report of a gap** (13 §7). Up again, every subscription to it gets a fresh value (§6.2).

## 5. Relay

What ws-kit does with a request after the `beforeRequest` hooks (§7):

| Step | |
|---|---|
| driver | must be relayed: in `drivers:`, not `kv` (13 §6), not an extension's private link (§7) — else `unknown-address` |
| field marked `inClients: 'forbidden'` (05a §3.1b) | `unknown-address`, as if it did not exist |
| `{ "$upload": ref }` in the payload | replaced by the uploaded bytes (§9) |
| `origin` | `{ instanceId: <apiId>, instanceType: 'api', client: <session id> }` |
| `deadline` | now + `timeoutMs` (`defaultTimeoutMs` if absent), clamped to `maxTimeoutMs` |
| `id` | a new internal `MessageId`; the session maps it back to the client's |
| call progress | `<driver>:$getCallProgress.<client id>` becomes the internal id (03 §6.4) |
| response | `afterRequest` hooks in reverse order; errors as 13 §8 |

`options` (05a §3.5a's `returnFields`, `since`) and `$refs` (05a §3.10) are relayed as they are.

## 6. Subscriptions

### 6.1. Fan-out

- **One internal subscription per address** for the whole api, however many sessions want it. The last session to leave unsubscribes it (13 §6).
- `SUBSCRIBE` answers `ok`, `body: null`, once the session is registered; the current value follows as an event (§6.2).
- A session's subscriptions end with the session. At most `maxSubscriptions` per session.
- **`$introspect`** (03 §5a) is subscribed like any address, `since` in `options`. The `afterIntrospect` and `onPush` hooks give each session its own payload (§7).

### 6.2. Events

- A driver's event goes out with its `seq`, after the `onPush` hooks.
- **An event without `seq` is the api's own read** — a `GET` ws-kit sends after a `SUBSCRIBE`, and for every subscription when its driver comes back (13 §7). It is dropped if a driver's event for that address arrived after the `GET` was sent. A failed read goes out as `error` (`unreachable`), never an old value.
- **`seq` only orders:** higher is newer, for the same address. A jump is not a loss — a session sees a subset of the driver's events, and §6.3 drops superseded ones. Loss only comes with a driver going down, and `$links` reports it.

```jsonc
→ { "id": "4", "address": "ONB:2.unipi.di.01", "method": "SUBSCRIBE" }
← { "re": "4", "ok": true, "body": null }
← { "address": "ONB:2.unipi.di.01", "value": false }               // the api's read
← { "address": "ONB:2.unipi.di.01", "seq": 1207, "value": true }   // the driver's event
```

### 6.3. Backpressure

- **Per session, per address, one event waits at most;** a newer one replaces it (as 03 §6.3).
- ws-kit writes to the socket while its buffer is under `highWaterBytes`; above it, events wait as above. Responses are never replaced and count to the buffer.
- A buffer above `highWaterBytes` for `stallMs` closes the connection with 4429 (§11).

## 7. Extension host

A WS extension is a plugin inside a ws-kit api (13 §2, 02b §5.2): created once at the api's start, with its own config and private links. auth, acl (13a) and l10n (13c) are extensions; ws-kit knows none of them.

```ts
// a ws-extension plugin, nestable (02b §5.2); declaredLinks are its private drivers (03 §8)
interface WsExtensionDescriptor<Config> extends Configurable<Config> {  // meta, config, rules, declaredLinks — 02b §5.1
  create(ctx: ExtensionContext, config: Config): WsExtension;         // once, at the api's configure
}

interface WsExtension {
  readonly messageTypes?: readonly string[];                       // control types it owns, e.g. ['auth'] (13a §9.1)
  onConnection?(session: Session): Promise<void>;                  // throw WsRefusal to close with its code
  onMessage?(session: Session, msg: Control): void | Promise<void>; // its types, once the session is open
  onClose?(session: Session): void;
  beforeRequest?(ctx: RequestCtx): void | Promise<void>;           // may change ctx.msg, or ctx.refuse(…)
  afterRequest?(ctx: ResponseCtx): void;                           // may change ctx.res
  beforeIntrospect?(ctx: IntrospectCtx): void;
  afterIntrospect?(ctx: IntrospectCtx): void;                      // filter or annotate ctx.payload
  onPush?(session: Session, push: WireEvent): WireEvent | null;    // events going out; null drops it
  httpRoutes?(): readonly HttpRoute[];                             // §8
  mdnsTxt?(): Readonly<Record<string, string>>;                    // §8, e.g. nodeId and key fingerprint (13a §12)
  stop?(): Promise<void>;
}

interface Session {
  readonly id: string;
  readonly hello: ClientHello;
  readonly upgrade: { readonly ip: string; readonly headers: Readonly<Record<string, string>> };  // after trustedProxies (§8)
  readonly state: Record<string, unknown>;          // memory only; one key per extension, e.g. state.auth (13a §9.1)
  send(msg: Control): void;
  receive(type: string, timeoutMs: number): Promise<Control>;   // only inside onConnection
  close(code: number, reason?: string): void;
}

class WsRefusal extends Error { constructor(readonly code: number, readonly reason?: string) }

interface RequestCtx  { readonly session: Session; msg: WireRequest; refuse(error: { kind: string; code: string; detail?: string }): void }
interface ResponseCtx { readonly session: Session; readonly msg: WireRequest; res: WireResponse }
interface IntrospectCtx { readonly session: Session; readonly driver: DriverId; payload: Value }

interface ExtensionContext {
  readonly api: { readonly id: ApiId; readonly publicUrl: string };
  // the api's view — what its clients see; calls carry the api's Origin and skip the hooks (13 §5)
  introspection(): Introspection;  onIntrospection(cb): void;  onLink(cb): void;
  get(address); set(address, value); call(address, args); subscribe(address, cb): Subscription; unsubscribe(sub);
  // its own declaredLinks only
  private(driverId: DriverId): { get; set; call; subscribe; unsubscribe; onLink };
  readonly log: Logger;                             // 04
}
```

- **Onion order.** `onConnection` and `before*` run in list order; `after*` and `onPush` in reverse. `session.state` is how one extension leaves typed data for the next (auth → acl); each extension exports the type of its key.
- **Control messages.** During `onConnection` the client sends only what the running extension `receive`s; anything else closes with 4400. Once the session is open, a control message goes to `onMessage` of the extension owning its `type` (13a's renewal); an unowned type is ignored. Two extensions claiming one type fail the api's `start`.
- **Memory only.** An extension keeps sessions and caches in memory. What must outlive a restart lives in a driver it links privately (`driver-auth`, 13a).
- **Private links** (`declaredLinks`, 02b §8) join the api's links; they are never relayed (§5) and not in `$links`.
- **A hook that throws:** in `onConnection` (not a `WsRefusal`) → close 1011; in `beforeRequest`/`afterRequest` → the request answers `internal-error` with a ref (13 §8); in `onPush` → the event is dropped. Each is logged.
- **Cleanup by ws-kit:** on drain and stop it drops every subscription and callback of an extension, then calls its `stop()`. An api has no reload (13 §3), so an extension has none either.
- **In config:** `extensions: Values.array(Values.plugin('ws-extension'))` — list order is the onion order. `main` checks each one's config and adds its `declaredLinks` to the api's links (02b §8). The WS API takes its list from config (§1); the Home API fixes auth and acl (18).

## 8. HTTP

One listener serves the WebSocket and a few HTTP routes. There is no REST copy of the API.

| Path | Method | |
|---|---|---|
| `/ws` | GET + upgrade | the WebSocket (§2) |
| `/` | GET | 302 to `/ui/` — WS API only |
| `/ui/*` | GET | the Inspector SPA from the `ui` package — WS API only. Hashed assets cached as immutable; `index.html` not cached |
| `/upload` | POST | §9 |
| `/health` | GET | `200 { "ok": true }`, no auth |
| an extension's routes | its own | under the path it names (13a: `/auth/*`) |

Anything else is 404.

- **Two claims on one path** — ws-kit's or another extension's — fail the api's `start`.
- **`trustedProxies`** (IPs or CIDRs): only a request from one of them has its `X-Forwarded-For`, `-Proto` and `-Host` believed. `session.upgrade.ip` is the client after them.
- **mDNS** (`mdns`, on by default): advertises `_evok._tcp` with TXT `apiId`, `v`, `path=/ws`, plus every extension's `mdnsTxt()`. An HTTP GET whose `Host` is a `.local` name gets 308 to the same path on `publicUrl` (13a §12); an upgrade is not redirected.

## 9. Uploads

Bytes larger than a message — a `.tgz` for `installPackage` (02a §2.5, 02b §12) — go over HTTP, on a ref the session asked for over WS. The `$upload` call passes the hooks like any request, so the session is authenticated; the call that uses the bytes is checked as usual.

```
→ $upload CALL { maxBytes: 4813000, sha512?: "…" }   → { ref: "u-81", exp: 1793376600 }
POST /upload   X-Evok-Upload: u-81   (raw body)      → 200 { size: 4812931, sha512: "…" }
→ main:inspectPackage { source: { tarball: { "$upload": "u-81" } } }   → report, the user confirms its integrity
→ main:installPackage { source: { tarball: { "$upload": "u-81" } } }   → the same bytes
```

- **The ref** is 128 random bits, valid 10 min, and only for the session that asked. It travels in a header, never in a URL (13a §9.1).
- **One POST per ref.** `Content-Length` is required and must not exceed `maxBytes`; a given `sha512` is checked. After a complete POST the bytes do not change.
- **Swap at relay** (§5): `{ "$upload": ref }` anywhere in a payload becomes the bytes, a `bytes` value (03a). The driver never sees HTTP. The ref can be used any number of times until it expires.
- **Where:** a temporary file in the api's runtime directory, removed when the ref expires, the session closes or the api stops.

| POST answer | When |
|---|---|
| 200 `{ size, sha512 }` | stored |
| 404 | unknown or expired ref |
| 409 | the ref already has its bytes |
| 411 / 413 | no `Content-Length` / above `maxBytes` |
| 422 | `sha512` differs; the ref is removed |

| `{ kind: 'ws', code }` | When |
|---|---|
| `upload-too-large` | `$upload` with `maxBytes` above `upload.maxBytes` |
| `upload-limit` | the session already holds `upload.maxRefs` refs |
| `upload-unknown` | `{ "$upload": ref }` not of this session, expired, or without bytes |

## 10. Config

```ts
const WsApiConfig = Values.struct({
  listen: Values.optional(Values.struct({                                    // 13 §9
    host: Values.string({ default: '0.0.0.0' }),
    port: Values.uint16({ default: 8401 }),
    tls:  Values.optional(Values.struct({ certFile: Values.string(), keyFile: Values.string() })),
  })),
  publicUrl:      Values.optional(Values.string({ label: 'Public URL', hint: 'https://byt3.t86.cz:8401' })),
  trustedProxies: Values.array(Values.string({ label: 'IP or CIDR' }), { default: [] }),
  mdns:           Values.bool({ default: true }),
  extensions:     Values.array(Values.plugin('ws-extension'), { default: [] }),   // §7
  limits: Values.optional(Values.struct({                                    // §11 — defaults there
    maxSessions, maxMessageBytes, maxSubscriptions, defaultTimeoutMs, maxTimeoutMs, highWaterBytes, stallMs,
  })),
  upload: Values.optional(Values.struct({ maxBytes: Values.uint32({ default: 50 * 2 ** 20 }), maxRefs: Values.uint8({ default: 2 }) })),
});
```

- **`publicUrl`** is the origin for the `Origin` check (§2), the session cookie, the OIDC redirect and the passkey RP ID (13a §12). Absent: `http(s)://<hostname>:<port>`.
- Bootstrap creates a WS API with `listen` and `publicUrl` (02a §6.3); the SPA derives its URL from them (02a §7).
- The Home API's config is its own (18); it reuses `listen`, `publicUrl`, `trustedProxies`, `mdns` and `limits` with its own defaults.

## 11. Keepalive and limits

- **Ping** every 30 s from ws-kit; no pong within 30 s ends the connection. A client may ping too.

| Limit | Default | Over it |
|---|---|---|
| `maxSessions` | 64 | upgrade answered 503 |
| hello | 10 s | close 4408 |
| `maxMessageBytes` | 1 MiB | close 1009 |
| `maxSubscriptions` | 10 000 per session | `ws/too-many-subscriptions` |
| `defaultTimeoutMs` / `maxTimeoutMs` | 5 000 / 600 000 | clamped |
| `highWaterBytes` | 1 MiB | events wait, coalesced (§6.3) |
| `stallMs` | 30 000 | close 4429 |

`maxMessageBytes`, `maxSubscriptions` and the timeouts are sent in the server hello (§2).

## 12. Versioning

- **The wire `v`** (§2) covers §2–§9: message shapes, api addresses, close codes. Within one `v` only additions — a new optional field, a new control `type`, a new api address. Clients ignore what they do not know.
- **An incompatible change is a new `v`.** ws-kit may speak several; a hello with one it does not speak gets `{ "type": "unsupported", "v": [1] }` and close 4426.
- **`evokNodeVersion`** is the daemon's release. It does not version the wire; 12a §4b checks a remote's against the range it supports.
- **Driver schemas are not versioned here.** They are data, read from introspection (03 §5): a new driver adds data, never wire schema, so a driver written after this api is relayed like any other (13 §6).
- The wire types are published in `client` (13 §1).

## 13. Testing

Tier 1 (basics/03), with fixture drivers from 03 §12, a fixture extension and a WS client:

- **Connection:** no hello in 10 s → 4408; wrong `v` → `unsupported`, 4426; a request before the server hello → 4400; a foreign `Origin` → 403; extensions run in list order, and a `WsRefusal` stops the next ones.
- **Relay:** `timeoutMs` clamped; `kv`, a private link and an `inClients: 'forbidden'` field → `unknown-address`; a duplicate `id` refused; call progress by the client's id.
- **Subscriptions:** two sessions on one address → one internal subscription, gone after both leave; `SUBSCRIBE` → a read without `seq`; a read older than a driver's event is dropped.
- **Loss and return:** kill the fixture → `$links` down; respawn → `$links` up and a fresh read per subscription (13 §7).
- **Backpressure:** a client that does not read gets only the newest value per address, then 4429 after `stallMs`.
- **Uploads:** a ref of another session → `upload-unknown`; a second POST → 409; a wrong `sha512` → 422; the file is gone after expiry and after the session closes.
- **Hooks:** onion order; a throwing `beforeRequest` → `internal-error` with a ref; `onPush` returning `null` drops the event.

## 14. Open

- **`client`** holding the wire types, or a separate schema package → M3.15.
- **TLS certificates** other than files — Let's Encrypt by DNS-01, and IP + self-signed by the node key (13a §12) → M3.15.
