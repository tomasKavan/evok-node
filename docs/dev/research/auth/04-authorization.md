# 04 — Authorization

**Research, not design.** Authorization models (RBAC, parametric roles, ReBAC, ABAC), in-process engines for Node 24, fast per-message checks, where roles live, an action vocabulary taken from Matter, home-automation permission models, and what a role scope could point to in evok-node. Feeds 13a (M3.6).

## 1. Models

### 1.1. RBAC (NIST, ANSI INCITS 359-2004)

| Component | What it defines | Note for evok-node |
|---|---|---|
| Core RBAC | users, roles, operations, objects, permissions; `UA ⊆ USERS × ROLES`, `PA ⊆ PERMS × ROLES`; a session maps a user to an *activated subset* of roles [V S1 §5.1] | Role activation per session fits "several auth levels per session": a role could be usable only at a given level [I] |
| Hierarchical RBAC | general (any partial order) or limited (tree) role hierarchies [V S1 §5.2] | e.g. `admin ≥ tenant ≥ guest` |
| SSD / DSD | separation of duty on assignment (static) or on activation in a session (dynamic) [V S1 §5.3] | not needed for a house [I] |

The standard has **no scope or parameter** on a role [V S1]: "tenant of flat 3" means one role per flat (`tenant-flat3` …), so the number of roles grows with the number of flats [I].

### 1.2. Parametric roles and role assignment at a scope

- **Academic names:** *parameterised roles* in OASIS — a role plus a tuple of parameters, e.g. `treating_doctor(x, y)`, parameters bound when the role is activated [V S2 §4.2, §5]; *Parameterized RBAC* (PRBAC) [V S3]; Xu & Stoller: "users and permissions have attributes that are implicit parameters of roles" [V S4].
- **Industry pattern:** the role definition has no scope; the **assignment** is `(subject, role, scope)`, and the scope is a node in a resource hierarchy.

| System | Role definition | Assignment at scope | Inheritance down the tree | Deny / exception |
|---|---|---|---|---|
| Kubernetes | ClusterRole (cluster-wide) | RoleBinding in a namespace may reference a ClusterRole: "lets you define a set of common roles across your cluster, then reuse them within multiple namespaces" [V S5] | none (flat namespaces) | none: "Permissions are purely additive (there are no "deny" rules)" [V S5]; `resourceNames` narrows to named objects [V S5] |
| Azure RBAC | role definition | assigned at management group / subscription / resource group / resource; scope is a path string `/subscriptions/{id}/resourceGroups/{rg}/…` [V S6] | "Lower levels inherit role permissions from higher levels" [V S6] | deny assignments block access even if a role grants it, but "You can't directly create your own deny assignments" (Azure-managed only); can exclude child scopes [V S7] |
| Google Cloud IAM | role | allow policy at organization / folder / project / resource [V S8] | effective policy = union of the resource's policy and inherited ones [V S8] | separate deny policies exist [V S8] |
| AWS IAM | policy with variables | no scope object; variables are substituted from the request at evaluation [V S9], e.g. `"aws:ResourceTag/Owner": "${aws:username}"` (ABAC with tags) [V S10] | n/a | (not checked here) |

### 1.3. ReBAC (Zanzibar, OpenFGA, SpiceDB)

- Zanzibar: Google's global service that stores and evaluates ACLs with "a uniform data model and configuration language"; p95 latency < 10 ms at millions of checks/s [V S11]. It is a **networked service**, not a library.
- OpenFGA (Zanzibar-style): relations on types; `X from Y` follows a relation to a related object (e.g. editors of a parent folder are editors of the document) [V S12, S13]; `but not` is exclusion [V S12]; ListObjects returns all objects a user has a relation with [V S14].
- SpiceDB: same idea, `permission read = reader + parent_folder->read`, exclusion `-` [V S16].
- Fit: a home hierarchy (site → level → room → group → device) is exactly a parent chain; a parametric role is a relation tuple `user:alice tenant flat:3` [I].

### 1.4. ABAC / policy language (Cedar)

