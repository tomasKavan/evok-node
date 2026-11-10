# 01 — Identity providers

**Research, not design.** External IdPs as the site IdP (authentik focus; Keycloak, Kanidm, Zitadel, Authelia, Pocket ID, Rauthy briefly) and Node libraries for evok-node's own local IdP and replica. Feeds 13a (M3.6).

Versions checked 2026-10-30: authentik 2026.8.5, Keycloak 26.8.1, Kanidm 1.11.2, Zitadel 4.20.0, Authelia 4.39.28, Pocket ID 2.19.1, Rauthy 0.37.2, oidc-provider 9.13.3, Node 24.22.x. Paths in tags such as `providers/scim` are files under the docs or source tree named in the source entry.

## 1. authentik: deployment and license

### 1.1. Release and components
- Latest release is 2026.8.5 (21 Oct 2026). The 2026.5 and 2026.2 lines still get patches [V S1]. The new "Base URL" setting becomes required in 2026.11 [V S2].
- Components: **server** (core plus embedded outpost), **worker** (background tasks) and **PostgreSQL** [V S6 core/architecture]. The default compose file runs postgres:16-alpine plus server and worker from one image [V-src S7 lifecycle/container/compose.yml].
- **Redis is not needed since 2025.10.** Cache, embedded outpost and WebSocket IPC moved to PostgreSQL. Sessions have been in PostgreSQL since 2025.4 [V S4].
- In 2026.8 the server entrypoint and proxy outpost were ported from Go to Rust (1:1, no speed-up yet). The Django core is unchanged [V S2]. In 2026.5 the worker got a Rust entrypoint, saving about 200 MB per worker [V S3].
- Outposts must run the same version as the core [V S2].

### 1.2. Footprint and ARM64
- Documented minimum: **2 CPU cores, 2 GB RAM** [V S5].
- Server and outpost images are built for amd64 and arm64 [V-src S7 .github/workflows/_reusable-container-build.yml, ci-outpost.yml].
- authentik does not fit on a 1 GB Patron next to evok-node: the documented minimum is 2 GB before PostgreSQL and evok-node are counted. It belongs on a NAS or server, so when the NAS is down authentik is down too [I]. See (05).

### 1.3. License
- MIT, except `authentik/enterprise/` (own license) and `website/` (CC BY-SA 4.0) [V-src S7 LICENSE].
- **Enterprise only**, where relevant here [V S6 enterprise/enterprise-features]:
  - SSF provider (pushes security events)
  - OAuth-token auth for SCIM (a static token is open source)
  - Account Lockdown, scheduled offboarding, agent accounts
  - Privileged access requests, enhanced audit, CSV export
  - mTLS client-certificate stage, RADIUS EAP-TLS
- **Open source**, where relevant:
  - OAuth2/OIDC, SAML, LDAP, RADIUS and SCIM providers
  - All authenticator stages, including WebAuthn
  - Notification webhooks, token exchange, object attributes [V S2, S6]
  - Dynamic Client Registration (DCR). Its code is in `authentik/providers/oauth2/` (MIT) [V-src S7 providers/oauth2/views/dcr.py], although the 2026.8 blog labels DCR "Enterprise" [V S8]; the code is what counts.

## 2. authentik: directory model

