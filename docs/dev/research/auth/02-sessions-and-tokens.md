# 02 — Sessions and tokens

**Research, not design.** Token formats, refresh, revocation, proof-of-possession, node-limited tokens, auth over WebSocket, PLC-to-PLC credentials and clocks. Feeds 13a (M3.6).

## 1. Token formats

### 1.1. Comparison

| Format | Verify with | Offline verify | Holder can attenuate | Revocation | Node 24 library |
|---|---|---|---|---|---|
| Opaque + introspection (RFC 7662) | call to the issuer | no [I] | no | immediate at issuer [I] | `oidc-provider` / `openid-client` [V S40][V S41] |
| JWT access token (RFC 9068) | issuer public key (JWKS) | yes | no | none built in; short `exp` or a deny list [I] | `jose` 6.2.14 [V S43] |
| PASETO v4.public | Ed25519 public key | yes | no | as JWT | `paseto` 4.0.1 (panva, rewrite 2026-09) [V S42][V S43] |
| Biscuit v3 | root public key | yes | **yes, offline, no key needed** | revocation IDs (one per block); verifier needs the list [V S3] | `@biscuit-auth/biscuit-wasm` 0.6.0 (2025-09-26) [V S43] |
| Macaroon | **root secret (HMAC)** | only where the secret is | yes, offline | as JWT | `macaroon` 3.0.4, last publish 2022 [V S43] |
| CWT (RFC 8392) | COSE key | yes | no | as JWT | [GAP] — no Node lib checked |

- RFC 9068: `typ` MUST be `at+jwt`; required claims `iss exp aud sub client_id iat jti`; optional `auth_time acr amr`; `roles` / `groups` / `entitlements` SHOULD be the claim names for roles [V S1 §2.1, §2.2, §2.2.3.1]. Resource server MUST check `typ`, `iss`, `aud` (must name this server), signature, `exp` ("small leeway") [V S1 §4]. Claims are readable by the client; use opaque tokens or encryption if that matters [V S1 §6].
- PASETO v4.public = Ed25519, no algorithm choice in the token ("versioned protocols") [V S2]. `exp`/`iat` are RFC 3339 strings, not numbers [V S2 Claims]. Not an IETF standard [I].
- Biscuit: blocks of Datalog (facts, rules, checks); the first ("authority") block gives rights, every later block can only add checks [V S3 Overview]. The token carries the private key of its last block, so **any holder** can append a block; sealing removes that ability [V S3 Cryptography]. Algorithms Ed25519 and ECDSA P-256 [V S3][V-src S4]. Time is not built in: `time(...)` is a fact the **verifier** supplies [V-src S45].
- Macaroons: chained HMAC; verification "requires knowledge of its root key" [V S5 §IV-D]. So every verifying PLC would hold a secret that can also **mint** tokens; poor fit for multi-node sites [I].
- CWT: CBOR + COSE, integer claim keys (`iss`=1, `sub`=2, `aud`=3, `exp`=4), JWT semantics, made for constrained IoT [V S6 §1, §3, §4]. No advantage on a 1 GB Linux PLC [I].

### 1.2. Example — "u-42, tenant of flat 3, node basement only, level PIN"

JWT (RFC 9068 shape):
```json
{"typ":"at+jwt","alg":"EdDSA","kid":"k1"}
{"iss":"https://auth.site-a.example/application/o/evok/","sub":"u-42",
 "aud":"urn:evok:site-a:node:basement","client_id":"home-ui","iat":1793376000,
 "exp":1793376900,"jti":"f3c1…","acr":"pin","roles":["tenant:flat-3"]}
```
Biscuit (authority block signed by the issuer; block 1 appended later by anyone, no key):
```
authority: user("u-42"); role("tenant","flat-3"); acr("pin"); site("site-a");
           check if time($t), $t <= 2026-10-30T16:15:00Z;
block 1:   check if node("basement");
node authorizer: time(2026-10-30T16:05:00Z); node("basement"); operation("unlock");
                 allow if role("tenant","flat-3"), acr("pin"); deny if true;
```
Result: allow on `basement`, deny on `garden` [V-src S45].