- Decision: any satisfied `forbid` → Deny; else any satisfied `permit` → Allow; else Deny (default deny, forbid overrides permit) [V S18].
- `resource in X` matches anything in the hierarchy of `X` [V S19]; conditions via `when` / `unless`, e.g. `forbid(principal, action, resource) unless { context.authentication.usedMFA };` [V S19] — the same mechanism could require an auth level (03).
- **Policy templates** with slots `?principal`, `?resource`; each *template-linked policy* is one role assignment (user × resource group) [V S20] — this is a parametric role.

### 1.5. One rule in four forms

Rule: *a tenant of flat 3 may operate devices in rooms of flat 3; the boiler room only admins.* (a) and (b) were run with the libraries and gave the expected decisions for 20 000 random requests; (c) passed `@openfga/syntax-transformer` validation (not evaluated) [I, local test §2.2].

**(a) Casbin, RBAC with domains** — domain = flat; the api must resolve the device's flat before the check [I].
```ini
[request_definition]
r = sub, dom, obj, act
[policy_definition]
p = sub, dom, obj, act
[role_definition]
g = _, _, _
[policy_effect]
e = some(where (p.eft == allow))
[matchers]
m = g(r.sub, p.sub, r.dom) && keyMatch(r.dom, p.dom) && keyMatch(r.obj, p.obj) && (r.act == p.act || p.act == "*")
# policy:
# p, tenant, flat*, *, operate      p, tenant, flat*, *, read      p, admin, *, *, *
# g, alice, tenant, flat3           g, tomas, admin, *   ("*" needs addNamedDomainMatchingFunc('g', keyMatch))
```
Request `enforce('alice', 'flat3', 'home:flat3/kitchen/light1', 'operate')`; boiler devices have domain `basement`, which no tenant rule matches.

**(b) Cedar**
```cedar
// template = parametric role tenant(?resource); link: ?principal=User::"alice", ?resource=Flat::"flat3"
permit (principal == ?principal, action in [Action::"read", Action::"operate"], resource in ?resource);
permit (principal in Group::"admins", action, resource);
forbid (principal, action, resource in Room::"boiler") unless { principal in Group::"admins" };
```
Entities: `Device::"…light1"` → parent `Room::"flat3-kitchen"` → parent `Flat::"flat3"`.

**(c) OpenFGA**
```
model
  schema 1.1
type user
type site
  relations
    define admin: [user]
type flat
  relations
    define site: [site]
    define tenant: [user]
    define operator: tenant or admin from site
type room
  relations
    define flat: [flat]
    define site: [site]
    define operator: operator from flat or admin from site
type device
  relations
    define room: [room]
    define blocked: [user]
    define can_view: operator from room
    define can_operate: operator from room but not blocked
```
Tuples `(user, relation, object)`: `(user:alice, tenant, flat:3)`, `(site:home, site, flat:3)`, `(flat:3, flat, room:f3-kitchen)`, `(room:f3-kitchen, room, device:f3-light1)`, `(site:home, site, room:boiler)` (no flat → only `admin from site`), `(user:tomas, admin, site:home)`.

**(d) Plain table** — role definitions `(role) → privileges`, assignments `(subject, role, scope)`; scope covers its subtree [I].

| Role | Privileges | | Subject | Role | Scope |
|---|---|---|---|---|---|
| tenant | view, operate | | alice | tenant | `home:flat3` |
| admin | view, operate, manage, administer | | group:admins | admin | `site` |

The boiler room needs no extra rule: it is not under any flat [I]. An exception is needed only when the hierarchy does not follow the permission boundary (§7).

## 2. In-process engines for Node 24

### 2.1. Comparison

