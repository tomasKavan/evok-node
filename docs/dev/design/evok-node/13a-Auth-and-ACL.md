# 13a — Auth and ACL

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** who the caller is, how sure we are of it, and what they may do — for every api that binds to it (13 §5). A library and a driver, not an api.

**Structure**

| Term | Means |
|---|---|
| **Site** | one node, or a cluster of nodes, using the same identity provider |
| **Node** | one evok-node, configured to use a local identity provider or the site's |
| **Identity provider (IdP)** | the authoritative user database and role assignment; session management; optionally third-party sign-in (SSO) |
| **IdP replica** | on a node using the site IdP: syncs with it, caches user sessions, validates and refreshes them. Drives every auth workflow on its node and decides when it needs the IdP |
| **Client app** | web, desktop or mobile UI where a user identifies themselves and talks to node apis. Keeps the session; uses biometry where it can |
| **Shell app** | the mobile (later desktop) app hosting the web apps (13b). Mainly handles sessions; connects to several sites and several nodes per site |

Two situations:

```
1. Local IdP                          2. Site IdP with a local replica

   client app ──► node [IdP]             client app ──► node A [replica] ──sync──► site IdP
                                          client app ──► node B [replica] ──sync──┘
```

**Imperatives**

- **Optional per api.** An api binds to it through plugins — WS extensions (13 §2) for apis on `ws-kit`. An api whose protocol has its own auth model keeps it (Matter fabrics, 16a); delivering a secured service is that api's own job (13 §5).
- **Role-based, RBAC only.** A role is an IdP group, and its grants are an attribute of that group; a user holds the roles of the groups they are in, parents included. No rule on device values (no ABAC).
- **Privileges come from the types.** `view < operate < manage < administer`, and what each operation needs, are the types' access marks (05a §3.1b). 13a holds who has which privilege where; it never redefines a mark.
- **Levels.** A session can have several authentication levels; a resource can require one. `DoorLock.unlock` needs biometry or a PIN (12c-09 §1.2).

**Roles, grants and scopes**

```ts
interface Grant { readonly privilege: Privilege; readonly scope: Scope }     // Privilege: 05a §3.1b
type Scope = 'site' | `node:${NodeId}` | `zone:${ZoneId}` | `device:${NodeId}/${Address}`

// authentik group "resident":                         { "evok": { "grants": [{ "privilege": "operate", "scope": "zone:common" }] } }
// authentik group "tenant:flat3" (parent "resident"): { "evok": { "grants": [{ "privilege": "manage",  "scope": "zone:flat3"  }] } }
```

| Scope | Covers, on a node |
|---|---|
| `site` | everything |
| `node:<id>` | everything, on the node with that id |
| `zone:<id>` | home devices in rooms of that zone or of a zone below it (12a §6) |
| `device:<node>/<address>` | that one address, on that node |

- **Fixed roles**, no parameters: one role per flat (`tenant:flat3`); what roles share goes to a parent group (`resident`).
- **Grants only add up.** On an address the highest privilege wins; there is no deny. A boundary is drawn in the hierarchy (12a §6), an exception is a `device:` grant.
- **All grants live in the IdP**, `device:` ones too. With a local IdP, `driver-auth` holds the same data.
- **Management is per home driver.** A grant reaching `<home>:manage` manages that whole driver (12a §5). A flat gets its own manager by having its own home driver — one per PLC, one per top zone in practice — and the others import its devices as remotes (12a §4b).
- **The grants attribute**, on any IdP group — a group that has it is a role:

```jsonc
{ "evok": { "v": 1, "grants": [
  { "privilege": "manage",  "scope": "zone:flat3" },
  { "privilege": "operate", "scope": "device:house/home:device.local.20" }
] } }
```

- **Inheritance is the replica's:** it adds the grants of a group's parents itself, never through the IdP's attribute merge.
- **Checked by each node at every sync:**

| Check | On failure |
|---|---|
| shape — `privilege` one of the four, `scope` matching its kind's pattern (03a) | that grant is skipped and reported; the group's other grants apply |
| unknown `v` | the whole attribute is skipped and reported |
| `node:` or `device:` naming another node | normal — it does not apply here; not reported |
| `device:` naming this node with an address it does not have | applied (it may appear later); a warning |
| `zone:` with an id no room here uses | applied; an info — maybe a typo |

  A sync never fails as a whole; a grant that doesn't parse grants nothing. Issues are `Issue[]` (03a) on a `driver-auth` reading, shown in the Inspector.
- **`nodeId`** is in `driver-auth`'s config, unique in the site; `node:` and `device:` name it.
- **`proof` is binding:** an api that cannot get it refuses the call (13 §5).

**The ACL extension**