### 1.3. Measured size and speed (x86-64, Node 22; ARM A53 will be slower [I])

| Token (same claims) | Chars | Verify |
|---|---|---|
| JWT EdDSA / ES256 / RS256 | 473 / 473 / 729 | EdDSA ≈ 0.2 ms (`jose`) |
| PASETO v4.public | 468 | — |
| Biscuit authority / +1 block / sealed | 376 / 616 / 660 (no `iss` URL, `jti`, `client_id` inside) | parse + verify + authorize ≈ 0.7 ms |

All [V-src S45]. Biscuit WASM file is 2.35 MB [V-src S45].

### 1.4. Patterns that mix self-contained and stateful

- **Home Assistant:** access token = HS256 JWT, `iss` = refresh-token id, signed with a key stored **per refresh token**; verify = look up refresh token, check key, check user active [V-src S26]. So deleting the refresh token kills all its access tokens at once; not stateless, but an in-memory lookup [I].
- **Kubernetes bound SA tokens:** JWT, plus the API server checks the bound object (Pod / Node) still exists and its UID matches [V S23].
- Fits a replica that keeps a session table in memory: token proves "who and which session", table decides "still valid" [I].

## 2. Sessions, refresh, proof-of-possession

IdP session (login at the IdP, `sid`) and a client's tokens have separate lifetimes; back-channel logout links them (§3) [V S12 §2.4, §2.7].

### 2.1. Typical lifetimes (defaults found)

| System | Access | Refresh | Other |
|---|---|---|---|
| `oidc-provider` 9.x | 1 h | 14 d; rotation extends up to 1 year | Session 14 d, Grant 14 d, client credentials 10 min, auth code 60 s [V S40 ttl, rotateRefreshToken] |
| Home Assistant | 30 min | 90 d | long-lived token: lifespan in days chosen at creation [V-src S26] |
| Kubernetes SA token | 1 h default, min 10 min | — (kubelet re-fetches at 80 % TTL or 24 h) | [V S24] |
| authentik | → (01) | → (01) | |

### 2.2. Refresh-token rules (RFC 9700)

- Refresh tokens for public clients MUST be sender-constrained **or** rotated [V S7 §2.2.2].
- Rotation: new refresh token on every refresh; old one invalid but its relation kept. If an old token is used again, the AS cannot tell attacker from client, so it **revokes the active refresh token** (whole chain) [V S7 §4.14.2].
- Refresh tokens MUST be bound to the consented scope and resource servers [V S7 §4.14.2].
- MAY revoke on password change or logout; SHOULD expire after a period of inactivity [V S7 §4.14.2].
- Access tokens SHOULD be audience-restricted to one resource server [V S7 §2.3].
- `oidc-provider` default: always rotate refresh tokens of public clients that are not sender-constrained; on reuse, revoke the whole grant [V S40].
- If clients hold **IdP** refresh tokens and the IdP rotates them, a replica that refreshes offline either forks the chain (reuse detection may then revoke it when the IdP returns) or must issue its **own** node refresh tokens [I] (→ 05).

### 2.3. Sender-constrained tokens

| | DPoP (RFC 9449) | mTLS-bound (RFC 8705) |
|---|---|---|
| Binding | `cnf.jkt` = thumbprint of client public key [V S8 §6.1] | `cnf.x5t#S256` = client cert thumbprint [V S9 §3.1] |
| Per request | signed proof JWT: `typ dpop+jwt`, `jti htm htu iat`, `ath` with a token, `nonce` if server asks [V S8 §4.2] | TLS client cert on the connection |
| Refresh token | bound to the DPoP key for public clients [V S8 §5] | SHOULD be bound for public clients [V S9 §4] |
| Browser | yes — non-extractable WebCrypto key; stolen token alone is useless, but XSS can still make proofs while the page is open [V S8 §2, §11.4] | poor — certificate prompts [V S9 §5, §6.4] |
| Native / shell app | yes, key in OS key store (→ 06) [I] | possible, TLS-stack dependent [I] |
| PLC | yes (key in 0600 file or TPM on Edge) [I] | natural fit [I] |
| WebSocket | proof covers HTTP method + URI only [V S8 §4.2]; browser cannot add a `DPoP` header to the WS handshake [I]; would need a proof in the first message (no standard) [I] | works on `wss` if TLS ends at evok-node [I] |

