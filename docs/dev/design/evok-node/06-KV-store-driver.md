# 06 — KV-store driver

## 1. Scope

`driver-kv-store` — a namespaced key-value store, reachable from other drivers and apis the same way any driver is (01 §5–§7), so no module has to invent its own file handling. It is 01 §7's worked example of a driver-owned resource that needs no arbitration, only separation. Its job is user data (02 §2) — aliases, groups, labels, plugin settings, a driver's own dynamically-bound endpoints (05 §6.5) — never readings, never platform facts, never config; those already have their own place.

## 2. Namespacing

A namespace is `driver.<id>` or `api.<id>`, and it is never something a caller states. Every `Request` carries `origin: { instanceId, instanceType, client? }` (03 §2); this driver reads `origin.instanceType`/`origin.instanceId` itself and builds the namespace from that alone. `instanceType` exists specifically because `drivers:` and `apis:` are separate keyed maps (02 §3) — a driver and an api can legally share an id, so the bare id can't disambiguate on its own.

This is a deliberate narrowing of 01 §7's original framing: there is no override. A caller cannot ask for a different namespace, deliberately shared or otherwise — nothing today needs one, and the moment something does, that's a real requirement to design against rather than a hook to keep warm. Renaming an instance's own id is still deletion plus creation, not a rename (02 §3), and its whole namespace goes with it — that consequence is unchanged.

A **key** is a plain string, entirely the calling module's own business past that. It never appears in an `Address` — see §4 — so it carries no grammar constraints from the messaging layer at all: dots, colons, whatever the caller finds useful.

## 3. Operations

Five methods, all `CALL`-shaped (05 §6.1) — `get`, `has`, `set`, `delete`, `list` — because a value has no fixed shape to hang a `reading`/`channel` off of, and `CALL` is exactly the shape for "an addressable thing with an effect and no stable value type of its own." There is nothing richer: no ranges, no transactions across keys, no query. A caller that needs more than this is asking for a different kind of storage, not a bigger version of this one.

| Method | Effect | Args | Result | Notes |
|---|---|---|---|---|
| `get` | `none` | `{ key: string }` | `json` | `errorKinds: ['key-not-found']` (05 §6.1) — a missing key resolves `{ok:false, kind:'domain-error', domainErrorKind:'key-not-found'}` (03 §7, 05 §6.4), never `internal-error` |
| `has` | `none` | `{ key: string }` | `bool` | never fails — presence is the whole answer, there is no separate error case |
| `set` | `mutates` | `{ key: string, value: json }` | `json` | echoes exactly the `value` it was given |
| `delete` | `mutates` | `{ key: string }` | `bool` | idempotent — always resolves `true`, whether or not the key existed |
| `list` | `none` | *(none)* | `json` | the caller's own keys, as a plain string array |

`value`'s codec is `json` — the closed vocabulary's own escape hatch for "no stable shape to declare" (03 §5) — because this driver stores exactly what it's given and never interprets it. Array data rides through this the same as anything else: `set('group-1', ['DI.01', 'DI.02'])` needs nothing special. `list`'s result is `json` too for the same reason: the closed `returns` vocabulary has no array-of-scalar member today, only scalars, `enum`, `struct` and `json` itself — widening it is a separate, general question for 05, not something to settle here for one method's sake.

`get`'s `key-not-found` domain error and `has`'s plain boolean look like they're solving the same problem twice, and they are, on purpose: `has` exists for a caller that only wants the question answered, without paying to move a value across the process boundary it doesn't want.

## 4. Dispatch

Built on `driver-kit` exactly as any other driver would be — `bind()` these five at `attach()` (05 §6.7), once, and never again. There is no dynamic binding here: the endpoint table is these five methods, forever, so `$introspect`'s `generation` never bumps after startup and a client watching it sees a driver that simply never changes shape. This only works because `onGet`/`onSet`/`onCall` now receive the full `Request` as their last argument (05 §6.4) — this driver is the reason that exists: `get`/`has`/`set`/`delete` all read `req.origin` to resolve §2's namespace, something the payload-only handler shape from before couldn't do.

Generic payload validation against each method's `argsCodec` happens before a handler ever runs, same as any `driver-kit`-bound endpoint (03 §5) — this driver's own handlers never re-check that `key` is a string.

## 5. Backing store

`node:sqlite` — built into Node 24 (release-candidate stability, no flag needed), not a native addon, so it carries none of the native-crash risk 01 §8 warns about for a compiled binding like `better-sqlite3`. One file per driver instance, not one per namespace: 01 §2 already says user data's transport is *a* database file, singular, and a namespace is just a column value, not a filesystem boundary — nothing about isolation needs a separate file per caller.