| Object | Facts |
|---|---|
| User | `attributes` holds free-form JSON. `group_attributes()` merges brand, then all groups (ordered by name), then the user, using deepmerge `always_merger` [V-src S7 core/models.py]. `user.groups` returns direct groups; `all_groups()` adds inherited ones [V S6 users-sources/user/user_ref]. |
| Group | Multiple `parents`. Members of a child group are effective members of the parent, and a binding to a parent includes its children. Groups have `attributes` [V S6 users-sources/groups]. In 2026.8 the LDAP source gained "Sync Group Parents" [V S2]. |
| Object attributes (2026.8, preview) | Typed fields (Text, Number, Boolean; required, unique, regex) on users, groups, application entitlements and device access groups. Values are stored as keys inside `attributes` [V S6 sys-mgmt/object-attributes]. |
| Role | A set of authentik permissions (on flows, users, …), assigned to users or groups and inherited down the group hierarchy [V S6 users-sources/roles]. Meant for authentik's own RBAC; it has no meaning for apps [I]. |
| **Application entitlement** | Named entitlement **per application**, with `attributes`, bound to users and/or groups [V S6 applications/manage_apps; V-src S7 core/models.py `ApplicationEntitlement(AttributesMixin…)`]. Read with `user.app_entitlements(app)`. The default `entitlements` scope emits both an `entitlements` and a `roles` claim, as lists of names [V-src S7 blueprints/system/providers-oauth2.yaml]. |
| Bindings | Since 2026.8, group, user and policy bindings can expire [V S2]. |

- The default `profile` scope puts **direct groups only** in the `groups` claim (`request.user.groups.all()`) [V-src S7 blueprints/system/providers-oauth2.yaml].

## 3. authentik: claims (scope mappings)

- A scope mapping is a Python expression that returns a dict of claims. Its context includes `user`, `request`, `token` and `provider` [V S6 providers/property-mappings; V-src S7 providers/oauth2/views/userinfo.py].
- Expressions may import authentik modules; the docs' own examples do it [V S6 stages/authenticator_validate, users-sources/groups/group_ref].
- Mapping claims always go to UserInfo. They go into the ID token and the JWT access token only when "Include claims in id_token" is on [V S6 providers/property-mappings].
- The access token is a JWT with the ID-token claims plus `azp` and `scope` [V-src S7 providers/oauth2/id_token.py `to_access_token`].
- Claims are fixed when a token is issued and change only on refresh [I].

Example: parametric roles from entitlements. The entitlement is named `tenant:flat-3` with attributes `{"role":"tenant","flat":3}`. Untested, written from the documented API [I].
```python
ents = request.user.app_entitlements(provider.application)
return {
    "roles": [e.name for e in ents],                             # ["tenant:flat-3", "admin"]
    "evok_roles": [e.attributes for e in ents if e.attributes],  # [{"role":"tenant","flat":3}]
}
```
The same from group attributes, where group "Flat 3 tenants" has `{"evok_roles":[{"role":"tenant","flat":3}]}` [I]:
```python
roles = []
for g in request.user.all_groups():
    roles += g.attributes.get("evok_roles", [])
return {"evok_roles": roles}
```

## 4. authentik: flows, stages and auth levels

- **Authenticator setup stages:** Duo, Email OTP, SMS, Static (generated one-time backup codes), TOTP, WebAuthn/passkeys. Endpoint/device stages are partly Enterprise [V S6 flows-stages/stages].
- **Authenticator Validation stage** [V S6 stages/authenticator_validate]:
  - Settings: allowed device classes; the action when nothing is enrolled (skip, deny or configure); WebAuthn user-verification requirement, device-type allowlist and hints; exponential throttling per OTP class.
  - **Last validation threshold:** validation is skipped if a compatible device was used inside the window. Windows below 30 s are useless for code-based devices.
- **No PIN stage exists** [V S6 stage list]. Ways to have a PIN anyway:
  - Store it as a user attribute. It is stored as plain JSON, visible in the admin API (`attributes`) [V-src S7 core/api/users.py] and exported by the LDAP outpost as an LDAP attribute [V S6 providers/ldap].
  - Store a hash in an attribute, written by a prompt stage and an expression policy [I].
- **ID token claims** [V-src S7 providers/oauth2/id_token.py, common/oauth/constants.py]:
  - `auth_time`: refresh keeps the original value [V-src S7 providers/oauth2/views/token.py].
  - `acr` is always `goauthentik.io/providers/oauth2/default`, the only value advertised in discovery [V-src S7 providers/oauth2/views/provider.py].
  - `amr` is derived from the **login event**: `pwd`, `user` (passwordless WebAuthn), `sc` (certificate), `mfa` (an MFA device was used).
  - Mapping claims are merged after the standard ones (`id_dict.update(self.claims)`), so a mapping could override `acr` or `amr` [V-src S7]. Whether that is useful or safe: [I].