- DPoP replay: accept proofs only for seconds–minutes; keep `jti`s for that window; a server nonce with server time avoids client clock problems [V S8 §11.1].

## 3. Revocation and logout

| Mechanism | Status | Direction | Fit for evok-node |
|---|---|---|---|
| RFC 7009 revocation | RFC; in `oidc-provider`, `openid-client` [V S40][V S41] | client → AS | client logout at replica / IdP [I] |
| RFC 7662 introspection | RFC; same libs [V S40] | RS → AS, online per check | needs the IdP online; not for the hot path [I] |
| OIDC Back-Channel Logout 1.0 | Final (errata set 1, 2023-12-15) [V S12] | OP → RP HTTP POST of a signed `logout_token` (`iss aud iat exp jti events`, `sub` and/or `sid`, no `nonce`) [V S12 §2.4, §2.5] | RP must be reachable from the OP; retry only on suspected recoverable errors [V S12 §1, §2.5] |
| authentik back-channel logout | docs mark it "2025.8.0+ Preview"; sent on logout, admin session delete, user deactivation, session expiry/revoke [V S17] | | works if authentik can reach the node on the LAN [I] |
| OpenID SSF 1.0 + CAEP 1.0 | Final (CAEP published 2025-08-29); adopters named: Apple, IBM, Okta [V S13][V S15][V S16] | push (RFC 8935) **or poll** (RFC 8936) [V S14 §6.1] | poll suits a node behind NAT [I] |
| authentik SSF | transmitter, push webhooks, "Enterprise" label; main receiver Apple Business Manager [V S19] | | licence and LAN reachability needed [I] |
| Short TTL | — | — | the fallback that always works [I] |

- CAEP events: session-revoked, token-claims-change, credential-change, assurance-level-change, device-compliance-change, session-established, session-presented, risk-level-change [V S15 §3].
- Back-channel logout: refresh tokens without `offline_access` SHOULD be revoked; with `offline_access` normally not [V S12 §2.7].

**An offline verifier** [I]:

| Can know | Cannot know |
|---|---|
| signature, `aud`, `iss`; `exp` against its own clock | revocations, password or role changes at the IdP since last sync |
| its own sessions and revocations (local table) | whether its clock is right, unless synced (§7) |
| its own `jti`/replay cache | use of the same token on other nodes |

## 4. Node-limited tokens

- **Audience:** `aud` names the node; RFC 8707 `resource` asks the AS for it; AS SHOULD restrict `aud` to it and can down-scope [V S10 §2, §2.2]. A token with several audiences can be used at any of them [V S10 §3].
- **Token exchange (RFC 8693):** the AS acts as STS; `subject_token`, optional `actor_token`, `audience`/`resource`, `scope`; `act` claim records delegation [V S11 §1, §2.1, §4.1]. Narrowing is AS policy, not required [V S11 §2.1.1].
- **authentik token exchange:** accepts access-token/JWT subject tokens; `audience` = another provider's `client_id` (one only); rejects `resource` (`invalid_target`); issues only requested scopes; delegation from 2026.8.0 [V S18]. **Needs the IdP online** — no help when it is down [I].
- **Biscuit attenuation:** the replica (or the client) appends `check if node("basement")` — no key, offline [V-src S45]. But a block can only **add** checks: it cannot extend the original expiry [V S3 Overview]. So it does not give an offline **refresh** [I].
- **Node-signed token:** the replica signs with its own node key, `iss` = node, `aud` = node. Only that node trusts the key, so the token is node-only by construction; no other node must trust anything new [I]. Local-IdP mode is the same thing [I].

Who signs, who trusts [I]:

| Option | Signer | Must trust the key | Works with IdP down |
|---|---|---|---|
| IdP token, `aud` = node | site IdP | each node (IdP JWKS) | verify yes; new tokens no |
| RFC 8693 exchange | site IdP | target node | no |
| Biscuit attenuated | IdP (authority) + holder | each node (root key) | yes, but only until original expiry |
| Node-signed | node replica | that node only | yes |

Real systems where an edge component mints or checks local credentials:

| System | What it does |
|---|---|
| AWS IoT Greengrass v2 | core device creates a **local CA**, signs the local MQTT broker cert (7 d default, 2–10 d, rotated 24 h before expiry; broker restart drops clients) [V S20][V S21]; client identity checked **with the cloud** [V S21]; trust of a client lasts `clientDeviceTrustDurationMinutes` = 1 min default; optional offline auth [V S20]; exact offline cache rules [GAP] |
| Azure IoT Edge | edgeHub authenticates modules and child devices "on behalf of IoT Hub"; works offline indefinitely after one sync [V S22]; which credentials are cached [GAP] |
| Kubernetes | API server issues JWTs bound to Pod / Node with `aud` and `exp`; checks the object still exists; node-bound tokens GA 1.33 [V S23] |

## 5. Auth over WebSocket

The browser WebSocket API cannot set custom headers, only cookies/Basic are sent implicitly [V S34].

| Option | Risk / limit | Precedent |
|---|---|---|
| Cookie | cross-site WebSocket hijacking; MUST check `Origin` against an allowlist [V S32]; `SameSite=Lax/Strict` helps [V S32]; cookie cannot be set for another origin [V S33] → a Home UI on node A cannot easily use a cookie for node B [I] | most web apps |
| Token in query string | URLs end up in logs; "usually considered unacceptable" [V S33][V S32] | |
| `Sec-WebSocket-Protocol` | `base64url.bearer.authorization.k8s.io.<token>`; client must offer a second real subprotocol for the server to echo [V-src S25]; header may still be logged by proxies [I] | Kubernetes API server |
| One-time ticket over HTTPS | ticket stored server-side, checked for reuse, expiry, source IP [V S34]; extra HTTP round trip [I] | |
| First-message auth | "most secure" of the options [V S33]; accept nothing else until auth OK, close on failure/timeout [V S32] | Home Assistant, graphql-ws |

- `ws` (Node): check `Origin` and auth in the HTTP server `upgrade` event before `handleUpgrade` [V S32].
- `Origin` is advisory: non-browser clients set any value [V S34].

### 5.1. What existing protocols do

| Protocol | Auth | Token expires on open connection | Revocation |
|---|---|---|---|
| Home Assistant WS | server sends `auth_required`; client `auth` with `access_token`; `auth_ok` / `auth_invalid`; 10 s timeout [V-src S26] | **ignored** — checked only at auth [V-src S26] | connection closed when its refresh token is revoked (callback) [V-src S26] |
| graphql-ws | `connection_init` payload; reject with close 4403; timeout 4408 [V S27] | second `connection_init` → close 4429, so no in-band re-auth [V S27]; recipe: client closes with 4403 at expiry, refreshes, reconnects; subscriptions resubscribe automatically [V S27] | server closes |
| Socket.IO | `auth` object in handshake; middleware runs once per connection [V S28] | nothing built in [V S28] | app closes |
| MQTT 5 | CONNECT Authentication Method/Data [V S31 §3.1.2.11.9–10] | client-initiated re-auth: AUTH reason 0x19; traffic continues during re-auth [V S29]; failure → DISCONNECT (Mosquitto: Not authorized) [V-src S30] | broker disconnects |

- OWASP: close the connection when the session expires; re-validate long connections (every 30 min is common); close all of a user's connections on logout [V S32].
- **Step-up inside an open connection:** only MQTT 5 enhanced auth has a protocol form (client-initiated) [V S29]; the broker can only disconnect [I]. graphql-ws reconnects [V S27]. Levels → (03).

## 6. PLC-to-PLC credentials

Requirement: PLC-to-PLC links keep working with the IdP down.