| Engine | Model fit | In-process | Eval speed | Size | Maintenance (npm latest) | License |
|---|---|---|---|---|---|---|
| Casbin (`casbin`) | RBAC with domains `g = _, _, _`, `keyMatch` on the domain [V S23]; on object paths too in my test [I]; `enforceSync`, `CachedEnforcer`, `getImplicitPermissionsForUser` [V-src S25] | yes, pure JS | Go impl.: 0.033 ms/op RBAC with domains (6 rules), 0.164 ms/op RBAC 1 100 rules, i7-6700HQ [V S24]; no Node numbers published [V S24]; Node: 6.7 µs [I, §2.2] | 510 kB unpacked [V S25] | 5.51.1, 2026-06-25 [V S25] | Apache-2.0 |
| Cedar (`@cedar-policy/cedar-wasm`) | RBAC + ABAC + hierarchy + templates + forbid [V S18–S20]; schema `validate`, `isAuthorizedPartial`, `preparsePolicySet` + `statefulIsAuthorized` [V-src S22] | yes, WASM | Rust: median 4–11 µs, p99 < 20 µs (EC2 m5.4xlarge) [V S21 §5.2]; WASM from Node: 93 µs, because all entities are passed as JSON on each call [I, §2.2; V-src S22 for the API] | 4.4 MB `.wasm` per target, 13.5 MB package (3 targets) [V-src S22] | 4.14.0, 2026-10-19 [V S22] | Apache-2.0 |
| CASL (`@casl/ability`) | actions × subjects × conditions; `can`/`cannot`; "isomorphic", rules serializable to UI, core "6KB mingzipped" [V S26] | yes, pure JS (browser too) | 0.41 µs [I, §2.2] | 208 kB unpacked [V S27] | 7.1.0, 2026-10-28 [V S27] | MIT |
| OPA / Rego (`@open-policy-agent/opa-wasm`) | general policy; `opa build -t wasm`; many built-ins not native in WASM [V S28] | yes, WASM | no figures in docs [V S28]; Rego 76–676 µs median in Cedar's benchmark (server) [V S21 §5.2] | 973 kB SDK + compiled policy [V S29] | 1.10.0, 2024-11-08 (no release for ~2 years) [V S29] | Apache-2.0 |
| Oso | Polar language | was in-process | — | 2.7 MB unpacked [V S29] | "The library version of Oso is now deprecated" (2023-12-18); last 0.27.3 (2024-01) [V S30] | Apache-2.0 [V S29] |
| OpenFGA | ReBAC (§1.3) | **server**; can be embedded only as a **Go** library; in-memory store "is for development only" [V S15]; `@openfga/sdk` is an API client [V S49] | Go server: 89–746 µs median in Cedar's benchmark [V S21 §5.2] | — | SDK 0.9.7, 2026-08 [V S49] | Apache-2.0 |
| SpiceDB | ReBAC | server; a third-party `spicedb-embedded` runs the Go code via FFI (Rust/Python/.NET), no Node binding found [V S17] | — | — | — | Apache-2.0 |

### 2.2. Local micro-benchmark [I]

Measured for this note, not published (S50): x86 Xeon container (2 vCPU), **Node 22.23**, 27 users × 170 devices (5 flats × 4 rooms × 8 + 10 boiler-room devices), the rule of §1.5, 20 000 random requests. Script: one check = one call.

| Engine | µs / check | Load time / RSS added |
|---|---|---|
| Casbin `enforceSync` | 6.7 | 18 ms / +12 MB |
| cedar-wasm `statefulIsAuthorized` (preparsed policies, 5 entities per call) | 92.6 | 27 ms / +16 MB |
| CASL `ability.can` (ability built per user) | 0.41 | 8 ms / +8.6 MB |
| precomputed `Set` of `deviceId\|action` per user | 0.17 | build of all 27 tables: 1.1 ms |

Cortex-A53 numbers are a **[GAP]** — run the same script on a Patron. Expect several times slower [I].

## 3. Speed for a per-message check

| System | What it precomputes or caches | Invalidation | Filtering of lists / events |
|---|---|---|---|
| Home Assistant | merges a user's group policies and compiles them into one function, cached on the user (`cached_property permissions`) [V-src S38] | `User.invalidate_cache()` [V-src S38] | `get_states` returns only entities with read; `state_changed` events are re-checked per event because "the user might have changed since the subscription was created" [V-src S38] |
| EMQX (MQTT) | per-client-session cache of authorization results, `max_size` 32, `ttl` 1 min [V S39] | API / dashboard clear; cleared on reconnect; "A rule change does not revoke a subscription that was already established" [V S39] | — |
| node-casbin | `CachedEnforcer` caches decisions keyed by request strings; `casbinJsGetPermissionForUser` exports model + policy for a front-end [V-src S25] | `invalidateCache()` [V-src S25] | — |
| CASL | one `Ability` per user, rules shared with the UI [V S26] | rebuild | UI hides what `can()` denies |
| OpenFGA | — | — | ListObjects: "what objects a user can see" [V S14] |

