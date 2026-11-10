# 07 — Way forward

**Research, not design.** Notes 01–06 read against Tomas's input (README §1) and today's design (README §3): a proposed shape, how it fits the design, what Tomas must decide, and what comes next. **Everything here is a proposal — not binding.** Feeds 13a (M3.6).

Design documents are written `design 06 §5a`; bare numbers (`02 §4`, `05 P3`) are the notes in this folder.

## 1. What the research changes

| Finding | Consequence | From |
|---|---|---|
| authentik needs ≥ 2 CPU and 2 GB RAM | it lives on a NAS or server, never on a PLC; "IdP down" then includes every NAS outage [I] | 01 §1.2 |
| authentik is good at users, groups, attributes, OIDC login | use it as the **authority** for who exists and their roles | 01 §2, §3, §11 |
| authentik has no PIN, one fixed `acr`, coarse `amr`, ignores `acr_values` | levels and proofs are evok-node's job | 01 §4, 03 §2.5 |
| authentik passkeys are bound to its host; its API gives no public keys and no hashes | a replica cannot verify authentik credentials; a password only if it passes through the replica (LDAP bind), which OIDC login avoids | 01 §6, 05 §3.1 |
| authentik rotates refresh tokens; a reused one fails | two nodes must not refresh the same authentik session, unless `refresh_token_threshold` is set | 01 §5, §11 |
| the offline precedents checked create the offline credential after an online login on that machine [I] | offline login = credentials enrolled earlier on this node | 05 §2 |
| a token the node signs for itself (`iss` = `aud` = node) is node-only by construction [I] | "valid on this node only" needs no extra mechanism | 02 §4 |
| the server sees only that a device key signed after local UV — biometry or device passcode, it cannot tell; a browser at an IP address gets no WebAuthn | the strongest proof a node can get is a hardware key in the shell app, or a passkey on a node with a DNS name and a trusted certificate | 03 §3, §7, 06 §2, §4 |
| a PIN either **identifies** a person or **confirms** a known one; the rules differ | decide which one evok-node checks | 03 §6 |
| a per-session table answers in ~0.2 µs (x86, measured); engines are slower | no policy engine on the hot path | 04 §2.2, §3 |
| client credentials and `private_key_jwt` need the IdP online; pinned keys and mTLS do not [I] | PLC-to-PLC trust must not run through the IdP | 02 §6 |
| a PLC without RTC restarts with the last saved time — behind, never ahead | offline expiry checks are lenient by the outage length | 02 §7 |

## 2. Proposed shape

**One component, two directory sources.** The replica and the local IdP are the same driver; only where users and roles come from differs. Because a site IdP is never an evok-node, a node with a local IdP is a one-node site.

```
                 site IdP (authentik, NAS) ── users, groups, role attributes
                    ▲ OIDC login        ▲ poll (+ SCIM push)
  shell app ────────┘                   │
     │ node tokens, proofs              │
     ▼                                  │
  node ─ api-auth (HTTP) ──────► driver-auth ◄──┘   sessions, node key, directory copy,
       ─ WS API / Home API                ▲          PIN verifiers, device keys, audit
           ext auth  (onConnection) ──────┤
           ext acl   (onRequest)  ── compiled table, in memory
```

| | Local IdP | Site IdP + replica |
|---|---|---|
| Directory | own, edited in the Inspector | synced copy, read-only, plus a node-local "disabled" flag |
| Online login | node's own login (password, passkey) | OIDC at authentik → the node turns the authentik token into a node session (D2) |
| Tokens | node-signed | node-signed — the same code |
| PIN, device keys | own | own, enrolled on the node while online (D6, D13) |
| IdP unreachable | — | node sessions keep working and refresh; new sessions only by one-time local login |

### 2.1. Sessions and tokens

