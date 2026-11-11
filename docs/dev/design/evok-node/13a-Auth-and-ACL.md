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
- **Role-based.** Roles are assigned to users and groups. Parametric roles are preferred — role `tenant`, parameter `flat 3`. Plain roles are acceptable if parameters do not fit.
- **Privileges come from the types.** `view < operate < manage < administer`, and what each operation needs, are the types' access marks (05a §3.1b). 13a holds who has which privilege where; it never redefines a mark.
- **Levels.** A session can have several authentication levels; a resource can require one. `DoorLock.unlock` needs biometry or a PIN (12c-09 §1.2).

**Replica**

| | IdP reachable | IdP unreachable |
|---|---|---|
| validate a session | yes | yes |
| refresh a session | yes | yes, valid on this node only — client apps must work with such a limited session |
| log a user in | through the IdP | a one-time local session, by biometry or PIN only |

**In a WS api** (WS API 15, Home API 18)

| Extension | Called | Does |
|---|---|---|
| `onConnection` | when a client connects | validates the session — timeout, refresh; decodes the user and their roles. Roles may come from the replica, not from the client's token |
| `onRequest` | at every message | authorizes the request; may filter introspection. In memory only — it must be very fast |

**Implementation direction** — to be confirmed:

- The IdP and the replica: a special driver, storing in KV (06) or its own database.
- Not wired into an api directly — only through the extensions.
- Management (users, roles, sessions …) through the WS API, with a UI in the Inspector (16, 17).
- Auth workflows (sign-in, password change …) through a dedicated HTTP(S) api.

**Covers**

- Users, groups, roles and role parameters — what a parameter points to (12a §6 hierarchy?).
- Sessions: format, lifetime, refresh, revocation; node-limited sessions.
- Levels: names, how each is reached, step-up within a session; what `proof` asks of a caller (13 §5).
- `actor` filled from the session, realm `idp` (13 §5).
- The replica: sync, cache, offline rules, when it calls the IdP.
- Third-party sign-in (SSO).
- PLC-to-PLC credentials: 12a §4b, 05a §3.8b, 07 §4.1.
- Access closures and `DoorLock`: 12c-07 §6, 12c-09 §1.2; the 2N user map (M3.6a, 12e).
- What a client app and the shell app must do (13b).
- Secrets at rest (06 §5a).

**Inputs:** research/auth · 13 §2, §5 · 15 · 18 · 06 §5a · 12a §4b, §6 · 05a §3.8b · 07 §4.1 · 12c-07 §6 · 12c-09 §1.2 · research/matter/08 §6

**Open:** the decisions listed in research/auth (way forward).
