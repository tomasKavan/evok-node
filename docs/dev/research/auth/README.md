# Auth research

**Research, not design.** Facts for 13a — auth and ACL (M3.6). Evidence tags as in [`../README.md`](../README.md): [V], [V-src], [I], [GAP]. Numbers called *measured* or *local test* come from a test run for the note and named in its sources; they are not published figures.

Compiled 2026-10-30.

## 1. Input from Tomas (2026-10-30)

- Two situations: a **local IdP** inside evok-node, and a **site IdP with a replica** inside each evok-node. The site IdP is external — authentik first, others (Keycloak …) kept open — never an evok-node.
- **Site** = one or more nodes sharing one IdP. **Node** = one evok-node using a local or the site IdP.
- **Replica:** syncs with the IdP, caches sessions, validates and refreshes them, drives every auth workflow on its node. IdP unreachable: still validates; refresh valid for this node only; one-time local login by biometry or PIN.
- Auth is optional per api (plugins); an api with its own protocol auth (Matter) keeps it.
- Role-based; parametric roles preferred (`tenant`, parameter `flat 3`), plain roles acceptable.
- A session can have several auth levels; a resource may require one (unlock → biometry or PIN).
- WS api: `onConnection` validates the session and decodes user and roles (roles may come from the replica); `onRequest` authorizes each message, may filter introspection, in memory and fast.
- Direction to confirm: IdP/replica as a driver (KV or own DB); management over the WS API with UI in the Inspector; auth workflows over a dedicated HTTP(S) api.
- Client app keeps the session and uses biometry where possible; a shell app hosts the web apps and connects to many sites and nodes.

Earlier identity input (door locks, 2N, Matter): research/matter/08 Input and §6 P11–P16.

## 2. Files

| File | Contents |
|---|---|
| [`01-identity-providers.md`](01-identity-providers.md) | authentik in depth (footprint, directory, claims, stages, `acr`/`amr`, endpoints, SCIM, API, outposts); Keycloak, Kanidm, Zitadel, Authelia, Pocket ID, Rauthy; comparison; Node libraries for a local IdP (`oidc-provider`, `jose`, `openid-client`, `@simplewebauthn/server`, `crypto.argon2`); fit with the two situations |
| [`02-sessions-and-tokens.md`](02-sessions-and-tokens.md) | JWT, PASETO, Biscuit, macaroons, CWT (measured size and speed); refresh rotation (RFC 9700), DPoP, mTLS; revocation, back-channel logout, SSF/CAEP; node-limited tokens (audience, token exchange, attenuation, node-signed); auth over WebSocket and what HA, graphql-ws, Socket.IO, MQTT 5 do; PLC-to-PLC credentials; clocks |
| [`03-auth-levels.md`](03-auth-levels.md) | NIST SP 800-63B-4 AAL, eIDAS; `acr`/`amr`/`auth_time`, RFC 8176, RFC 9470 step-up; what WebAuthn UV and phone biometry tell a server; session elevation vs per-operation proof; Google, Alexa, Apple HAP, Home Assistant, Loxone for locks and garage doors; the two uses of a PIN |
| [`04-authorization.md`](04-authorization.md) | RBAC, parametric roles, role assignment at a scope (Kubernetes, Azure, GCP), ReBAC (OpenFGA), Cedar; one rule in four forms; in-process engines and a local benchmark; per-session tables; roles in token vs replica; Matter privileges as a vocabulary; permission models of home-automation products; scope candidates in evok-node |
| [`05-replica-and-offline.md`](05-replica-and-offline.md) | SCIM receiver minimum; authentik SCIM push, LDAP outpost, REST polling, webhooks; Keycloak has no SCIM out; offline precedents (SSSD, Windows, Kanidm, Entra, Greengrass, IoT Edge, Duo); what a replica can hold per factor; PIN protection with and without TPM; revocation while offline |
| [`06-client-apps.md`](06-client-apps.md) | RFC 8252 and RFC 10017; Secure Enclave and Keystore keys, prompt-only vs crypto-bound, attestation; step-up by signed node challenge; Capacitor, Tauri, React Native, Flutter; WebAuthn on a LAN (no IP RP IDs); local TLS options; many sites and nodes; shell ↔ web app hand-off (HA, CVE-2026-44698); wall panels; enrolment |
| [`07-way-forward.md`](07-way-forward.md) | The research read against Tomas's input and today's design: proposed shape, fit with the design, decisions for Tomas, next steps. Proposals only |

## 3. Where auth touches evok-node today

In these notes, design documents are written `design 06 §5a` wherever a bare number could mean a note in this folder.

| Where | What |
|---|---|
| 13 §5 | The gate: every message to a driver has passed an api's auth and ACL. `actor` `{ realm, id?, name? }` is always overwritten by the api; `proof` on a method makes the api get proof first |
| 13 §2 | WS extensions: `onConnection` (auth, language), `onRequest` (ACL, localization) |
| 05a §3.1, §3.1a | `proof?: true` in `MethodType`; the `actor` annotation and `Values.actor()` |
| M3.8 (WS API) | hello carries `evokNodeVersion` and `lang`; ACL subjects, resources, actions; PLC-to-PLC auth belongs to this api |
| M3.11 (Home API), M3.9 (Inspector) | auth and ACL as WS extensions; write and test actions gated |
| design 06 §5a | sensitive keys in a second 0600 file; no encryption at rest |
| design 12a §4b, 05a §3.8b, 07 §4.1 | PLC-to-PLC credentials deferred to M3.6 |
| 12a §6 | hierarchy level → room → group — a role-scope candidate |
| 12c-09 §1.2 | `DoorLock.unlock` is `proof`; what proof asks → M3.6 |
| 12c-07 §6 | `open` of a `garageDoor`, `gate` or `door` needs the same proof; `Closure` is one DeviceType for every kind |
| 16a, research/matter/08 P15 | Matter bridge: own auth (fabrics); one bridge vs one per flat |
| M3.6a (12e) | 2N users and PINs come from the IdP through Access Commander |