For evok-node [I]: a site has hundreds of devices and ~4 privileges, so a full per-session table `address → privilege bits` is small and cheap to build at `onConnection` (1.1 ms for all users in §2.2). Check = one `Map.get` + bit test. Triggers to rebuild: role assignment change (replica sync, 05), introspection change (device added, moved to another room, imported), auth-level change in the session (03). The same table filters `$introspect`. Existing SUBSCRIBEs must be re-checked on rebuild or per event (EMQX lesson; HA practice).

## 4. Where roles live

| Option | Freshness | Size | Offline | Evidence |
|---|---|---|---|---|
| Roles in token claims | stale until refresh: token data "is up to date only at the time you acquire the token" [V S31] | grows with groups. Entra ID omits `groups` above **200 (JWT), 150 (SAML), 6 (implicit flow)** and sends `hasgroups` or `_claim_names` instead; the app "must use Microsoft Graph" [V S31] | works | authentik default `profile` scope puts all group names in `groups` [V-src S32]; no limit seen [I] |
| Resolved by the verifier from user id | as fresh as the replica | token stays small | needs a synced copy of assignments (05) | HA resolves permissions from the user's groups at run time [V-src S38] |
| Hybrid | token: `sub`, session id, `acr` (02, 03); assignments from replica; optional role version in token to detect change [I] | small | yes | Entra: use app roles (`roles` claim) or Graph for real-time membership [V S31] |

Parametric assignments (`tenant@flat3`) can be encoded as claim strings, but the IdP must then know the home hierarchy [I]; authentik property mappings can emit any claim (01).

## 5. Action vocabulary: Matter Access Control

Matter ACL entries are **fabric-scoped** with fields Privilege, AuthMode (CASE, Group; PASE gives implicit Administer during commissioning), Subjects (node IDs, CATs, group IDs; empty = anyone with that AuthMode), Targets (cluster, endpoint, device type; endpoint and device type exclusive; empty = whole node). Spec minimums: 3 entries per fabric, 4 subjects and 3 targets per entry. There is no deny entry [V S33].

| Privilege | Also grants (SDK check) | Default use | Examples of stricter per-element requirements |
|---|---|---|---|
| View | — | read / subscribe attributes and events [V S33] | — |
| ProxyView | View [V-src S34] | for proxies; "not yet supported in the Matter SDK" [V S33]; exact spec meaning [GAP: Matter Core spec §6.6] | — |
| Operate | View [V-src S34] | write attributes, invoke commands [V S33] | OnOff `Toggle`; Thermostat `OccupiedHeatingSetpoint` write; DoorLock `LockDoor`/`UnlockDoor` (must use timed invoke) [V-src S35] |
| Manage | Operate, View [V-src S34] | per cluster element | Thermostat `SystemMode`, `MinHeatSetpointLimit` write; OnOff `StartUpOnOff`; DoorLock `AutoRelockTime`, `OperatingMode` [V-src S35] |
| Administer | Manage, Operate, ProxyView, View [V-src S34] | Access Control cluster [V S33] | DoorLock `SetUser`, `SetCredential`, `SetWeekDaySchedule` [V-src S35] |

Mapping to evok-node — **all [I]**:

| evok-node operation | Privilege |
|---|---|
| `$introspect`, GET, SUBSCRIBE, CALL with `effect: 'none'` | view |
| SET; CALL with `effect: 'mutates'` | operate |
| home driver `manage.*` (levels, rooms, groups, names); device configuration (limits, modes) | manage |
| users, roles, sessions; node and plugin config; raw drivers in the Inspector | administer |
| methods with `proof` | operate **plus** proof / auth level (03); Matter only asks for a timed invoke |

Matter treats thermostat `SystemMode` as Manage but the setpoint as Operate, so `effect: 'mutates'` alone is too coarse; a per-method privilege in metadata would cover it [I]. The Matter bridge keeps its own auth: a controller with Operate on the bridge is not limited to one flat unless the bridge's ACL targets only that flat's endpoints [I].

## 6. Home-automation permission models

