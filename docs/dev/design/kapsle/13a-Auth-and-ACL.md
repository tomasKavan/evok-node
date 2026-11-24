# 13a — Auth and ACL

## 1. Scope

Who the caller is, how sure we are of it, and what they may do — for every api on `ws-kit` (15, 18). One driver, `driver-auth`, and two WS extensions, `auth` and `acl`.

It assumes 13 §5 (the gate, `actor`), 05a §3.1b (access marks), 12a §6 (zones) and 15 (the extension contract). Not here: an api with its own auth model keeps it — the Matter bridge's fabrics (16a), a plugin's own scheme (13 §5). The shell app's side is 13b; this file states what it must do (§7, §14).

## 2. Terms

| Term | Means |
|---|---|
| **Site** | the nodes that share one identity provider; one node with a local IdP is a site of one |
| **Node** | one kapsle; its `nodeId` is unique in the site (§3.2) |
| **IdP** | the authoritative directory: users, groups, grants, nodes, clients. A **site IdP** is external — authentik first; a **local IdP** is `driver-auth` itself |
| **Replica** | `driver-auth` on a node with a site IdP: a synced, read-only copy of the directory plus its own sessions |
| **Principal** | who a session acts for: `user:<id>`, `node:<nodeId>` (another PLC), `client:<id>` (an enrolled kiosk) |
| **Shell** | the mobile app hosting the web apps (13b); holds the site's IdP session and the phone's keys |
| **Session** | a node's own login of one principal on that node; never valid on another node |

## 3. Components

```
            site IdP (authentik) ── users, groups, grants, nodes, clients, PIN hashes
               ▲ OIDC login          ▲ sync (poll 5 min, webhook = hint)
  shell ───────┘                     │
    │ node tokens, proofs            │
    ▼                                │
  node ── ws-kit api (WS API, Home API)
            ext auth  ── /auth/* HTTP routes, hello, sessions ──┐ private link (15)
            ext acl   ── per-request check, filtering ──────────┤
                                                                ▼
                                                           driver-auth ── directory copy, sessions,
                                                                          keys, PIN hashes, node key
```

### 3.1. `driver-auth`

- **One driver, two directory sources** (`mode`): `local` — it is the IdP, edited in the Inspector; `site` — a replica of the site IdP.
- **Storage:** its own SQLite file, mode 0600 — it owns its data (01 §7); not the KV driver.
- **Reached by the extensions over their private link** (15). An api that lists `auth` in `drivers:` relays only what is not marked `inClients: 'forbidden'` (05a §3.1b) — the management below.

```ts
// @kapsle/driver-auth — kinds auth.*; `inClients: 'forbidden'` = never relayed to clients (05a §3.1b)
const AuthDriver = device('auth.Driver', {
  // the extensions' own — inClients: 'forbidden'
  openSession:  method('mutates', Session, OpenArgs, { access: { inClients: 'forbidden' } }),     // §7
  refresh:      method('mutates', Session, RefreshArgs, { access: { inClients: 'forbidden' } }),
  check:        method('none', SessionState, Values.struct({ sid: Values.string() }), { access: { inClients: 'forbidden' } }),
  challenge:    method('mutates', Challenge, ChallengeArgs, { access: { inClients: 'forbidden' } }),   // §8.2
  verifyProof:  method('mutates', ProofResult, ProofArgs, { access: { inClients: 'forbidden' } }),
  grantsOf:     method('none', GrantList, Values.struct({ principal: Values.string() }), { access: { inClients: 'forbidden' } }),
  changes:      reading(DirectoryRev, { subscribe: true, access: { inClients: 'forbidden' } }),   // grants, sessions, disabled flags
  // management — relayed by the WS API to the Inspector
  directory:    reading(DirectoryView, { subscribe: true, access: { read: 'administer' } }),   // users, groups, nodes, clients
  issues:       reading(IssueList, { subscribe: true, access: { read: 'administer' } }),       // §4.3
  sync:         reading(SyncState, { subscribe: true, access: { read: 'administer' } }),       // last run, IdP reachable
  sessions:     reading(SessionList, { subscribe: true, access: { read: 'administer' } }),
  revoke:       method('mutates', Values.void, Values.struct({ sid: Values.string() }), { access: { call: 'administer' } }),
  disable:      method('mutates', Values.void, Values.struct({ principal: Values.string(), disabled: Values.bool() }), { access: { call: 'administer' } }),
  enrolClient:  method('mutates', Enrolment, ClientArgs, { access: { call: 'administer' } }),   // §10
  pairPeer:     method('mutates', Values.void, PeerArgs, { access: { call: 'administer' } }),   // §11, local mode only
  setPin:       method('mutates', Values.void, PinArgs, { access: { call: 'administer' } }),    // local mode only
  syncNow:      method('mutates', Values.void, undefined, { access: { call: 'administer' } }),
});
```