| Option | Enrolment | Rotation | IdP down |
|---|---|---|---|
| OAuth client credentials (RFC 6749 §4.4) | client registered at AS | AS policy | **fails** — AS issues the access tokens [I] |
| `private_key_jwt` (RFC 7523) | register public key at AS | client rotates key | **fails** at AS [I]; a peer could verify a self-signed assertion directly, but that is not OAuth [I]; supported in `oidc-provider` [V S40] |
| mTLS, site CA (`tls_client_auth`) or pinned certs (`self_signed_tls_client_auth`) | CSR signed by site CA, or cert registered [V S9 §2] | re-issue before expiry (Greengrass: days) [V S21] | **works**; CA key needed only to enrol [I] |
| Long-lived API token (HA style) | admin creates, copies to peer | manual; lifespan chosen [V-src S26] | **works** if the target node issued and verifies it [I] |
| Noise PSK (ESPHome) | 32-byte key in config, or set on first connection if none [V-src S35]; `Noise_NNpsk0_25519_ChaChaPoly_SHA256` [V-src S35] | manual | **works**; shared secret per link [I] |
| Matter-style commissioning | PASE (SPAKE2+) with a 27-bit setup PIN code / QR, then CASE sessions [V S36]; operational certs from a fabric CA [I] | fabric admin | **works** [I] |
| SPIFFE (concept) | SPIFFE ID + SVID (X.509 or JWT) from a local Workload API; CA bundles for federation [V S37] | short-lived, automatic | depends on local issuer [I] |

- Pairing pattern seen: short code or QR proves physical access (Matter), or "trust on first connection" (ESPHome unprovisioned) [V S36][V-src S35].

## 7. Clocks

- `exp`, `nbf`, DPoP `iat`, Biscuit `time` all need wall-clock time [V S1 §4][V S8 §11.1][V-src S45].
- Leeway seen: `jose` 0 s default (`clockTolerance`), `currentDate` option lets the caller pass its own "trusted now" [V S39][V-src S39]; `oidc-provider` 15 s [V S40]; Home Assistant 10 s [V-src S26].
- `systemd-timesyncd` saves the time every 60 s (`SaveIntervalSec`, for systems "with no local RTC") and at boot moves the clock forward to that saved time → "roughly monotonic" [V S38]. After a power cut of N hours the clock is ~N hours **behind** until NTP sync → tokens that expired during the cut look valid [I].
- Sync signals: `/run/systemd/timesync/synchronized` is touched on each sync; `systemd-time-wait-sync` / `time-sync.target` delay units until synced [V S38].
- RTC: Edge has one (brief); Patron and Neuron [GAP] — check Unipi hardware docs.
- Mitigations [I]: (a) monotonic clock (`performance.now()`) for in-process timeouts; (b) last-known time from disk as a floor; (c) server or peer time in the `hello` / `auth_ok` (DPoP nonce precedent [V S8 §11.1]); (d) refuse expiry-sensitive actions until synced; (e) tokens issued by the node itself use the node's clock for both issue and check, so skew cancels out.

## 8. Node libraries (versions from npm, 2026-10-30)

| Package | Version | Notes |
|---|---|---|
| `jose` | 6.2.14 (published 2026-10-29) | JWT/JWS/JWE/JWK; v6 supported; zero runtime deps [V S39][V S43] |
| `oidc-provider` | 9.13.3 (2026-10-29) | AS: JWT AT (RFC 9068), DPoP, mTLS, resource indicators, revocation, introspection, back-channel logout; token exchange only via `registerGrantType` (custom handler) [V S40] |
| `openid-client` | 6.8.8 (2026-09-05) | RP: DPoP, introspection, revocation, client credentials, refresh [V S41]; `genericGrantRequest` for other grants [V-src S41] |
| `@biscuit-auth/biscuit-wasm` | 0.6.0 (2025-09-26) | Rust core in WASM; `engines` node ≥ 22; README asks for `--experimental-wasm-modules` [V S4][V-src S4], which Node 24.5.0 unflagged [V S44]; last release > 1 year ago; commit activity [GAP] |
| `paseto` | 4.0.1 (2026-09-04) | panva rewrite, zero deps, WebCrypto; v3.1.4 was 2023 [V S42][V S43] |
| `macaroon` | 3.0.4 (2022) | stale [V S43] |
| Node 24 | 24.22.2 LTS (2026-10-28) | [V S44] |