| Product | Roles | Scope of limits | Notes |
|---|---|---|---|
| Home Assistant | owner; groups `system-admin`, `system-users`, `system-read-only` [V-src S38] | core policy supports `entity_ids`, `device_ids`, `area_ids`, `domains`, `all` with read / control / edit [V S36]; system groups cover the whole home [V-src S38] | not exposed: "don't expect it publicly exposed anytime soon" (2019) [V S37]; custom group policies load only from storage [V-src S38]; no UI found [I]; additive (only `True` values), owner bypasses [V-src S38, V S36] |
| openHAB | `administrator`, `user` [V-src S40]; custom roles only by editing `users.json` [V S41] | whole home | "Visiblity is merely cosmetic. All the Items are avaiable through the REST API"; "at least three attempts at RBAC" not merged (2026 thread) [V S41] |
| Loxone | users, nested user groups, "Full Access" [V S42] | **rooms, categories, functions**; access schedules; internal / external access [V S42] | deny flag on user or parent wins; "not configured" = not allowed, not inherited [V S42] |
| Homey | Owner (one), Manager, Resident, Guest [V S43] | whole home; Guest is "Control-only" [V S43] | no per-device / zone limits [V S43] |
| Apple Home | owner; invited people with "Add and Edit Accessories" and "Control Accessories Remotely" [V S44] | residents: all accessories; guests: specific doors, locks and security accessories, on a schedule, local only [V S44] | per-accessory limits only for guests [V S44] |
| SmartThings | Owner, Member [V S45]; "control devices only" option (community post) [V S46] | whole location [V S45] | — |
| Google Home | Admin, Member; Member toggles Activity and Settings [V S47] | whole home [V S47] | — |
| Fibaro HC3 | admin; users with "Manage Access" [V S48] | per-scene rights shown [V S48]; per-device rights [GAP: HC3 manual] | — |

Summary [I]: consumer products give whole-home roles; per-room scope appears only in Loxone (and, unexposed, in HA). A multi-flat house with tenants needs scoping that consumer products do not offer.

## 7. Scope for evok-node

What a role parameter could point to [I]:

| Scope | Example | Covers | Precedent |
|---|---|---|---|
| site | `site` | all nodes | Azure management group, GCP organization [V S6, S8] |
| node | `node:flat3-plc` | all drivers of one node | subscription / project [I] |
| driver | `node:basement/drv:modbus1` | raw driver in the Inspector | Kubernetes namespace [I] |
| home hierarchy node | `home:level1/flat3`, `…/kitchen`, `…/kitchen/spots` | devices below it | HA `area_ids` [V S36], Loxone rooms [V S42], Cedar `in` [V S19], OpenFGA `from` [V S12] |
| device | `home:…/light1` | one device | K8s `resourceNames` [V S5], HA `entity_ids` [V S36], Matter endpoint target [V S33] |
| category / type | all locks | cross-cutting | Loxone categories [V S42], HA `domains` [V S36], Matter device-type target [V S33] |

Inheritance and exceptions:

| Mechanism | Who uses it |
|---|---|
| additive only, no deny | Kubernetes [V S5], Matter [V S33], HA policy [V-src S38] |
| inheritance down the tree, union | Azure [V S6], GCP [V S8] |
| deny at a scope, wins over allow | Azure deny assignments (system-managed only) [V S7], Loxone deny flag [V S42], Cedar `forbid` [V S18] |
| exclusion in a relation | OpenFGA `but not` [V S12], SpiceDB `-` [V S16] |

Devices outside their room's rule (e.g. a boiler-room valve shown in flat 3, a shared staircase light): (a) place them in a hierarchy node that matches the boundary, (b) add a device-level grant, (c) deny / "restricted" mark at a node [I]. Imported devices: whether the importing node's hierarchy or the source node decides scope is open; PLC-to-PLC callers are in 02 [I].

## 8. Proposals for 13a (not binding)