- `driver-auth` keeps a **session table**. An access token is a short JWT the node signs: identity, session, level — **no roles** (roles come from the directory copy, 04 §4).
- A refresh token is opaque, rotated with reuse detection; DPoP-bound when the client has a key store (02 §2.2, §2.3).
- **Site login at a node (D2):** the shell presents an authentik ID token issued to the site's one evok client and key-bound to the shell's session key (authentik `bound_key`, 01 §5, 06 §2.5), with a DPoP proof for this node. The node checks it with the cached JWKS and opens its own session. A captured token is useless without the key; no per-node provider is needed.
- **The authentik session** is held and refreshed by the shell app (D3). Nodes keep no authentik refresh tokens; a node acting as BFF for a plain browser uses the ID token at login and keeps nothing else.
- So **node-limited is the normal shape**. Lost while authentik is down: sessions on nodes not visited yet, and directory freshness.

```json
{ "typ": "at+jwt", "alg": "EdDSA", "kid": "basement-1" }
{ "iss": "evok:site-a:basement", "aud": "evok:site-a:basement", "sub": "u-42", "client_id": "shell",
  "jti": "a7c…", "sid": "s-91c", "iat": 1793376000, "exp": 1793376600, "acr": "l1", "auth_time": 1793370000 }
```

### 2.2. In the WS api

- **Binding is opt-in.** An api on `ws-kit` lists the auth and ACL extensions (manifest kind `ws-extension`, design 13 §2). An api with its own auth (Matter, an MQTT plugin) does not, and fills `actor` with its own realm (design 13 §5). Whatever an api decides, the driver trusts it — the gate is the api's responsibility.
- **`onConnection`:** first-message auth in the hello (`auth: { token }`), nothing accepted before it, 10 s timeout, `Origin` allowlist at upgrade (02 §5, P3). Verifies the JWT locally, subscribes to the session's status at `driver-auth`, fetches the user's assignments, compiles the table (§2.4).
- **In-band `auth`** renews the token on an open connection; the api closes at `exp` + grace without one, and at once on revoke (02 P4; Home Assistant closes on revoke, 02 §5.1). The WS access token stays bearer; it is short and useless once its session is revoked.
- **`onRequest`:** one table lookup. A `proof` method gets a challenge; the client repeats the call with the proof; the api asks `driver-auth` to verify, then relays with `actor` filled (design 13 §5).

```jsonc
→ { "id": 7, "call": "home:device.local.12.unlock" }
← { "re": 7, "ok": false, "error": { "kind": "auth", "code": "proofNeeded", "kinds": ["uv", "pin"], "nonce": "n-3f…", "exp": 1793376060 } }
→ { "id": 8, "call": "home:device.local.12.unlock", "proof": { "nonce": "n-3f…", "kind": "uv", "keyId": "k-iphone", "sig": "…" } }
← { "re": 8, "ok": true }
```

The proof signs `{ nonce, exp, node, sid, address, method, argsHash }` — bound to this one call, usable once, checkable offline (03 P3, 06 §2.5).

### 2.3. Levels and proof

| Level | Reached by |
|---|---|
| `l1` | any login: password, site token with `amr` `pwd`, a refreshed session |
| `l2` | device key with UV, passkey with UV, authentik login with `amr` `mfa` — or `user` when authentik's WebAuthn stage requires UV (01 §4) |

- Freshness is kept apart from the level (`auth_time` per factor), not as more levels (03 P1).
- **`proof` methods ask for a per-operation proof** of kind `uv` or `pin`; whether `ack` (confirm only) is enough is D5.
- Optional **session minimum** for whole areas: e.g. `administer` needs `l2` within 15 min — the NIST AAL3 inactivity limit (03 §1.1); GitHub's sudo window is 2 h (03 §4.1).

### 2.4. Roles and ACL

```ts
type Privilege = 'view' | 'operate' | 'manage' | 'administer'             // each includes the ones before
interface Role       { readonly id: string; readonly privilege: Privilege }  // tenant → operate, admin → administer
interface Assignment { readonly subject: Subject; readonly role: string; readonly scope: Scope }
type Subject = `user:${string}` | `group:${string}` | `node:${string}` | `client:${string}`  // client = a wall panel
type Scope   = 'site' | `node:${string}` | `zone:${string}` | `device:${string}/${string}`    // device:<node>/<address>
```