## 9. Proposals for 13a (not binding)

- **P1 — Node-signed access tokens.** Replica and local IdP issue the same short JWT (`at+jwt`, EdDSA, `iss` = `aud` = node, 5–15 min) from their session table; IdP tokens stay between replica and IdP. Node-only by construction; offline refresh uses the same path.
- **P2 — Stateful check in `onConnection`.** Token carries session id; the replica's in-memory table decides validity (HA / Kubernetes pattern). Revocation is then immediate on the node.
- **P3 — First-message auth on WS.** HA-style `auth_required` → `auth` → `auth_ok`, 10 s timeout, nothing else before; `Origin` allowlist in `upgrade`; no tokens in URLs.
- **P4 — In-band re-auth, close at expiry.** Client sends a new `auth` with a fresh token on the open socket; server closes (4403-style code) at `exp` + small grace if none came, and at once on revoke. Same message can raise the auth level.
- **P5 — Refresh tokens.** Opaque, rotated with reuse detection (RFC 9700); DPoP-bound where the client has a key store (shell app).
- **P6 — PLC-to-PLC by mTLS with a site CA** (or pinned certs), enrolled with a pairing code + admin approval; no IdP in the runtime path; peer roles from the replica.
- **P7 — Trusted time.** Treat the clock as trusted only after NTP or peer sync; until then refuse new offline sessions and expiry-sensitive proofs; send server time in `auth_ok`.
- **P8 — Biscuit later, not now.** Useful for delegation (guest, installer) but cannot do offline refresh; JWT + `jose` covers M3.6.
- **P9 — Revocation feed.** Short TTL as base; back-channel logout from authentik where it can reach the node; SSF poll as an option (Enterprise); full resync on reconnect (→ 05).

## 10. Sources