In `site` mode, `setPin` and `pairPeer` answer `domain-error` `site-managed`: the site IdP is the only source (§4).

### 3.2. Config

```ts
const AuthConfig = Values.struct({
  nodeId: Values.string({ pattern: '^[a-z0-9-]{1,32}$', label: 'Node id' }),      // unique in the site
  mode:   Values.string({ enumValues: ['local', 'site'], default: 'local' }),
  site:   Values.optional(Values.struct({                                          // mode 'site'
    issuer:   Values.string({ format: 'url', label: 'IdP issuer' }),               // OIDC discovery
    clientId: Values.string({ default: 'kapsle' }),                                  // the site's one kapsle app
    apiToken: Values.string({ sensitive: true }),                                  // the node's service account, for sync (02a §4)
    syncS:    Values.uint32({ unit: 's', default: 300 }),
  })),
  file:   Values.string({ default: '/var/lib/kapsle/auth.sqlite' }),
});
```

### 3.3. The extensions

| Extension | Hooks (15) | Does |
|---|---|---|
| `auth` | `onConnection`, `httpRoutes`, `onClose` | the hello and in-band renewal (§9.1); `/auth/*` on the api's own listener, so cookie, `Origin` and the OIDC redirect share `publicUrl` (§12); leaves `session.state.auth` = principal, grants, level, sid |
| `acl` | `beforeRequest`, `afterIntrospect`, `onPush` | the check (§5.3) and proof (§8.2); fills `actor` (13 §5) |

The Home API fixes both (18); the WS API lists them in config (15). Both take `{ idp: <driver-auth id> }` and declare it as a private link.

## 4. Directory

### 4.1. Principals and roles

| Principal | In a site IdP | In a local IdP |
|---|---|---|
| `user:<id>` | a user | a user record in `driver-auth` |
| `node:<nodeId>` | a service account, attribute `kapsle.nodeKey`, optionally `kapsle.delegate: true` (§11.4) | a peer record, made by `pairPeer` |
| `client:<id>` | a service account, attribute `kapsle.clientKeys` (§10) | a client record, made by `enrolClient` |

- **A role is a group** with a grants attribute; a principal holds the roles of its groups and their parents. RBAC only — no rule on device values.
- **Fixed roles**, no parameters: one per flat (`tenant:flat3`); what roles share goes to a parent (`resident`).
- **Inheritance is the replica's:** it walks group parents itself, never relying on the IdP's attribute merge.
- **A guest** is a user with a PIN and narrow grants, disabled after the visit.

```jsonc
// group "resident"
{ "kapsle": { "v": 1, "grants": [{ "privilege": "operate", "scope": "zone:common" }] } }
// group "tenant:flat3", parent "resident"
{ "kapsle": { "v": 1, "grants": [{ "privilege": "manage", "scope": "zone:flat3" }] } }
// group "peer:garden" ∋ node:garden
{ "kapsle": { "v": 1, "grants": [{ "privilege": "operate", "scope": "device:house/ONB:2.unipi.ro.04" }] } }
```

### 4.2. PINs

