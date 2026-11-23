# 15 — Nextgen API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** our own WS and HTTP surface — designed rather than inherited.

**Covers**

- **One model, two transports.** WS and HTTP, and which is authoritative for what. Not two APIs.
- **Subscriptions and diffs:** what a client subscribes to, what a diff contains, ordering guarantees,
  resync after a gap, and backpressure. The mechanism is decided in 03; **its surface is decided
  here**, and the two must not drift.
- **Consumes every driver,** including ones written after this API. The introspection-driven schema,
  and what "stable" can mean for a schema that is derived rather than declared.
- **Public schema ownership and versioning,** and the `client` package's relationship to it.
- **ACL:** subjects, resources, actions, and where enforcement sits. The authentication *mechanism* is
  **deliberately deferred** (G-2 defers ports, paths and authentication; the deferral is tracked in
  [`STATUS.md`](../../plan/STATUS.md)) — so state what ACL assumes of it and nothing more.
- **Serving the inspector UI** at the root.
- **Its own config:** `listen` (with `tls`, 13 §9) and `publicUrl`, plus `trustedProxies` (whose `X-Forwarded-*` it believes) and `mdns` (advertise `_evok._tcp` with `nodeId`, redirect `.local` to `publicUrl`). `publicUrl` is the origin for the session cookie, the `Origin` check, the OIDC redirect and the passkey RP ID (13a). Bootstrap creates a ws api with them (02a §6.3); the SPA derives its URL from them (02a §7).
- **The hello carries `apiId`**, so the SPA knows which api it is connected to and warns before a change reloads it (02a §7).
- **evok-node as a client of evok-node.** A home driver imports another PLC's devices over
  this api (12a §4b). Its authentication — PLC to PLC, no human in the loop — is part of this api's
  auth design (M3.6). The connection's hello advertises `evokNodeVersion`: 12a §4b checks a remote's
  against the range it supports.
- **Session language.** `hello.lang`, else the request's `Accept-Language`, else `en`. `setLang` changes
  it mid-session; the client refetches what it shows.
- **Localization at the edge.** A WS extension (13 §2) resolves `LocalizedText` (04 §7) to the session's
  language in everything it sends: schema annotations (`label`, `hint`, `helpMd`, `enumLabels` — 03a §4),
  values of format `text`, and the schemas inside values of format `schema`. Drivers always answer every
  language, so introspection stays one shared payload.
- **Refs.** `$refs` (03 §3, 05a §3.10) is relayed like any other address.
- **WS extensions** (13 §2) — the contract `ws-kit` gives every api built on it:

```ts
interface WsExtensionDescriptor<Config> {      // manifest kind `ws-extension`
  readonly meta: ModuleMeta;                   // 02 §4
  readonly config: ValueType<Config>;          // 03a
  rules?(config: Config): readonly Issue[];
  declaredLinks?(config: Config): { readonly drivers: readonly DriverId[] };   // its private drivers (03 §8)
  create(ctx: ExtensionContext, config: Config): WsExtension;                  // once, at the api's configure
}

interface WsExtension {
  onConnection?(session: Session, hello: Hello): Promise<void>;   // may reject
  onClose?(session: Session): void;
  beforeRequest?(ctx: RequestCtx): void | Promise<void>;          // may change ctx.msg, or ctx.refuse(error)
  afterRequest?(ctx: ResponseCtx): void;                          // may change ctx.res
  beforeIntrospect?(ctx: IntrospectCtx): void;
  afterIntrospect?(ctx: IntrospectCtx): void;                     // filter or annotate the payload
  onPush?(session: Session, push: Push): Push | null;             // values and introspection changes going out
  stop?(): Promise<void>;
}

interface ExtensionContext {
  // the api's view — what its clients see
  introspection(): Introspection;  onIntrospection(cb): void;  onLink(cb): void;
  get(address); set(address, value); call(address, args); subscribe(address, cb): Subscription; unsubscribe(sub);
  // its own declaredLinks only
  private(driverId: DriverId): { get; set; call; subscribe; unsubscribe; onLink };
  readonly log: Logger;                        // 04
}
```

  - **Stacked, onion order:** `onConnection` and `before*` run in list order, `after*` and `onPush` in reverse. `session.state` is where one extension leaves typed data for the next (auth → ACL).
  - **The api stays agnostic.** Users, zones, languages are the extensions'; the api only offers these services.
  - **An extension sees only what the api's clients see**, plus its private drivers. Its own calls carry the api's `Origin` and skip the hooks (13 §5).
  - **Cleanup by `ws-kit`:** on drain and stop it drops every subscription and callback of an extension, then calls its `stop()`. An api has no reload (13 §3), so an extension has none either.
  - **The api's descriptor combines its extensions'** — config, rules, links. Links are `drivers:` plus every extension's `declaredLinks`; only `drivers:` is relayed to clients. How `validate` and the forms see an extension's config inside the api's is M3.7b's (02b).
  - **This api lists its extensions in config**, e.g. `extensions: { auth: { idp: auth }, acl: { idp: auth } }`. The Home API fixes its own (18).
- **Access marks** (05a §3.1b) are used as the types wrote them, as on the Home API — no override and no per-client profile (13 §5).

**Inputs:** research/01 (as contrast) · research/08 · to_revision/0003 ·
[`STATUS.md`](../../plan/STATUS.md), the undeclared-workspace-edges open question

**Open:** `client → api-nextgen` versus a separate `schema-nextgen` package, and the deferred auth
mechanism.