- **Request parameters** [V-src S7 providers/oauth2/views/authorize.py]:
  - `acr_values` is **not parsed**.
  - `max_age` is honoured: re-authentication if the login event is older.
  - `prompt=login|none|consent` is honoured.
- **Step-up:** an Authenticator Validation stage could sit in the provider's authorization flow (it runs per app after login) and be bound by a policy on `request.context["oauth_scopes"]` [I]. `amr` would still show only the login event, so the RP could not see the step-up [I]. [GAP] Settle it with a test token from such a flow.
- For evok-node, authentik's auth-level signal is coarse (`pwd`, `mfa`, passkey). A door-unlock proof has to be collected by the api (03).

## 5. authentik: protocol endpoints

| Feature | authentik 2026.8 |
|---|---|
| Grants | Authorization code with PKCE, implicit, hybrid, client credentials, device code, refresh, token exchange. Each grant type can be switched off per provider (since 2026.5) [V S6 providers/oauth2/index; S3]. |
| Client credentials | Several ways to authenticate [V S6 providers/oauth2/machine_to_machine]:<br>• username plus app password<br>• the provider secret (creates a service account automatically)<br>• `client_assertion` = a JWT from a **federated OAuth source** (any JWKS) or from another authentik provider |
| Device code | `/application/o/device/`. Needs a device-code flow on the brand [V S6 providers/oauth2/device_code]. |
| Token exchange (RFC 8693) | Off by default. Impersonation, plus delegation with an `act` claim since 2026.8 [V S6 providers/oauth2/token_exchange; S2]. |
| Refresh | Only with the `offline_access` scope and its mapping [V S6].<br>Default lifetimes: code 1 min, access token 1 h, refresh token 30 d [V-src S7 providers/oauth2/models.py].<br>`refresh_token_threshold` defaults to 0, so every refresh rotates the token and marks the old one revoked. Reusing a revoked token gives `invalid_grant` and a `suspicious_request` event; the rest of the token family is not revoked [V-src S7 providers/oauth2/views/token.py, token/refresh_token.py]. |
| Introspection / revocation | Global `/application/o/introspect/` and `/revoke/`. Only confidential providers can introspect, and only their own tokens unless they are listed under "Federated OAuth2/OpenID Providers" [V S6 providers/oauth2/index]. |
| JWKS | Per application: `/application/o/<slug>/jwks/`. Without a signing key, tokens are HS256 with the client secret and no JWKS is published [V S6]. |
| Logout | RP-initiated, front-channel and back-channel. Back- and front-channel are preview since 2025.8, with one logout URI per provider; the RP must be reachable from authentik over HTTPS [V S6 providers/oauth2/frontchannel_and_backchannel_logout]. Since 2026.8, deactivating a user triggers back-channel logout and deletes the user's sessions [V S2]. |
| DPoP | ID-token key binding only (`bound_key` scope; code, device and refresh flows). Access tokens stay Bearer [V S6 providers/oauth2/key-binding]. See (02). |
| Certification | OpenID Certified since 2026.8: Basic, Implicit, Hybrid, Config and Form Post OP profiles, plus RP-Initiated, Front-Channel and Back-Channel logout [V S6 releases/2026/v2026.8]. |

## 6. authentik: provisioning, events and API