- S1 — RFC 9068 JWT Profile for OAuth 2.0 Access Tokens: https://rfc-editor.org/rfc/rfc9068.html
- S2 — PASETO spec (Version4.md, 04-Claims.md): https://github.com/paseto-standard/paseto-spec
- S3 — Biscuit specification: https://github.com/eclipse-biscuit/biscuit/blob/main/SPECIFICATIONS.md
- S4 — biscuit-wasm repo and package: https://github.com/eclipse-biscuit/biscuit-wasm
- S5 — Birgisson et al., Macaroons, NDSS 2014: https://www.ndss-symposium.org/wp-content/uploads/2017/09/04_3_1.pdf
- S6 — RFC 8392 CBOR Web Token: https://rfc-editor.org/rfc/rfc8392
- S7 — RFC 9700 OAuth 2.0 Security BCP: https://datatracker.ietf.org/doc/html/rfc9700 (§4.14.2 read from the draft source: https://github.com/oauthstuff/draft-ietf-oauth-security-topics/blob/master/A04_attacks-and-mitigations.md)
- S8 — RFC 9449 DPoP: https://rfc-editor.org/rfc/rfc9449.html
- S9 — RFC 8705 OAuth mTLS: https://rfc-editor.org/rfc/rfc8705.html
- S10 — RFC 8707 Resource Indicators: https://rfc-editor.org/rfc/rfc8707.html
- S11 — RFC 8693 Token Exchange: https://rfc-editor.org/rfc/rfc8693.html
- S12 — OpenID Connect Back-Channel Logout 1.0: https://openid.net/specs/openid-connect-backchannel-1_0.html
- S13 — OpenID Shared Signals WG specifications: https://openid.net/wg/sharedsignals/specifications/
- S14 — OpenID SSF 1.0 Final: https://openid.net/specs/openid-sharedsignals-framework-1_0-final.html
- S15 — OpenID CAEP 1.0 Final: https://openid.net/specs/openid-caep-1_0-final.html
- S16 — Help Net Security, OIDF approves SSF/CAEP/RISC (2025-09-22): https://www.helpnetsecurity.com/2025/09/22/openid-standards-real-time-security-event-sharing/
- S17 — authentik front-/back-channel logout: https://docs.goauthentik.io/add-secure-apps/providers/oauth2/frontchannel_and_backchannel_logout/
- S18 — authentik token exchange: https://docs.goauthentik.io/add-secure-apps/providers/oauth2/token_exchange/
- S19 — authentik SSF provider: https://docs.goauthentik.io/add-secure-apps/providers/ssf/
- S20 — AWS Greengrass client device auth component: https://docs.aws.amazon.com/greengrass/v2/developerguide/client-device-auth-component.html
- S21 — AWS Greengrass device authentication: https://docs.aws.amazon.com/greengrass/v2/developerguide/device-auth
- S22 — Azure IoT Edge offline capabilities: https://learn.microsoft.com/azure/iot-edge/offline-capabilities
- S23 — KEP-4193 bound service account token improvements: https://www.kubernetes.dev/resources/keps/4193/
- S24 — Netdata guide, Kubernetes bound SA tokens (secondary): https://www.netdata.cloud/guides/kubernetes/kubernetes-bound-service-account-tokens/
- S25 — Kubernetes WebSocket bearer subprotocol (source): https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/apiserver/pkg/authentication/request/websocket/protocol.go
- S26 — Home Assistant source (`components/websocket_api/{auth,http,connection}.py`, `auth/__init__.py`, `auth/const.py`, `components/auth/__init__.py`): https://github.com/home-assistant/core/tree/dev/homeassistant
- S27 — graphql-ws PROTOCOL.md and recipes: https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md
- S28 — Socket.IO middlewares: https://socket.io/docs/v4/middlewares/
- S29 — EMQX, MQTT 5.0 AUTH packet: https://www.emqx.com/en/blog/mqtt-5-0-control-packets-06-auth
- S30 — Mosquitto `src/handle_auth.c`: https://github.com/eclipse-mosquitto/mosquitto/blob/master/src/handle_auth.c
- S31 — MQTT 5.0 OASIS Standard (§4.12 not readable with the fetch tool): https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html
- S32 — OWASP WebSocket Security Cheat Sheet: https://github.com/OWASP/CheatSheetSeries/blob/master/cheatsheets/WebSocket_Security_Cheat_Sheet.md
- S33 — python-websockets, Authentication: https://websockets.readthedocs.io/en/stable/topics/authentication.html
- S34 — Heroku Dev Center, WebSocket Security: https://devcenter.heroku.com/articles/websocket-security
- S35 — ESPHome source (`components/api/__init__.py`) and aioesphomeapi `_frame_helper/noise.py`: https://github.com/esphome/aioesphomeapi
- S36 — Matter CHIP Tool guide: https://github.com/project-chip/connectedhomeip/blob/master/docs/development_controllers/chip-tool/chip_tool_guide.md
- S37 — SPIFFE standard: https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE.md
- S38 — systemd-timesyncd.service(8), timesyncd.conf(5): https://github.com/systemd/systemd/blob/main/man/systemd-timesyncd.service.xml
- S39 — jose (README, JWTVerifyOptions, `jwt_claims_set.js`): https://github.com/panva/jose
- S40 — oidc-provider README and docs: https://github.com/panva/node-oidc-provider
- S41 — openid-client README and docs: https://github.com/panva/openid-client
- S42 — paseto (panva) README: https://github.com/panva/paseto
- S43 — npm registry metadata (versions, dates): https://registry.npmjs.org/
- S44 — Node.js 24 changelog: https://github.com/nodejs/node/blob/main/doc/changelogs/CHANGELOG_V24.md
- S45 — Local test for this note: Node 22.23.4 x86-64, `jose` 6.2.14, `paseto` 4.0.1, `@biscuit-auth/biscuit-wasm` 0.6.0; same claims in each format; size, verify time, Biscuit attenuation allow/deny.
- Not fetched in this pass (search budget ran out): RFC 7009, RFC 7662, RFC 7523, RFC 6749 §4.4 text — statements about them are tagged [I].