- **P1 — Assignment = (subject, role, scope).** Roles are plain names with a privilege set; the parameter is a scope path (site / node / driver / home hierarchy node / device); scope covers its subtree.
- **P2 — Matter-style privileges.** `view < operate < manage < administer`; default from method metadata (GET/SUBSCRIBE/`effect: 'none'` → view, `mutates` → operate); optional per-method override (`privilege: 'manage'`).
- **P3 — Additive first.** Start without deny (as Kubernetes, Matter, HA); model the boundary in the hierarchy; add a narrow "restricted node" or deny later only if a real case needs it.
- **P4 — Per-session compiled table.** At `onConnection` build `address → privilege bits` from assignments + introspection; check = Map lookup; rebuild on role, introspection or auth-level change; re-check live SUBSCRIBEs on rebuild.
- **P5 — No policy engine on the hot path.** Hand-written TS evaluator over the table; Casbin or CASL acceptable if expressiveness is needed; Cedar-WASM too slow per message in Node (§2.2) but usable for offline validation.
- **P6 — Roles from the replica.** Token carries identity, session and `acr`; the verifier resolves assignments by user id from the replica; optional role version claim to detect staleness.
- **P7 — Filter introspection with the same table** (view privilege), as HA does for `get_states`.
- **P8 — Matter bridge alignment.** If tenants use Matter controllers, map evok-node scopes to per-fabric ACL targets (endpoints of their flat).

## 9. Sources