- **SCIM provider (outbound SCIM 2.0)** [V S6 providers/scim]:
  - **What is pushed:** users, groups and membership. Membership uses PATCH when the target supports it, otherwise PUT.
  - **Custom attributes:** a mapping returns an extension schema URN plus its object.
  - **Default group mapping:** sends only `displayName` [V-src S7 blueprints/system/providers-scim.yaml]. Group attributes need a custom group mapping, and group parents are not pushed by default [I].
  - **When:** on every create, update or delete of a user or group and on membership changes, plus a full sync every hour. Work runs in the worker in batches of 100.
  - **Retries:** HTTP 429/503 and failed requests raise a transient error. The task is retried up to `AUTHENTIK_WORKER__TASK_MAX_RETRIES` times (default 5) [V-src S7 lib/sync/outgoing/tasks.py, providers/scim/clients/base.py, clients/exceptions.py; V S6 install-config/configuration].
  - **Scope:** users bound to the backchannel application (no binding means all users), plus optional group filters.
  - **Arbitrary endpoint:** any reachable base URL with a static bearer token works. authentik reads `ServiceProviderConfig` (cached 1 h) to learn about filter, bulk and patch support. An evok-node SCIM endpoint is therefore possible, as long as authentik can reach the node [I].
  - **Not pushed:** password hashes and authenticators. They are not in the mapping output [I].
- **Events:** event actions include `login`, `login_failed`, `logout`, `user_write`, `password_set` and `model_created/updated/deleted` [V S6 sys-mgmt/events/event-actions].
  - Notification rules (filtered by policy) feed transports: local, email, generic **webhook** (POST JSON, with body and header mappings and a custom CA), Slack/Discord [V S6 sys-mgmt/events/transports].
- **SSF provider (Enterprise):** Security Event Tokens for MFA device added/removed, logout, session revoked and credential change. The receiver subscribes a stream [V S6 providers/ssf].
- **REST API `/api/v3/`:**
  - Users can be filtered with `last_updated__gt`, which allows incremental polling [V-src S7 core/api/users.py].
  - The user serializer returns `attributes`, groups and roles. It does **not** return the password or its hash; a hash can only be *written*, and only via blueprints [V-src S7].
  - The WebAuthn device API returns `pk, name, created_on, device_type, aaguid, user`. It does **not** return `credential_id` or `public_key` [V-src S7 stages/authenticator_webauthn/api/devices.py].
- **WebAuthn RP ID** is the request host without the port, and there is no setting to override it. It is stored per device [V-src S7 stages/authenticator_webauthn/utils.py, models.py].

## 7. authentik: outposts and HA

- **Outposts** (LDAP, RADIUS, proxy, RAC) talk to the core over the API and a WebSocket, using an auto-created service-account token. Config changes are pushed over the WebSocket [V S6 add-secure-apps/outposts].
- **LDAP bind and search modes** [V S6 providers/ldap]:
  - Direct bind runs the bind flow in the core.
  - **Cached bind** keeps the result in memory for the session duration. Revocations and password changes do not reach it.
  - **Cached search** holds all users and groups in memory.
  - So with the core down, cached modes keep answering for credentials already seen, while direct binds and new logins fail [I].
- The LDAP outpost returns custom user and group attributes as LDAP attributes [V S6 providers/ldap]. That is the likely path for the PINs that 2N Access Commander syncs over LDAP [I]. [GAP] Which attribute and format Access Commander expects for a PIN.
- **HA:** server and worker are stateless and can run as several instances; PostgreSQL provides HA, read replicas and connection poolers; active-passive is documented [V S6 install-config/high-availability]. There is no multi-master or edge replication of authentik itself [I].

## 8. Other IdPs (brief)