- **Parametric role = role + scope** in the assignment, the Kubernetes / Azure pattern (04 §1.2): `{ subject: 'group:flat3-tenants', role: 'tenant', scope: 'zone:flat3' }`. A scope covers what is below it.
- **Zone** (D8): a site-wide name on a level, room or group (design 12a §6); a device is in the zones of its group, room and level. The IdP needs zone names only; `device:` scopes are node-local and belong to local assignments.
- In authentik: group attribute `{ "evok": [{ "role": "tenant", "scope": "zone:flat3" }] }` (01 §3, P2).
- **Privilege of a call** from metadata: `$introspect`, GET, SUBSCRIBE, `effect: 'none'` → view; SET, `mutates` → operate; a method may raise it (`privilege: 'manage'` — thermostat `SystemMode`, Matter's split, 04 §5).
- **Additive only**; boundaries live in the hierarchy (04 P3).
- **Compiled per session:** `address → privilege bits` from assignments × the api's projection; rebuilt on assignment, introspection or level change; live subscriptions re-checked on rebuild (04 §3, the EMQX lesson). The same table filters introspection (04 P7).
- Raw drivers in the Inspector: `node:` or `device:` scopes only.
- **Imported devices** (design 12a §4b): the node that serves the client decides by its own hierarchy; the source node checks the peer (§2.7).

### 2.5. Replica, sync and offline

- **Poll is the truth, SCIM push is the fast path** (05 P1): the replica polls authentik's REST API at start, at reconnect and every N minutes, with a per-node service-account token; an optional SCIM receiver takes pushes (authentik must reach the node; one SCIM provider per node). Users have a `last_updated__gt` filter (01 §6); groups and deletions need a full compare [GAP — check the group API]. A logout webhook or back-channel logout is only a "sync now" hint. A `DirectorySource` adapter keeps Keycloak possible (no SCIM out, 05 §1.3).
- **Synced:** user id, name, active flag, groups, membership, role attributes. Never passwords (05 P2).
- **Offline credentials only after an online login on this node** (05 P3): PIN verifiers and device keys are enrolled per node (D6, D13).
- **PIN protection** (05 P4): Argon2id verifier (`crypto.argon2`, scrypt fallback, 01 §10); a failure counter written before each check; growing delays; a TPM-held HMAC key where there is a TPM.
- **Local deny list** wins over sync until an admin clears it; full pull at reconnect closes sessions of users now inactive (05 P6).
- **Clock (D14):** after a site-wide power cut neither NAS nor NTP may be there. Node-signed tokens are issued and checked by one clock, so skew cancels (02 §7); the saved time is behind, never ahead, so "last online login ≤ 14 d" errs by at most the outage.

### 2.6. Client apps

- Shell sign-in at authentik in the system browser with PKCE S256 (authentik does not enforce PKCE, 06 §1.1). Redirect type: D22.
- **Two hardware keys per install and site:** a session key (DPoP, also the `bound_key`) without user auth, and a per-use biometric step-up key (06 P1). Passcode fallback and re-enrolment: D11.
- The web app inside the shell gets short-lived node tokens over the bridge; refresh token and keys stay native; the bridge serves the main frame and pinned node origins only (06 §7, CVE-2026-44698).
- Plain browser on a node: the node is the BFF — login, HttpOnly cookie, `Origin` check at upgrade (06 §1.2). A `Secure` cookie and passkeys need HTTPS without errors, i.e. a DNS name and a trusted certificate (D12).
- **Local IdP in the shell:** the login page is on the node, and a self-signed node breaks the system-browser flow (06 §5). The shell may log in natively over its pinned connection — RFC 8252 targets third-party IdPs; here the IdP is the node the app already pins [I] (D12).
- Wall panel = a `client:` principal with a scoped role; a `proof` method needs a person's PIN, and that person becomes `actor` (06 P7).
- Enrolment by QR: node URL + certificate fingerprint + one-time code (06 P6).

### 2.7. PLC to PLC

- Each node has a key pair, made at install (a sensitive key, design 06 §5a).
- **Trust without the IdP at runtime:** a peer's public key comes from the directory (site: the node as an authentik service account, its key as an attribute written by the admin) or from pairing by code or QR in the Inspector (D16).
- `RemoteLink`'s hello: the peer sends a nonce, the caller signs it with its node key — no clock needed between nodes; TLS pinned to the peer's key.
- A peer is a principal: `{ subject: 'node:garden', role: 'peer', scope: 'device:house/ONB:2.unipi.ro.04' }` — the bypass relay of design 12i §5.3.
- **A call relayed for a user** (an imported `DoorLock`) meets two gates: the user's at node A, the peer's at node B. Today design 13 §5 makes B overwrite `actor` with node A, and B wants proof too. Needed: **delegation** — B keeps `actor` from a peer allowed to delegate, recorded as `act: node A` (RFC 8693's `act`, 02 §4), and trusts A's proof or checks an end-to-end one (D9).

## 3. Fit with the current design

| Where | Today | With §2 |
|---|---|---|
| design 13 §5 | api overwrites `actor` with its caller; `proof` per method; a rule passes no `actor` | add peer delegation (§2.7); rules and `proof` (D10) |
| design 05a §3.1 | `proof?: true` | stays a boolean — the kinds asked are 13a's policy; optional `privilege` per method (D15) |
| design 13 §2 | `onConnection`, `onRequest` | as §2.2; the WS API needs a wire error with a challenge (M3.8) |
| WS API, Home API (M3.8, M3.11) | auth deferred | hello `auth`, in-band `auth`, `proofNeeded`, close codes |
| new | — | `driver-auth` (driver), `api-auth` (HTTP api); both go into design 01 §11 and basics/01 |
| `driver-auth` exposure | — | management tails (`administer`) may be relayed by the WS API; session and proof tails never (D17) |
| design 06 §5a | sensitive keys, 0600 | PIN verifiers, node key, service-account token are sensitive; storage D18 |
| design 12a §6 | level → room → group | zone names on hierarchy nodes (D8) |
| design 12a §4b, 05a §3.8b, 07 §4.1 | credentials deferred | nonce signed by the node key + pinned TLS (§2.7) |
| design 12c-09 §1.2 | Open: what proof asks | `uv` or `pin`; `ack` per D5 |
| design 12c-07 §6 | proof only for access kinds of one `Closure` type | D19 |
| design 16a | own auth; DoorLock and access closures not exposed | unchanged (D23) |
| design 01 §2 | an api is a stateless translator | holds: state is in `driver-auth`; `api-auth` translates HTTP |
| M3.6 task | authentik upstream; "local DB as a new driver kind" | matches `driver-auth`; the two situations to be added to the task text |

## 4. Decisions for Tomas

**Before 13a** — they shape its structure:

| # | Decide | Options | Proposal |
|---|---|---|---|
| D1 | Replica and local IdP | one driver, two directory sources · two components | one driver |
| D2 | How a node accepts the site login | authentik ID token for the site client, key-bound + DPoP to this node · one authentik provider per node (`aud` = node) · RFC 8693 exchange at authentik (online only) | key-bound ID token |
| D3 | Who holds the authentik session | shell app · each node (needs `refresh_token_threshold`) · BFF node for browsers | shell app; a BFF node only for a plain browser. Departs from "the replica refreshes" for the IdP session only — node sessions are still refreshed by the replica |
| D4 | Level model | session levels · per-operation proof · both | both; levels `l1`, `l2`; freshness apart |
| D5 | Unlock with a confirmation only | earlier door-lock decision (2026-10-25: logged-in user only confirms) vs today's input (unlock → biometry or PIN): keep `ack` · `ack` only after a `uv` ≤ 5 min · always `uv`/`pin` | `ack` only after a fresh `uv`; Google forbids ack-only (03 §5) |
| D6 | The PIN evok-node checks | **kind:** confirming (pick yourself from a list, then PIN) · identifying (site-unique) — **door PIN:** separate from the 2N keypad PIN · the same (then clear at the IdP) — **where:** per node, enrolled online · hashed in an authentik attribute (write path, LDAP exposure) | confirming; separate from 2N; per node |
| D7 | Session lifetimes | online: access 10 min, idle 30 d, absolute? (AAL1 SHOULD reauth ≤ 30 d, 03 §1.1) · one-time local: single connection · ≤ 12 h | online 10 min / 30 d idle / 30 d absolute; one-time ≤ 12 h, no refresh, last online login here ≤ 14 d, 5 PIN failures then delays |
| D8 | What a role scope points to | zone names · hierarchy ids · devices only | zones + `node:` + `device:` |
| D9 | Calls relayed between PLCs | delegation, B trusts A's proof · end-to-end proof from the client to B · no `proof` methods across PLCs | delegation, B trusts A |
| D10 | Rules calling `proof` methods | never · allowed when the author proved `l2` at creation · admin flag per rule | consent at creation |
| D11 | Biometric key policy | passcode fallback counts (`.userPresence`) · biometry only (`biometryCurrentSet`), PIN when the key is invalidated | biometry only + PIN fallback; re-register when online |
| D12 | Node names and TLS | IP + pinning in the shell only · DNS names (owned domain, DNS-01) · vendor zone (Plex-like) | DNS names recommended (06 P5); IP + pinning still works for the shell; a plain browser at an IP gets no passkeys and no `Secure` cookie |
| D13 | Device keys | registered at each node where the app opens a session · published in an authentik attribute to all nodes (05 P2, 06 P1) | per node — no IdP write path |
| D14 | Offline clock | refuse offline login until time is synced · allow on the saved time (behind by the outage) | allow, logged |

**Can wait** for the 13a write-up or later tasks:

| # | Decide | Options | Proposal |
|---|---|---|---|
| D15 | Privilege of a call | `effect` only · `effect` + per-method `privilege` | override |
| D16 | PLC-to-PLC trust | node keys + pinned TLS (directory or pairing) · mTLS with a site CA (02 P6) — who runs it | node keys + pinning |
| D17 | Internal tails of `driver-auth` | "not relayable" mark in metadata · fixed ACL rule · a separate driver | mark |
| D18 | Storage | KV driver · own `node:sqlite` file in `driver-auth` | own file, 0600 (one owner, design 01 §7) |
| D19 | Proof for access closures | separate DeviceType `AccessClosure` · per-device proof flag · proof by zone/category in auth policy | separate DeviceType |
| D20 | Library | own token service on `jose` + `openid-client` · `oidc-provider` | own; `oidc-provider` only if third-party OIDC clients come |
| D21 | Sync interval and hints | N minutes; back-channel logout; webhook | N = 5 min; webhook as a hint |
| D22 | Shell redirect (M3.7) | claimed https on a vendor domain (registered in each authentik) · custom scheme | claimed https, custom scheme as fallback |
| D23 | Matter (M3.13) | `DoorLock` and access closures on Matter; one bridge vs one per flat; per-fabric ACL targets per flat (04 P8) | out of M3.6; with research/matter/08 P11–P16 |

## 5. Next steps

1. Tomas answers D1–D14.
2. Designer: 13a — scope · components · directory and roles · sessions and tokens · levels and proof · WS extensions · `api-auth` · replica and offline · PLC to PLC · client contract (feeds M3.7) · storage and secrets · testing.
3. Same change set: design 13 §5 (delegation, rules), 05a §3.1 (`privilege`, not relayable), 12c-09 §1.2 and 12c-07 §6 Opens, 12a §4b / 05a §3.8b / 07 §4.1 credentials, 12a §6 zones, the M3.6 task text, `STATUS.md`.
4. GAPs to settle on hardware or by test: Patron RTC and TPM; `crypto.argon2` in the Node build on Unipi; the §2.4 table on a Cortex-A53; authentik `amr` after an in-flow step-up; authentik group API for incremental sync; the PIN attribute Access Commander reads over LDAP; Chrome LNA for WebSockets.