```sql
CREATE TABLE IF NOT EXISTS kv (
  namespace TEXT NOT NULL,
  key       TEXT NOT NULL,
  value     TEXT NOT NULL,   -- JSON.stringify(value)
  PRIMARY KEY (namespace, key)
);
```

The composite primary key already is the index — `namespace` and `key` together, nothing more is needed, no separate `CREATE INDEX`.

```yaml
drivers:
  KV:
    type: kv-store
    path: /var/lib/evok-node/kv/KV.db   # optional; default is this — <driverId>.db under the state dir
```

`path` is this driver's only config key. Talked to through a small interface of this driver's own (`open`/`all`/`upsert`/`remove`), never raw `node:sqlite` calls scattered through the handlers — `basics/02-Coding.md` §5.1's "behind an interface thin enough to swap it out," so a future engine change is one file, not a rewrite.

## 6. In-memory mirror

`Map<Namespace, Map<Key, Value>>`, hydrated once at `configure()` from `SELECT * FROM kv`, kept in sync on every `set`/`delete`. `get`/`has`/`list` answer from this and never touch disk — 01 §8's "never a synchronous disk read" applies here exactly as it does to any other driver's `GET`. No library: this is a plain nested `Map`, not a cache — there is no eviction, because everything stays resident. That's safe specifically because this driver's job is metadata (aliases, labels, settings), never readings or timeseries — both are non-goals stated elsewhere (root README, 05 §2) — so unbounded growth was never the shape of this data to begin with.

## 7. Writes: order and durability

`set`/`delete` write to sqlite first, then update the mirror, then respond. This ordering is the whole durability story: the mirror is never ahead of disk, so a crash between the two loses nothing that was ever acknowledged, and a write that throws — disk full, say — never touches the mirror at all, surfacing as an ordinary `internal-error` (03 §4) with no special-casing needed.

This does briefly block the driver's own event loop, which sounds like it collides with 01 §8's "nothing on the boundary may block" — it doesn't, and it's worth saying why: that rule is about a slow *remote* answer masquerading as a fast one, so a caller can trust that a timeout means the driver is wedged, not that a bus was slow. A local write of a few bytes to sqlite is neither slow nor remote; treating it under the same rule as a live Modbus read would be a category error, not a stricter reading of the same principle.

## 8. Concurrency across reload

This driver's own `isConfigEqual` is just `path` equality — its only config key — so 02 §5.1's "present in both, `isConfigEqual` true ⇒ untouched" already covers every reload that doesn't touch storage location: this driver isn't part of them at all. Only an actual `path` change reaches `prepareReload`/`reload`.

When it does: `prepareReload` closes the current db handle; `reload` reopens at the new path and rehydrates the mirror fully before returning. `onRequest` is registered once at startup (05 §6.7) and is never re-registered on reload, so requests keep arriving through the same handler during that gap — this driver gates them itself with an internal readiness promise, replaced (pending) by `prepareReload` and resolved by `reload` once the new mirror is live. Same shape 03 §9 already uses for `not-ready` before the first `onRequest` call, just re-armed for a swap instead of only used once at cold start — no new framework machinery, this driver's own bookkeeping.

## 9. Placement

`worker_thread` (default) is the right choice for this driver in the overwhelming case. `node:sqlite` being Node core rather than a native addon means `child_process` buys nothing here that `worker_thread` doesn't already give — 01 §8's native-crash-isolation argument for choosing it doesn't apply to this driver the way it might to one wrapping a native serial-port binding. "Heavy" for this driver (01 §8's forward reference) means large values or scan-rate write frequency — a caller doing either is asking this driver to be something it isn't; §1 already says what it's for.

## 10. Testing

Tier 1 (unit; `basics/03-Testing.md`), scoped to `packages/driver-kv-store`, against a temp sqlite file — no simulator, no hardware:

- Mirror hydration at `configure()` matches whatever the file already held, across a restart.
- `get`/`has`/`set`/`delete`/`list`, including: `get` on a missing key answers `domain-error`/`key-not-found`, never `internal-error`; `has` never errors; `delete` on a never-set key still resolves `true`; `set` echoes exactly what it was given, including array-shaped `value`.
- Namespace isolation: two fixture origins (one `driver`, one `api`, same bare id) land in `driver.<id>` and `api.<id>` respectively, never collide, and neither can see the other's keys through any payload field — because there isn't one.
- Write ordering: a forced write failure (a locked or unwritable file) leaves the mirror exactly as it was, and answers `internal-error`.
- Reload: a `path` change closes the old handle, rehydrates from the new file, and a request arriving mid-swap resolves only after the swap completes rather than racing it; a config change that leaves `path` untouched never calls `prepareReload`/`reload` at all.