| IdP | Facts that matter here |
|---|---|
| **Keycloak 26.8.1** [V-src S11 git tags] | **Footprint:** Java/Quarkus. About 1250 MB RAM per pod, including realm caches and 10k sessions [V S9].<br>**Directory:** Organizations supported since 26.0 [V-src S11 release_notes 26_0_0]. Groups have attributes, and the User Attribute mapper can **aggregate group attributes** [V-src S11 UserAttributeMapper.java].<br>**Step-up:** native ACR→LoA mapping with a "Conditional – Level Of Authentication" step that has its own max age. Accepts `acr_values` and an essential `acr` in `claims` [V S11 server_admin acr-to-loa-mapping, authentication/flows].<br>**Protocols:** back-channel logout, device flow, client credentials [V S11 server_admin]. Standard token exchange since 26.2; passkeys and DPoP supported since 26.4 [V-src S11 release_notes].<br>**SCIM:** 26.8 makes the **inbound** SCIM API supported; there is no outbound push [V S10].<br>**Events:** event-listener SPI (logging and email built in), no webhook [V S11 events/login].<br>**Risk:** CVE-2026-97176 lets a lower-LoA SSO cookie produce a token without step-up. A third-party article dated Sep 2026 says no fix exists [V S12]. [GAP] Whether 26.8.1 fixes it.<br>**License:** Apache-2.0. |
| **Kanidm 1.11.2** | **Footprint:** Rust, about 64 KB RAM per entry. ARM needs aarch64 with neon_v8 [V S13 preparing_for_your_deployment].<br>**OAuth2/OIDC:** code and client-credentials grants, PKCE (S256 only), introspection, revocation, RFC 8693 token exchange, ES256 ID tokens [V S13 supported_features].<br>**Claim maps:** per client, claim → group → values [V S13 integrations/oauth2/custom_claims].<br>**Other:** passkeys and attested passkeys [V S13 accounts/account_policy]. Multi-master, eventually consistent replication [V S13 repl]. `unixd` caches users and credentials (optional TPM) for offline login, a precedent for (05) [V S13 integrations/pam_and_nsswitch]. SCIM is inbound only. Device flow and back-channel logout are not in the feature list [V S13].<br>**License:** MPL-2.0. |
| **Zitadel 4.20.0** | **Footprint:** Go plus PostgreSQL. About 512 MB for Zitadel; the database needs about 4 GB per core [V S14 self-hosting/manage/production].<br>**Roles:** project roles are granted per **organization**. The claim looks like `urn:zitadel:iam:org:project:{id}:roles: {role: {orgId: orgDomain}}`: a role with one fixed scope dimension (the org), not a free parameter [V S14 guides/integrate/retrieve-user-roles].<br>**Other:** SCIM 2.0 *server* (inbound), OpenID Certified, device authorization, passkeys [V S14 README].<br>**License:** AGPL-3.0 [V-src S14]. |
| **Authelia 4.39.28** | **Status:** the OIDC provider is still "beta" on its roadmap, but it is OpenID Certified and emits `amr` [V S15 roadmap].<br>**Policy levels:** `one_factor` / `two_factor` [V S15 security/access-control]. It has no user database of its own: users live in a file or in LDAP, for example LLDAP [I].<br>**Other:** arm64 binaries [V S15 artifact-signing].<br>**License:** Apache-2.0. |
| **Pocket ID 2.19.1** | **Model:** passkey-only OIDC provider, OpenID Certified [V S16 README].<br>**Features:** custom claims, **SCIM push**, back-channel logout, device flow, federated client credentials [V S16 CHANGELOG].<br>**License:** BSD-2 [V-src S16]. |
| **Rauthy 0.37.2** | **Footprint:** Rust, on embedded Hiqlite (Raft SQLite) or PostgreSQL. About 40 MB single instance, about 65 MB as an HA cluster [V S17 README].<br>**Features:** custom roles, groups and scopes; user attributes bound to scopes; back-channel logout; device flow; **SCIM v2 to downstream clients**; passkeys; event notifications by email, Matrix or Slack [V S17].<br>**License:** Apache-2.0. |

## 9. Comparison

`?` means not verified ([GAP]). The tags are in §1–§8.