- A WS extension (15). It sees exactly what the api's clients see and decides only on that: `zone:` resolves through each relayed home driver's `manage.listHierarchy` — an api that doesn't relay one resolves no zone.
- One copy of each home driver's hierarchy, refreshed on its `manage.hierarchyRev` (12a §6). A session keeps only its grants. Checked per request, per listed device (`afterIntrospect`) and per pushed value (`onPush`):

```ts
privilege(session, address) = max(g.privilege for g in session.grants if covers(g.scope, address))
// zone: tail → group → room → zone → parent → … contains the grant's zone
allowed = privilege(session, address) >= markOrDefault(element)    // 05a §3.1b
       && (!element.access?.proof || proofOk)
```

- One link to `driver-auth`, private to the extension (15) and shared by every session: changes of grants and sessions.
- On loss: the hierarchy copy and the sessions' grants stay as they were; a new session resolves `zone:` to nothing until the hierarchy arrives.

**PLC to PLC**

- **A node is a principal**, `node:<nodeId>`, with grants from its groups like a user — `operate` on the relay a peer drives, `view` on what a home driver imports (12a §4b, 07 §4.1).
- **Credentials:** an Ed25519 key pair, made by `driver-auth` at install. The private key is a sensitive secret (06 §5a) and never leaves the node; the public key is shown in the Inspector, as text and QR. No passwords, no tokens from the IdP — links work with the IdP down.
- **Where a peer is known:**

| Mode | The peer |
|---|---|
| site IdP | a service account `node:<id>` in the IdP, attribute `{ "evok": { "nodeKey": "ed25519:…" } }`; synced by the replica like a user. **Only from the IdP** — no local pairing |
| local IdP (`driver-auth` is the master) | a record in `driver-auth`, made by pairing in the Inspector: a code or QR from the peer, approved on this node |

- **Connecting** — both sides prove themselves, no clock needed between them; TLS pinned to the node key:

```
garden ──WS──► house
house  → hello   { node: 'house', nonce: n1 }
garden → auth    { node: 'garden', nonce: n2, sig: sign(garden.key, n1 ‖ 'house' ‖ n2) }
house  : verify with garden's key from the directory → principal node:garden → its grants
house  → auth_ok { sig: sign(house.key, n2 ‖ 'garden') }
```

  After `auth_ok` the peer is a session like any user's: the ACL extension, access marks and `proof` apply unchanged.
- **Rotation:** a new key is published beside the old one, the old one removed later. **Revocation:** the account disabled in the IdP (at the next sync), or the node-local "disabled" flag (at once).
- **A call relayed for a user** — Petr unlocks a `DoorLock` imported from `garden`: `house` calls `garden` as `node:house`. **Delegation:** `garden` keeps the `actor` a peer allowed to delegate passes on, records `act: node:house`, and trusts that peer's proof. This changes 13 §5's "the api always overwrites `actor`" when 13a is designed.

**Replica**

| | IdP reachable | IdP unreachable |
|---|---|---|
| validate a session | yes | yes |
| refresh a session | yes | yes, valid on this node only — client apps must work with such a limited session |
| log a user in | through the IdP | a one-time local session, by biometry or PIN only |

**In a WS api** (WS API 15, Home API 18)

| Extension | Called | Does |
|---|---|---|
| `onConnection` | when a client connects | validates the session — timeout, refresh; decodes the user and their grants. Grants come from the replica, not from the client's token |
| `onRequest` | at every message | authorizes the request (above); filters introspection and pushes. In memory only — it must be very fast |

**Implementation direction** — to be confirmed:

- The IdP and the replica: a special driver, storing in KV (06) or its own database.
- Not wired into an api directly — only through the extensions.
- Management (users, roles, sessions …) through the WS API, with a UI in the Inspector (16, 17).
- Auth workflows (sign-in, password change …) through a dedicated HTTP(S) api.

**Covers**

- Users and groups.
- Sessions: format, lifetime, refresh, revocation; node-limited sessions.
- Levels: names, how each is reached, step-up within a session; what `proof` asks of a caller (13 §5).
- `actor` filled from the session, realm `idp` (13 §5).
- The replica: sync, cache, offline rules, when it calls the IdP.
- Third-party sign-in (SSO).
- PLC to PLC (above), for 12a §4b, 05a §3.8b, 07 §4.1: the hello's exact messages, which peers may delegate, how `act` reaches the driver.
- Access closures and `DoorLock`: 12c-07 §6, 12c-09 §1.2; the 2N user map (M3.6a, 12e).
- What a client app and the shell app must do (13b).
- Secrets at rest (06 §5a).

**Inputs:** research/auth · 13 §2, §5 · 15 · 18 · 06 §5a · 12a §4b, §6 · 05a §3.8b · 07 §4.1 · 12c-07 §6 · 12c-09 §1.2 · research/matter/08 §6

**Open:** the decisions listed in research/auth (way forward).