- S1 — ANSI INCITS 359-2004, Role Based Access Control: https://www.cs.purdue.edu/homes/ninghui/readings/AccessControl/ANSI+INCITS+359-2004.pdf
- S2 — Yao, Moody, Bacon: A Model of OASIS Role-Based Access Control and its Support for Active Security, SACMAT 2001: https://www.cl.cam.ac.uk/research/srg/opera/publications/papers/sacmat2001.pdf
- S3 — Abdallah, Khayat: A Formal Model for Parameterized Role-Based Access Control, FAST 2005: https://www.open-access.bcu.ac.uk/4234/
- S4 — Xu, Stoller: Mining Parameterized Role-Based Policies (CODASPY 2013): https://www3.cs.stonybrook.edu/~stoller/codaspy2013.html
- S5 — Kubernetes: Using RBAC Authorization (doc source): https://raw.githubusercontent.com/kubernetes/website/main/content/en/docs/reference/access-authn-authz/rbac.md
- S6 — Microsoft: Understand scope for Azure RBAC: https://learn.microsoft.com/en-us/azure/role-based-access-control/scope-overview
- S7 — Microsoft: Azure deny assignments (doc source): https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/main/articles/role-based-access-control/deny-assignments.md
- S8 — Google Cloud: Using resource hierarchy for access control: https://docs.cloud.google.com/iam/docs/resource-hierarchy-access-control
- S9 — AWS IAM: Policy variables and tags: https://docs.aws.amazon.com/IAM/latest/UserGuide/PolicyVariables.html
- S10 — AWS IAM: Controlling access using tags: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_tags.html
- S11 — Pang et al.: Zanzibar, USENIX ATC 2019: https://www.usenix.org/conference/atc19/presentation/pang
- S12 — OpenFGA: Configuration language (doc source): https://raw.githubusercontent.com/openfga/openfga.dev/main/docs/content/configuration-language.mdx
- S13 — OpenFGA: Parent-child objects: https://openfga.dev/docs/modeling/parent-child
- S14 — OpenFGA: Relationship queries / ListObjects (doc source): https://raw.githubusercontent.com/openfga/openfga.dev/main/docs/content/interacting/relationship-queries.mdx
- S15 — OpenFGA Go module (embedding, storage): https://pkg.go.dev/github.com/openfga/openfga@v1.11.1
- S16 — SpiceDB: Schema: https://authzed.com/docs/spicedb/concepts/schema
- S17 — spicedb-embedded (Rust crate README): https://docs.rs/crate/spicedb-embedded/latest/source/README.md
- S18 — Cedar: How authorization works: https://docs.cedarpolicy.com/auth/authorization.html
- S19 — Cedar: Basic policy construction: https://docs.cedarpolicy.com/policies/syntax-policy.html
- S20 — Cedar: Role management using policy templates: https://docs.cedarpolicy.com/bestpractices/bp-implementing-roles-templates.html
- S21 — Cutler et al.: Cedar: A New Language for Expressive, Fast, Safe, and Analyzable Authorization (OOPSLA 2024, extended): https://arxiv.org/pdf/2403.04651
- S22 — @cedar-policy/cedar-wasm 4.14.0 (registry metadata and package typings): https://registry.npmjs.org/@cedar-policy/cedar-wasm
- S23 — Casbin: RBAC with Domains: https://casbin.apache.org/docs/rbac-with-domains/
- S24 — Casbin: Benchmark: https://casbin.apache.org/ja/docs/benchmark
- S25 — casbin (node-casbin) 5.51.1 (registry and `lib/cjs` source): https://registry.npmjs.org/casbin
- S26 — CASL README: https://raw.githubusercontent.com/stalniy/casl/master/README.md
- S27 — @casl/ability 7.1.0 (registry): https://registry.npmjs.org/@casl/ability
- S28 — OPA: WebAssembly: https://www.openpolicyagent.org/docs/wasm
- S29 — @open-policy-agent/opa-wasm 1.10.0 and oso 0.27.3 (registry): https://registry.npmjs.org/@open-policy-agent/opa-wasm , https://registry.npmjs.org/oso
- S30 — Oso changelogs (deprecation notice): https://www.osohq.com/docs/oss/project/changelogs.html
- S31 — Microsoft: Configuring group claims and app roles in tokens: https://learn.microsoft.com/en-us/security/zero-trust/develop/configure-tokens-group-claims-app-roles
- S32 — authentik default OAuth2 scope mappings (source): https://raw.githubusercontent.com/goauthentik/authentik/main/blueprints/system/providers-oauth2.yaml
- S33 — Matter SDK: Access Control Guide: https://raw.githubusercontent.com/project-chip/connectedhomeip/master/docs/guides/access-control-guide.md
- S34 — Matter SDK: `src/access/Privilege.h`, `AccessControl.cpp`: https://raw.githubusercontent.com/project-chip/connectedhomeip/master/src/access/AccessControl.cpp
- S35 — Matter SDK cluster XML (thermostat, door-lock, onoff): https://raw.githubusercontent.com/project-chip/connectedhomeip/master/src/app/zap-templates/zcl/data-model/chip/thermostat-cluster.xml (also `door-lock-cluster.xml`, `onoff-cluster.xml`)
- S36 — Home Assistant developer docs: Permissions: https://developers.home-assistant.io/docs/auth_permissions
- S37 — Home Assistant developer blog: User permissions (2019-03-11): https://developers.home-assistant.io/blog/2019/03/11/user-permissions
- S38 — Home Assistant core source (`auth/permissions/*`, `auth/models.py`, `auth/auth_store.py`, `components/websocket_api/commands.py`): https://raw.githubusercontent.com/home-assistant/core/dev/homeassistant/auth/permissions/util.py
- S39 — EMQX: Authorization: https://docs.emqx.com/en/emqx/latest/access-control/authz/authz.md
- S40 — openHAB core `Role.java`: https://raw.githubusercontent.com/openhab/openhab-core/main/bundles/org.openhab.core/src/main/java/org/openhab/core/auth/Role.java
- S41 — openHAB community: Custom roles and permissions (June 2026): https://community.openhab.org/t/custom-roles-and-permissions/169573
- S42 — Loxone: User and Rights Management: https://www.loxone.com/enen/kb/user-and-rights-management/
- S43 — Homey: Add and manage user accounts: https://support.homey.app/hc/en-us/articles/360012615814-Add-and-manage-user-accounts-on-Homey
- S44 — Apple: Share control of your home: https://support.apple.com/102386
- S45 — SmartThings: Share Control of your Smart Devices: https://support.smartthings.com/hc/en-us/articles/360051931312-Share-Control-of-your-Smart-Devices
- S46 — SmartThings community: Member permissions (June 2023): https://community.smartthings.com/t/member-permissions-and-new-energy-app-features-june-2023/265551
- S47 — Google: Manage people and permissions in the Google Home app: https://support.google.com/googlehome/answer/9155535
- S48 — DoorBird: Connection guide FIBARO HC3: https://www.doorbird.com/downloads/connect/cnt_fibaro_hc3_en.pdf
- S49 — @openfga/sdk 0.9.7 (registry): https://registry.npmjs.org/@openfga/sdk
- S50 — Local test for this note: Node 22.23 x86, `casbin` 5.51.1, `@cedar-policy/cedar-wasm` 4.14.0, `@casl/ability` 7.1.0, a plain `Set`; the rule of §1.5; 27 users × 170 devices; 20 000 random requests.