| | authentik | Keycloak | Kanidm | Zitadel | Authelia | Pocket ID | Rauthy |
|---|---|---|---|---|---|---|---|
| Footprint | ≥2 CPU, 2 GB + PG | ~1.25 GB/pod | 64 KB/entry | ~0.5 GB + PG | ? | ? | ~40 MB |
| ARM64 | yes | ? | yes (neon_v8) | ? | yes | ? | ? |
| OIDC certified | yes (2026.8) | ? | ? | yes | yes | yes | ? |
| Claims from group attributes | yes (Python) | yes (aggregate mapper) | per-group values | ? | ? | custom claims | user attributes → scopes |
| acr / amr / step-up | fixed acr; amr; `max_age`, `prompt=login`; no `acr_values` | ACR→LoA, `acr_values`, `claims` | ? | ? | amr; 1F/2F policy | ? | ? |
| Passkeys | yes | yes | yes | yes | ? | only method | yes |
| SCIM out | **yes** | no (in) | no (in) | no (in) | no [I] | **yes** | **yes** |
| Events / webhooks | webhook; SSF (Ent.) | listener SPI | ? | ? | ? | ? | email/Matrix/Slack |
| Back-channel logout | yes (preview) | yes | not listed | ? | ? | yes | yes |
| Introspection | yes | yes [I] | yes | ? | ? | ? | ? |
| Client credentials | yes, plus foreign JWT | yes | yes | ? | ? | federated | ? |
| Device flow | yes | yes | not listed | yes | ? | yes | yes |
| License | MIT + Ent. | Apache-2.0 | MPL-2.0 | AGPL-3.0 | Apache-2.0 | BSD-2 | Apache-2.0 |

## 10. Node libraries (local IdP and replica)

- **`oidc-provider` 9.13.3** (29 Oct 2026):
  - **Package:** MIT. Dependencies are only `jose`, `koa` and `debug`; unpacked size 552 kB [V S19; V-src S18 package.json]. One maintainer; only v9.x is supported [V S18 README].
  - **Certified profiles:** Basic, Implicit, Hybrid, Config, Form Post, 3rd-Party-Init; Back-Channel and RP-Initiated Logout; FAPI 1.0, FAPI CIBA, FAPI 2.0 [V S18 README].
  - **Implements:** DCR, RP-initiated and back-channel logout, revocation, PKCE, introspection (also as JWT), device flow, mTLS, resource indicators, JAR, PAR, RAR, **DPoP**, JARM, CIBA, the `iss` response parameter. Access tokens can be opaque or JWT [V S18 README].
  - **Config:** `features.clientCredentials`, `features.claimsParameter`, `acrValues` (default `[]`). Default claims include `acr`, `auth_time` and `sid` [V S18 docs/README].
  - **Not implemented:** RFC 8693 token exchange and front-channel logout; neither is in the spec list [V S18 README].
  - **Login UI:** the app supplies the login and consent screens ("interactions"); `devInteractions` is for development only [I].
  - **Storage adapter:** one adapter instance per model, with `upsert(id, payload, expiresIn)`, `find`, `findByUserCode`, `findByUid`, `consume`, `destroy` and `revokeByGrantId`. The in-memory default is for development only. The `ReplayDetection` upsert should be an atomic insert-if-absent [V-src S18 example/my_adapter.js; V S18 docs/README §adapter].
  - **Fit with KV:** a KV driver works if it offers TTL, lookup by `userCode` and `uid`, and fan-out by `grantId`. Going through driver messaging adds a hop on every request [I].
- **`openid-client` 6.8.8:** MIT; dependencies `jose` and `oauth4webapi` [V S19]. The replica's RP library towards authentik [I].
- **`jose` 6.2.14:** MIT [V S19]. JWT/JWS/JWE/JWK and remote JWKS [I].
- **`@simplewebauthn/server` 14.0.3:** MIT; dependencies `@peculiar/*` and `tiny-cbor` [V S19].
- **Hashing in Node 24:**
  - `crypto.scrypt` is built in [I].
  - **`crypto.argon2()` / `argon2Sync()` were added in v24.7.0.** They carry no stability marker of their own (the module is Stable) [V S20 crypto.md]. They throw `ERR_CRYPTO_ARGON2_NOT_SUPPORTED` when the linked OpenSSL has no Argon2 [V S20 errors.md; V-src S20 src/crypto/crypto_argon2.cc `#if OPENSSL_WITH_ARGON2`]. [GAP] Whether the Node build on Unipi (Debian package or official binary) has it.
  - Fallbacks: `argon2` 0.45.1 (node-gyp) and `@node-rs/argon2` 2.2.2 (prebuilt) [V S19].
  - On 1 GB of RAM the Argon2 memory cost has to be chosen with care, for example 64 MiB per hash, which limits parallel logins [I].