- **A PIN identifies its user** — no name is typed. 6 digits or more, set by an admin, unique in the site (the admin's to keep so, for now — §16).
- **Site IdP:** two user attributes. `kapsle.pin` — the clear PIN, readable only by 2N Access Commander's LDAP account, which drives the 2N directory (12e). `kapsle.pinHash` — Argon2id, written by an IdP expression policy when the PIN is set; the only form any node syncs.
- **Local IdP:** `setPin` stores the hash only.

### 4.3. Sync and checks

- **Poll is the truth:** every `syncS`, at start and when the IdP comes back, with the node's `apiToken`. A webhook from the IdP only triggers a poll. Synced: users (id, name, active), groups, membership, parents, `evok.*` attributes. Never passwords; `kapsle.pin` is not readable by the node's account.
- **A sync never fails as a whole.** Each grant is checked:

| Check | On failure |
|---|---|
| shape — `privilege` one of the four, `scope` matching its kind's pattern (03a) | that grant is skipped; an issue |
| unknown `v` | the group's attribute is skipped; an issue |
| `node:` or `device:` naming another node | normal — it does not apply here |
| `device:` naming this node with an address it does not have | applied (it may appear later); a warning |
| `zone:` with an id no room here uses | applied; an info |

  Issues are `Issue[]` (03a) on `issues`, shown in the Inspector.
- **A node-local "disabled" flag** (`disable`) wins over sync at once, until an admin clears it. A principal inactive at the IdP loses its sessions at the next sync.

## 5. Authorization

### 5.1. Privileges and marks

`view < operate < manage < administer`. What each operation needs is the type's access mark, or its default (05a §3.1b); 13a never redefines a mark. The WS API and the Home API use the marks as written, for every client (13 §5).

### 5.2. Scopes

```ts
interface Grant { readonly privilege: Privilege; readonly scope: Scope }
type Scope = 'site' | `node:${NodeId}` | `zone:${ZoneId}` | `device:${NodeId}/${Address}`
```

| Scope | Covers, on a node |
|---|---|
| `site` | everything |
| `node:<id>` | everything, on the node with that id |
| `zone:<id>` | home devices in rooms of that zone or of a zone below it (12a §6) |
| `device:<node>/<address>` | that one address, on that node |

- **Grants only add up.** On an address the highest privilege wins; there is no deny. A boundary is drawn in the hierarchy (12a §6), an exception is a `device:` grant.
- **Management is per home driver.** A grant reaching `<home>:manage` manages that whole driver (12a §5). A flat gets its own manager by having its own home driver — one per PLC, one per top zone in practice — and the others import its devices (12a §4b).

### 5.3. The check

The `acl` extension sees exactly what the api's clients see, and decides only on that. It keeps one copy of each relayed home driver's `manage.listHierarchy`, refreshed on its `manage.hierarchyRev` (12a §6); a session keeps only its grants (§9.1).

```ts
privilege(session, address) = max(g.privilege for g in session.grants if covers(g.scope, address))
// zone: tail → group → room → zone → parent → … contains the grant's zone
allowed = privilege(session, address) >= markOrDefault(element)        // 05a §3.1b
       && (!element.access?.proof || proof(session, call) ok)          // §8.2
```

| Hook | Checks |
|---|---|
| `beforeRequest` | every GET, SET, SUBSCRIBE, CALL; refused ⇒ `{ kind: 'auth', code: 'forbidden' }` (a refusal, 15 §3), the driver never sees it. Api addresses (`$links`, `$upload` — 15 §4) need only an open session |
| `afterIntrospect` | drops devices below `view`, and fields below their `read` |
| `onPush` | drops values and introspection changes for what the session may no longer see |

- **Grants change** (`driver-auth`'s `changes`): the session's grants are replaced; subscriptions now below `view` end.
- **On loss:** of `driver-auth` — sessions keep their grants, new connections are refused; of a home driver — its last hierarchy copy stays, and a session opened before the first copy arrives resolves no `zone:`.

## 6. Sessions and tokens

### 6.1. Node access token

Short, node-signed, a session id inside; validity is decided by the session table, so a revoke acts at once.

```jsonc
{ "typ": "at+jwt", "alg": "EdDSA", "kid": "house-1" }
{ "iss": "kapsle:house", "aud": "kapsle:house", "sub": "user:u-42", "sid": "s-91c",
  "iat": 1793376000, "exp": 1793376600, "acr": "l1", "auth_time": 1793370000 }
```

No grants inside — they come from the directory (§4). Signed with the node key (§11.1); `jose` (§13).

### 6.2. Lifetimes

| Secret | Where | Lives |
|---|---|---|
| node access token | shell memory, the hello, renewed in-band | 10 min |
| node session — refresh token (shell, DPoP-bound to K) or cookie (browser: HttpOnly, Secure, SameSite=Strict) | client; the node keeps a hash | 30 d idle, 30 d absolute |
| one-time local session (§7.4) | the same | single connection, ≤ 12 h, no refresh |
| IdP refresh token | shell only | the IdP's (authentik: 30 d, rotated on use) |
| ID token bound to K | shell → node, once | minutes |
| K, B private keys | phone hardware | per install; B until biometry changes |
| K, B public keys | each node where they were registered | until removed |
| PIN hash | IdP attribute, synced; or `driver-auth` | until changed |
| node key | node, sensitive (06 §5a) | per install; rotation §11.3 |
| sync `apiToken` | node config, sensitive (02a §4) | set by the admin |

- **Refresh tokens** are opaque, rotated on every use; reusing an old one revokes the session (RFC 9700).
- **Revocation:** `revoke`, the "disabled" flag, or the IdP (next sync). Open connections of the session close at once (§9.1).

## 7. Logins

### 7.1. Shell, site IdP

```
shell → IdP       : login in the system browser, PKCE S256, scope bound_key, DPoP key K
IdP   → shell     : ID token { sub, cnf: K }, IdP refresh token
shell → node      : POST /auth/site { idToken } + DPoP proof (K, htu = this node)
node              : signature against its copy of the IdP's keys, `aud` = clientId, K's proof, user active
                  → openSession → { access, refresh }
shell → node      : POST /auth/keys { K, B }          // first login on this node (§7.5)
```

The site has **one** kapsle app in the IdP. A node never calls the IdP to log a user in; the shell holds the IdP session and fetches a fresh bound ID token for each node it opens.

### 7.2. Browser — the node as backend for frontend

```
browser → node : GET /auth/login                 → 302 to the IdP (PKCE, state)
browser → IdP  : login
browser → node : GET /auth/callback?code         → node redeems the code (PKCE verifier) for an ID token,
                                                    uses it once, keeps nothing from the IdP
node → browser : Set-Cookie (§6.2), 302 to the SPA
browser → node : WS upgrade with the cookie; `Origin` must be `publicUrl`
```

Each node's `/auth/callback` is in the kapsle app's redirect list. Proof in a browser is a passkey registered on this node, or the PIN (§8).

### 7.3. Local IdP

The node's own login page (`/auth/login`): password or a passkey; the shell logs in with the same `POST /auth/site` replaced by `POST /auth/password`. Everything after the login is §6.

### 7.4. One-time local session

When the IdP cannot be reached for a new session: `POST /auth/local` with the device key and biometry (`l2`; keys registered here before) or the PIN (`l1`; hashes are synced, so any node). Single connection, ≤ 12 h, no refresh, logged.

| IdP down | Shell | Browser |
|---|---|---|
| a session on this node | works, refreshed by the node | works |
| a proof | B, or the PIN | a passkey, or the PIN |
| a new session where keys were registered | §7.4 with K + B (`l2`) or the PIN (`l1`) | passkey (`l2`) or the PIN (`l1`) |
| a new session on a node never used | §7.4 by PIN only | the same |

### 7.5. Phone keys

Two keys per install and site, both in hardware: **K** — the session key, no user prompt, DPoP; **B** — the step-up key, biometry only (`biometryCurrentSet` / `AUTH_BIOMETRIC_STRONG`). Registered **per node**, at the first online login there, never published through the IdP. When B becomes invalid (a new finger), the PIN is the fallback until the shell registers a new B while online.

## 8. Levels and proof

### 8.1. Levels

| Level | Reached by |
|---|---|
| `l1` | a password, a site login with `amr` `pwd`, a refreshed session, the PIN |
| `l2` | the device key with biometry, a passkey with user verification, a site login with MFA |

Freshness is kept apart, as the time of each factor (`auth_time`), not as more levels. The level goes into `actor.level` (13 §5).

### 8.2. Proof

`access.proof` is binding: an api that cannot get a proof refuses the call (13 §5). A proof is for **one call**:

```jsonc
→ { "id": 7, "call": "home:device.local.12.unlock" }
← { "re": 7, "ok": false, "error": { "kind": "auth", "code": "proofNeeded", "kinds": ["uv", "pin"], "nonce": "n-3f…", "exp": 1793376060 } }
→ { "id": 8, "call": "home:device.local.12.unlock", "proof": { "nonce": "n-3f…", "kind": "uv", "keyId": "k-iphone-b", "sig": "…" } }
← { "re": 8, "ok": true }
```

| Kind | How | Allowed |
|---|---|---|
| `uv` | B signs `{ nonce, exp, node, sid, address, method, argsHash }` after biometry; a passkey assertion over the same in a browser | always |
| `pin` | the PIN, over the session's TLS; checked against the synced hashes | always |
| `ack` | a confirmation only | when the session proved `uv` within the last 5 minutes |

- **The nonce** is single use, ~60 s, bound to the call's address, method and arguments; a proof never serves another call.
- **The PIN identifies the user** and makes that one call run as them: their grants are checked, `actor` is them at `l1`; the session itself does not change. That is how a kiosk (§10) and a guest open a door.
- **PIN failures** are counted per source and across the site, with growing delays; the count is written before each check.

### 8.3. Rules

A rule runs inside the home driver, never through an api. A rule whose actions may call a method marked `proof` needs its author's consent when it is created or changed: the api fills `by` with the caller, `level` included, and the home driver accepts only `level: 'l2'`, recording who and when (12b §6a).

## 9. The WS extensions

### 9.1. `auth`

Message framing is 15's; the content below is binding.

```jsonc
← { "type": "auth_required", "node": "house", "nonce": "n1", "time": 1793376000 }   // first, after the upgrade
→ { "type": "auth", "token": "<node access token>" }                                // a user from the shell
→ { "type": "auth", "principal": "node:garden", "nonce": "n2", "sig": "…" }          // a key principal (§10, §11.2)
← { "type": "auth_ok", "principal": "user:u-42", "level": "l1", "exp": 1793376600 } // + "sig" for a key principal
← { "type": "auth_invalid", "code": "expired" }                                      // then close
```

- **Nothing before `auth_ok`.** 10 s to authenticate; the `Origin` allowlist (`publicUrl`) is checked at the upgrade; no token ever in a URL.
- **A browser** with a valid cookie gets `auth_ok` at once, without `auth_required`.
- **Renewal in-band:** another `auth` with a fresh token on the open socket — a control message the extension owns (15 §7). Without one, the api closes at `exp` + 30 s.

| Close | When |
|---|---|
| 4401 | not authenticated, invalid token or signature |
| 4403 | session revoked, principal disabled |
| 4408 | no `auth` within 10 s |
| 4410 | token expired, not renewed |

- On `auth_ok` it calls `grantsOf` and keeps the grants, the level and `sid` in `session.state.auth` for `acl`; `changes` keeps them current.

### 9.2. `acl`

§5.3 and §8.2. It also fills every `actor` member (13 §5) from `session.state.auth`, or from the PIN's user for that call, or — from a delegating peer — keeps the one it was sent (§11.4).

## 10. Enrolled clients

A kiosk-like device — a wall panel, a kitchen tablet — is a principal of its own, `client:<id>`, never an anonymous session.

```
admin (Inspector) → enrolClient { id: 'kitchen-tablet' } → QR: publicUrl + node key fingerprint + one-time code (10 min)
tablet            → POST /auth/enrol { code, key: <its public key> }   // TLS pinned to the fingerprint
node              : the key is the client's; from now on the hello with the key (§9.1)
```

- Its grants come from its groups like anyone's (`panel:flat3`). Its name is in the log.
- **Proof on it is the PIN** of the person at it (§8.2).
- **Where the record lives** follows §4.1: with a site IdP, the admin creates the service account and the enrolment writes nothing to the IdP — the node shows the key to paste into `kapsle.clientKeys`, and the client works once the replica syncs it; with a local IdP, `enrolClient` stores it at once.

## 11. PLC to PLC

### 11.1. Node key

An Ed25519 key pair, made by `driver-auth` at install. The private key never leaves the node (06 §5a); the public key is shown in the Inspector as text and QR. It signs the node's access tokens (§6.1), its TLS certificate when it has no public one (§12), and its hello as a peer.

### 11.2. Connecting

Both sides prove themselves; no clock is needed between them:

```
garden ──WS──► house
house  → auth_required { node: 'house', nonce: n1 }
garden → auth          { principal: 'node:garden', nonce: n2, sig: sign(garden.key, n1 ‖ 'house' ‖ n2) }
house  : verify with garden's key from the directory → node:garden → its grants
house  → auth_ok       { principal: 'node:garden', sig: sign(house.key, n2 ‖ 'garden') }
```

`RemoteLink` (05a §3.8b) and 12a §4b's peer link do this from the calling side. After `auth_ok` the peer is a session like any user's.

| Mode | The peer |
|---|---|
| site IdP | a service account `node:<id>` with `kapsle.nodeKey`; **only from the IdP** — `pairPeer` refused |
| local IdP | `pairPeer`: the peer's QR or code, approved in the Inspector |

### 11.3. Rotation and revocation

A new key is published beside the old one; both are accepted until the old one is removed. Revocation: the account disabled at the IdP (next sync), or `disable` on this node (at once).

### 11.4. Delegation

A call relayed for a user — Petr unlocks a `DoorLock` imported from `garden`: `house`'s api checks Petr and his proof, `house`'s home driver forwards the call over its peer link, and `garden` sees `node:house`.

- **A peer with `kapsle.delegate: true`** may pass a user on. `garden` keeps the `actor` members it was sent, sets `via: 'node:house'` (13 §5), and treats `access.proof` as met: the calling node's copy of the device has the same type, so its own gate asked for the proof.
- Its own grants are still checked: `node:house` needs `operate` on the lock at `garden`.
- A peer without the flag gets `actor` overwritten with itself, and a `proof` call is refused.

## 12. Names and TLS

- **One canonical name per node** (`byt3.t86.cz`), its `publicUrl` (15) — one origin, so one cookie, one passkey, one redirect URI. At home, split-horizon DNS points it to the LAN address; hairpin NAT is the fallback.
- **The node holds its own certificate** for that name — Let's Encrypt via DNS-01, no open port — so the LAN never depends on a reverse proxy. A reverse proxy for the public side is optional; `X-Forwarded-*` is believed only from `trustedProxies` (15).
- **`.local`** (mDNS) only for discovery and a redirect to `publicUrl` — never a second login origin.
- **The shell** finds a node on the LAN by mDNS (`_evok._tcp`, with `nodeId` and the key fingerprint), connects to its LAN address and checks it as the canonical name (SNI) or by the pinned node key; elsewhere it uses `publicUrl`. It offers advertised nodes to add, confirmed by the fingerprint.
- **IP + self-signed** (signed by the node key) stays possible: secure in the shell by pinning; a plain browser gets a warning and no passkeys.
- **Passkey RP ID** is the node's host, or the site's parent domain (`t86.cz`) when all nodes share it.

## 13. Storage and secrets

| What | Where |
|---|---|
| directory copy, sessions (hashed refresh tokens), registered keys, PIN hashes, failure counters, issues | `driver-auth`'s SQLite file, 0600 |
| node key, `apiToken` | secrets (02a §4, 06 §5a) |
| tokens | `jose` (EdDSA JWT); the IdP side with `openid-client` (OIDC discovery, code flow, JWKS); `oidc-provider` only if third-party OIDC clients ever come |
| PIN hashes on a local IdP | Argon2id (`crypto.argon2`; scrypt where missing) |

**Clock:** after a power cut with no NTP and no IdP, the saved time is used — behind, never ahead — and new offline sessions are logged. `auth_ok` carries the node's time.

## 14. Example flows

| Flow | Steps |
|---|---|
| Petr opens the Home UI on his phone at home | mDNS finds `house` → §7.1 if no session (else refresh) → hello (§9.1) → `acl` filters introspection to flat 3 and common |
| Petr unlocks the front door | §8.2 `proofNeeded` → Face ID signs with B → `unlock` runs with `actor` Petr, `l2` |
| An admin in a browser | §7.2 → Inspector over the WS API with `administer @ node:house` |
| A guest at the kitchen tablet | the tablet's own session (§10) shows the lights; the door asks for a PIN → the guest's PIN → the call runs as the guest |
| The NAS with authentik is off | open sessions go on; a new phone session by PIN (§7.4); sync waits; `sync` shows the IdP unreachable |
| `garden` imports `house`'s devices | §11.2 hello with node keys → `node:garden` gets `view` on what it imports (12a §4b) |

## 15. Testing

Tier 1 (basics/03), against a fixture IdP (OIDC discovery, JWKS, token endpoint, the directory REST API), a fixture home driver and `ws-kit`:

- **Hello:** nothing before `auth_ok`; 4408 after 10 s; a wrong `Origin` is refused at the upgrade; renewal keeps the socket; 4410 at `exp` + 30 s; revoke closes with 4403 at once.
- **Site login:** a bound ID token without K's DPoP proof, with another node's `htu`, or for an inactive user is refused; with it, a session opens without any call to the fixture IdP.
- **Browser:** the callback sets the cookie with HttpOnly, Secure, SameSite=Strict; the node keeps no IdP token.
- **Check:** a tenant of flat 3 lists only flat 3 and common devices; SET on another flat is `forbidden`; moving a device out of the zone (`hierarchyRev`) ends its subscription; `device:` and `node:` grants for another node grant nothing here.
- **Sync:** a malformed grant is skipped with an issue and the group's other grants apply; an unknown `v` skips the attribute; the disabled flag wins over a sync.
- **Proof:** a nonce used twice, for another address or other arguments, or after `exp` is refused; `ack` passes only within 5 min of `uv`; a PIN call runs as the PIN's user with their grants; failures add delay.
- **Offline:** with the fixture IdP stopped, sessions refresh; §7.4 by PIN works on a fresh node; by K + B only where registered.
- **Peers:** the hello fails with a wrong key or a replayed nonce; a peer without `delegate` gets `actor` overwritten and `proof` refused; with it, `via` is set.
- **In clients:** `inClients: 'forbidden'` fields of `driver-auth` never appear in a client's introspection and answer `forbidden`, even with `auth` in `drivers:`.
- **Enrolment:** a code works once and for 10 min; a client's key from another node is refused.

## 16. Open

- **PIN uniqueness** is the admin's for now; generated PINs and a check that does not leak other users' PINs → M5.1, with the IdP's PIN flow for the 2N.
- **Hardware and IdP facts**, settled on hardware or by test (M3.15): the Patron's RTC and TPM; `crypto.argon2` in the Node build on Unipi; the §5.3 check on a Cortex-A53; authentik's `amr` after an in-flow step-up and its group API for incremental sync; the PIN format Access Commander reads over LDAP (M5.1); Chrome's Local Network Access for WebSockets.