- **A minimal own token service would need** [I]:
  - signing keys, a JWKS and key rotation
  - JWTs with `aud`, `exp`, `auth_time`, `amr`/`acr`
  - refresh tokens with rotation and reuse detection, plus a revocation list
  - a session store
  - PIN/password verification with throttling and lockout
  - WebAuthn ceremonies
  - for browser or third-party clients: discovery, authorization code + PKCE, state/nonce handling, and audit events

  `oidc-provider` covers the protocol part; its cost is OIDC-level complexity.

## 11. Fit with the two situations

| Need (brief) | authentik facts | Fit |
|---|---|---|
| Authoritative users and roles | Users, groups (multiple parents), entitlements, all with attributes; admin API plus SCIM push (§2, §6) | Clean. SCIM carries users, groups, membership and attributes. Entitlements are not SCIM objects, so they need API polling [I]. |
| Parametric roles | Custom claim from entitlement or group attributes (§3) | Clean in the token. The replica can also compute roles from synced attributes [I]. |
| Replica validates sessions offline | JWT access and ID tokens verifiable with a cached JWKS (§5) | Clean for signature and expiry. Revocation is not visible offline [I]. See (05). |
| Replica refreshes; node-only session offline | authentik cannot issue node-limited tokens offline | The replica issues its own node-scoped token [I]. See (02). |
| Several nodes refresh one session | Rotation by default; reusing a revoked refresh token gives `invalid_grant` plus a suspicious event (§5) | Conflict when two nodes refresh the same session [I]. Fixes: one refresher per client session, or `refresh_token_threshold` > 0, which keeps the token until it is near expiry [V-src S7]. |
| Offline login by PIN | No PIN concept; password hashes are not readable by API or SCIM (§4, §6) | The replica must hold its own PIN verifier [I]. If 2N needs the PIN over LDAP, authentik has to hold it in a readable form, probably in clear [I][GAP]. |
| Offline login by biometry/passkey | RP ID = authentik's host; no override; `credential_id` and public key not exposed (§6). WebAuthn: the RP ID must equal the origin's effective domain or be a registrable suffix of it, and https is required (except localhost) [V S21 §Terminology]. Related Origin Requests (`/.well-known/webauthn`) let other origins use one RP ID [V S21 §sctn-related-origins]. | **Does not map.** A replica on another host cannot use authentik passkeys, and it could not verify them anyway without the public key [I]. Node passkeys must be enrolled with the replica. See (06). |
| Several auth levels | Fixed `acr`, coarse `amr`, `acr_values` ignored (§4) | Auth levels are computed by evok-node [I]. See (03). |
| Revocation push to replica | Back-channel logout (node must be reachable over HTTPS), logout webhooks, SSF (Ent.), polling `last_updated__gt` (§5, §6) | Usable as hints. The replica still needs short token lifetimes [I]. See (05). |
| IdP down | Outposts keep only cached modes (§7) | The replica carries the node [I]. |

## 12. Proposals for 13a (not binding)

- **P1 — authentik as authority only.** Use it for users, groups and role assignment, and as the online OIDC login. Keep auth levels, PIN and node passkeys in the evok-node replica.
- **P2 — Roles as group attributes first.** A group (for example "Flat 3 tenants") carries `evok_roles: [{role, flat}]`. SCIM can push groups, and a scope mapping can emit the same claim. Application entitlements are cleaner per app, but they need API polling for the replica.
- **P3 — Replica sync = an evok-node SCIM endpoint plus polling.** SCIM push on change and hourly full sync. REST polling for what SCIM lacks (entitlements, sessions). A logout/`model_*` webhook only as a "sync now" hint. Keep the replica protocol IdP-neutral, because Keycloak and Kanidm have no SCIM out.
- **P4 — One refresher per authentik session.** Either the shell app or a single node refreshes with authentik; or set `refresh_token_threshold`. Nodes then issue their own short node tokens. See (02).
- **P5 — Enrol local credentials online.** PIN hashes and node passkeys are enrolled while authentik has confirmed the user, are stored by the replica, and are never pushed back to authentik.
- **P6 — Local IdP library choice depends on clients.** Use `oidc-provider` only if third-party OIDC clients must log in to a node. Otherwise build a small token service on `jose` + `@simplewebauthn/server` + `crypto.argon2` (scrypt as fallback). Decide after (02) and (06).
- **P7 — Settle the 2N PIN path early.** Find out how Access Commander reads PINs over LDAP (attribute name and format). It decides whether the site IdP must hold PINs in clear.

## 13. Sources

- S1 — authentik GitHub releases: https://github.com/goauthentik/authentik/releases
- S2 — authentik release notes 2026.8: https://docs.goauthentik.io/releases/2026.8
- S3 — authentik 2026.5 blog: https://goauthentik.io/blog/2026-05-22-authentik-version-2026-5/
- S4 — "We removed Redis" (authentik blog): https://goauthentik.io/blog/2025-11-13-we-removed-redis/
- S5 — authentik Docker Compose installation: https://docs.goauthentik.io/install-config/install/docker-compose/
- S6 — authentik docs source at tag version/2026.8.5, `website/docs/` (paths in tags): https://github.com/goauthentik/authentik/tree/version/2026.8.5/website/docs
- S7 — authentik source at tag version/2026.8.5 (paths in tags): https://github.com/goauthentik/authentik/tree/version/2026.8.5
- S8 — authentik 2026.8 blog: https://goauthentik.io/blog/2026-09-01-authentik-version-2026-8/
- S9 — Keycloak, Concepts for sizing CPU and memory: https://www.keycloak.org/high-availability/single-cluster/concepts-memory-and-cpu-sizing
- S10 — Keycloak 26.8.0 release notes: https://www.keycloak.org/docs/26.8.0/release_notes/
- S11 — Keycloak repository, main (`docs/documentation/server_admin`, `docs/documentation/release_notes`, `services/…/oidc/mappers`; tags 26.8.0, 26.8.1): https://github.com/keycloak/keycloak
- S12 — Skycloak, CVE-2026-97176 Keycloak step-up bypass (third party): https://skycloak.io/blog/cve-2026-97176-keycloak-loa-acr-cookie-bypass/
- S13 — Kanidm book source (`book/src`; tag v1.11.2): https://github.com/kanidm/kanidm/tree/master/book/src
- S14 — Zitadel repository (README, `apps/docs/content`; tag v4.20.0): https://github.com/zitadel/zitadel
- S15 — Authelia repository docs (`docs/content`; tag v4.39.28): https://github.com/authelia/authelia
- S16 — Pocket ID repository (README, CHANGELOG; tag v2.19.1): https://github.com/pocket-id/pocket-id
- S17 — Rauthy README (tag v0.37.2): https://github.com/sebadob/rauthy
- S18 — node-oidc-provider (README, docs/README.md, example/my_adapter.js): https://github.com/panva/node-oidc-provider
- S19 — npm registry metadata (oidc-provider, openid-client, jose, @simplewebauthn/server, argon2, @node-rs/argon2): https://registry.npmjs.org/
- S20 — Node.js v24.x `doc/api/crypto.md`, `doc/api/errors.md`, `src/crypto/crypto_argon2.cc`: https://github.com/nodejs/node/tree/v24.x
- S21 — W3C Web Authentication Level 3, spec source `index.bs` (§Terminology RP ID scope; §sctn-related-origins): https://github.com/w3c/webauthn/blob/main/index.bs
