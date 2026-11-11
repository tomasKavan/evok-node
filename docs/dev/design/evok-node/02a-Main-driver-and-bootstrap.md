# 02a — Main driver and bootstrap

## 1. Scope

The `main` driver is main's face on the bus: it shows the config, the running instances and the installed plugins, and it validates and applies changes to the dynamic config (02 §3a). The bootstrap api sets up the first WS API. This file also states the dynamic file's own rules — revisions, secrets, write order, where the files live, backup — and what the inspector SPA does when the api serving it reloads.

It assumes 02 (config, merge §3a, startup §5, reload §5.1) and 03a (values, `checkValue`, `Issue`). Not here: who may call the `main` driver — that is the api's auth and ACL (13 §5, 13a).

## 2. The `main` driver

### 2.1. What it is

- **Reserved id `main`**, type `main`, package `driver-main` (01 §11). One per system, never an entry in either file: `main` always spawns it (02 §5 step 6).
- **A driver like any other** — its own `worker_thread`, built on driver-kit (05a). Not code inside `main`: `main` stays off every request path (01 §2), and a plugin that crashes or hangs while `describe` resolves it (§2.5) takes this worker down, not `main`.
- **Reached through an api that names it**: `drivers: ['*', main]`. `'*'` never includes it (03 §8).
- **Read-only in static mode.** With `dynamicConfig` off, the readings, `describe`, `restart` and `reload` work; every write answers `static-config`.

### 2.2. The control channel

```ts
// main ⇄ the main driver only, over its runner's channel (02 §6). Never an envelope, never to anyone else.
interface MainControl {
  snapshot(): ControlSnapshot;                                              // on start; then pushed by onChange
  onChange(cb: (s: ControlSnapshot) => void): void;                         // config, runner states, reload progress
  validate(candidate: DynamicFile): Promise<{ issues: Issue[]; plan: ReloadPlan }>;   // 02 §5 steps 3–5, nothing touched
  apply(candidate: DynamicFile, baseRevision: number): Promise<ApplyResult>;          // §3.1
  restart(id: Id): Promise<void>;
  reload(): Promise<void>;                                                  // the same as systemctl reload
}

type DynamicFile = { revision: number; drivers: Record<Id, Entry>; apis: Record<Id, Entry> };
type Entry = { type: string; run?: Placement; drivers?: readonly string[]; [body: string]: Value };   // head + body, 02 §5 step 3
```

`main` validates, because only `main` sees the whole picture — both files, every module's value type, links, cycles. Before it does, the `main` driver resolves every `type` in the candidate in its own worker (02 §4's `PluginRegistry`): a plugin that throws or hangs on import is an issue there and never reaches `main`.

### 2.3. Readings

Declared with `Values` (03a); shown as TS for brevity. All three are subscribable.

```ts
config: {
  mode: 'static' | 'dynamic';
  revision: number;                                   // the dynamic file's; 0 without one
  drivers: Record<Id, EntryView>;
  apis:    Record<Id, EntryView>;
  issues:  readonly Issue[];                          // paths start at ['drivers' | 'apis', id]; left-out entries' issues too (02 §5)
  reload?: ReloadProgress;                            // the last or the running apply or reload — §3.2
}
type EntryView = {
  source: 'static' | 'dynamic';
  state: 'active' | 'left-out';                       // left-out — 02 §5
  entry: Entry;                                       // as in the file; every sensitive value as a ref — §4
};

instances: readonly InstanceInfo[];
type InstanceInfo = {
  id: Id; kind: 'driver' | 'api'; type: string;
  source: 'static' | 'dynamic' | 'builtin';           // builtin: main, bootstrap
  placement: Placement;
  state: 'not-started' | 'running' | 'stopping' | 'stopped' | 'failed';   // the runner's own (02 §6)
  pid?: number; threadId?: number;
  since: Date;                                        // the last state change
  lastError?: string;                                 // e.g. 'start: EADDRINUSE 0.0.0.0:443'
  links: readonly DriverId[];                         // resolved, '*' expanded
};

plugins: readonly PackageInfo[];                      // from the manifest (02 §4) — nothing imported
type PackageInfo = {
  name: string; version: string; source: 'builtin' | 'plugin';
  plugins: readonly { kind: string; id: string; label?: LocalizedText;
                      status: 'unresolved' | 'ok' | 'error'; error?: string }[];
};
```

### 2.4. Methods

| Method | Effect | Args | Result | `errorKinds` |
|---|---|---|---|---|
| `describe` | `none` | `{ kind: 'driver' \| 'api', type }` | `{ meta: ModuleMeta, config: ValueSchema }` | `unknown-type`, `load-failed` |
| `validate` | `none` | `Changeset` | `{ issues, plan }` | `static-config` |
| `apply` | `mutates` | `Changeset` | `ApplyResult` | `static-config`, `conflict`, `busy` |
| `revisions` | `none` | — | `{ revision, at: Date }[]` | `static-config` |
| `rollback` | `mutates` | `{ revision, baseRevision }` | `ApplyResult` | `unknown-revision`, and `apply`'s |
| `restart` | `mutates` | `{ id }` | void | `unknown-instance` |
| `reload` | `mutates` | — | void | `busy` |

```ts
type Changeset = {
  baseRevision: number;
  drivers?: { set?: Record<Id, Entry>; remove?: readonly Id[] };
  apis?:    { set?: Record<Id, Entry>; remove?: readonly Id[] };
};
type ReloadPlan  = Record<Id, 'start' | 'stop' | 'change' | 'links'>;   // 02 §5.1's buckets; unchanged ids absent
type ApplyResult =
  | { outcome: 'applied'; revision: number; plan: ReloadPlan }
  | { outcome: 'invalid'; issues: readonly Issue[] };                  // nothing written, nothing touched
```

- `set` replaces a whole entry, never merges into it (02 §3a). A static id in `set` or `remove` is an issue.
- The candidate is valid as a whole or not at all: a left-out entry (02 §5) must be fixed or removed in the same changeset.
- `restart` is 02 §5.1's explicit restart: the runner stops and starts the instance. `main` itself cannot be restarted this way (`unknown-instance`).
- `main`'s own cross-instance checks report `code: 'rule'` with these ids: `static-entry`, `reserved-id`, `id-collision`, `unknown-type`, `load-failed`, `unknown-link`, `cycle`, `bootstrap-needs-dynamic`.

### 2.5. Plugins

`plugins` imports nothing. `describe` resolves one module type in this worker, on demand, so a picker ("add a driver") gets labels and a form only for what it shows. A plugin that fails to load answers `load-failed` and its entry in `plugins` turns `error`.

Installing and removing plugins is not designed — **Open, below**. What is known: in v1 it means writing packages and then restarting the daemon, because the manifest is assembled once (02 §4) and `main` cannot unload a module it imported; packages would live outside dpkg's directories, e.g. `/var/lib/evok-node/plugins/node_modules`, as a second manifest root. `PackageInfo` is grouped by package because that is what an install acts on.

## 3. Apply

### 3.1. The flow

```
apply(cs)
 1. another apply or a reload is running          → busy
 2. cs.baseRevision ≠ revision                    → conflict — two tabs, or a hand edit
 3. candidate = dynamic + cs; types resolved in this worker (§2.2)
 4. main: 02 §5 steps 3–5 on static ∪ candidate   → issues ⇒ { outcome: 'invalid' }, nothing touched
 5. main writes the files (§5.2)
 6. main answers { outcome: 'applied', revision, plan }
 7. main runs 02 §5.1's prepare and commit; progress in config.reload
```

**`apply` answers before the reload runs**, for two reasons:

- An apply relayed by an api the reload stops would wait forever: drain waits for the call in flight (13 §3), the call waits for the reload, until its deadline.
- The result survives a reconnect: progress lives in `config.reload` and `instances`, not in a response that may never arrive.

```
apply(cs)       → { outcome: 'applied', revision: 43, plan: { ws: 'change', EXT: 'change', mqtt: 'start' } }
config.reload   → { revision: 43, phase: 'done', results: { ws: 'ok', EXT: 'ok', mqtt: 'failed' } }
instances.mqtt  → { state: 'failed', lastError: 'start: ECONNREFUSED nas:1883', … }
```

### 3.2. Progress

```ts
type ReloadProgress = {
  revision: number;
  phase: 'prepare' | 'commit' | 'done';
  results: Record<Id, 'ok' | 'failed'>;   // per id in the plan; 'failed' ⇒ that instance's lastError
};
```

A `start()` that fails in commit is accepted, not retried (02 §5.1): the revision is current, the instance shows `failed`.

### 3.3. Rollback

`rollback` applies a kept revision's `drivers:` and `apis:` as the whole candidate, through §3.1. It makes a new revision; history is never rewritten. Its secret refs still resolve: a secret is kept while any kept revision refers to it (§5.2).

## 4. Secrets

A member marked `sensitive` (03a §4) is never read back.

```yaml
# what the config reading and the dynamic file show
password: { $secret: k7f3q2mxa9 }

# in a changeset
password: { $secret: k7f3q2mxa9 }   # keep — the ref as read
password: n3w-pa55                  # a new value — main stores it under a new ref
                                    # left out — removed (only if the member is optional)
```

- **Storage.** Values live in the secrets file (§5.1), keyed by a random ref. The dynamic file and every revision hold refs only.
- **A ref is valid only in the entry it came from.** Anywhere else, or unknown, it is `sensitive-missing` (03a §5).
- **Resolved late.** `main` puts the stored value in place of a ref only when it checks a body and hands `Config` to an instance (02 §5 step 4). The `main` driver never holds a stored value; a new one passes through it once, on its way to `main`.
- **Static entries.** The human writes a value in the static file; the `config` reading shows `{ $secret: static }` instead.
- **Never logged** — not by `main`, not by the `main` driver, not in an issue's message.

## 5. Files

### 5.1. Layout

```
/etc/evok-node/config.yaml                       static — by hand; the daemon never writes it
/var/lib/evok-node/config.dynamic.yaml           dynamic — the current revision; refs only
/var/lib/evok-node/config/revisions/000043.yaml  the last keepRevisions revisions; refs only
/var/lib/evok-node/config.secrets.yaml           secrets, mode 0600
```

- The dynamic file stores entries as the user set them — no filled-in defaults — so a changed default in a newer plugin version takes effect.
- A hand edit of the dynamic file is allowed: the next reload reads it and gives it a new revision, so a tab with the old `baseRevision` gets `conflict`.
- The dynamic file starts with a comment saying it is written by evok-node and edited through the inspector.

### 5.2. Write order

```
1. add new secrets                      config.secrets.yaml — tmp + fsync + rename
2. the dynamic file                     tmp + fsync + rename
3. the revision copy                    revisions/<n>.yaml
4. drop revisions beyond keepRevisions, then secrets no kept revision refers to
```

Each step is atomic by itself, so a copy taken between any two is consistent: every ref in the dynamic file exists in the secrets file — at worst there is one secret too many, or the newest revision copy is missing. After a crash between 2 and 3, `main` writes the missing copy at startup.

### 5.3. Backup — for the user docs

An admin procedure, not an api: the user docs are written from this.

- **Config:** the four paths of §5.1. A live copy is safe (§5.2).
- **The whole box:** also the KV store, `/var/lib/evok-node/kv/*.db` and `*.secrets.db` (06) — stop the daemon, or copy each with `sqlite3 <db> ".backup <file>"`.
- **Not needed:** `/etc/evok-node/autogen.yaml` (regenerated) and the hardware definitions (from the package).

```sh
systemctl stop evok-node
tar czf evok-node-$(date +%F).tgz /etc/evok-node/config.yaml /var/lib/evok-node
systemctl start evok-node
# restore: stop, untar to /, start
```

- The archive holds secrets in plain text — protect it.
- Never restore one backup onto two boxes running at the same time: KV holds protocol identity — Matter fabrics, TLS keys (13 §4).

## 6. The bootstrap api

### 6.1. What it is

- **Reserved id `bootstrap`**, type `bootstrap`, package `api-bootstrap` (01 §11). At most one; never an entry in either file. `main` spawns it when `main.bootstrap.enabled` is not `off` (02 §5 step 6), which needs `dynamicConfig: true` (`bootstrap-needs-dynamic`, §2.4).
- **Its only job is to create the first WS API** linked to `main`, then send the browser there.
- **Plain `node:http`** — no ws-kit, no WS extensions, no auth. Linked to `main` only. It serves its own one-form page, not the inspector.
- **Its config** is `main.bootstrap` without `enabled` (02 §5 step 3):

```ts
const BootstrapConfig = Values.struct({
  listen: Values.struct({
    host: Values.string({ default: '0.0.0.0' }),
    port: Values.uint16({ min: 1, default: 8081 }),
  }, { label: 'Listen' }),
});
```

### 6.2. When it listens

It follows `main:config` itself; `main` knows nothing about ws apis.

```ts
const wsSeesMain = (c: ConfigReading) =>
  Object.values(c.apis).some(v => v.entry.type === 'ws' && (v.entry.drivers ?? []).includes('main'));

onConfig(c => {
  if (enabled === 'auto') wsSeesMain(c) ? closeListener() : openListener();
  // 'always': the listener stays open; GET / redirects while wsSeesMain(c)
});
```

**Configured, not running.** A ws api counts in either file, left out or not (02 §5). One that fails to start therefore never reopens a bootstrap without auth: the only window without auth is before the first setup. Bootstrap is setup, not lockout recovery — recovery is a static ws api (02 §3a), or a rollback over SSH: copy a revision over the dynamic file and `systemctl reload`.

### 6.3. HTTP

```
GET  /        → the setup page; 302 to the ws api's URL (§7) once wsSeesMain
POST /setup   { host?, port, tls?, publicUrl? }
              → main:apply({ baseRevision, apis: { set: { ws: { type: 'ws', drivers: ['*', 'main'], listen: { host, port }, tls, publicUrl } } } })
              → 201 { url } | 409 a ws api already sees main | 422 { issues }
```

`listen`, `tls` and `publicUrl` are api-ws's own keys (15); bootstrap knows them because it creates that api. It answers the POST first, and only then does a reload close its listener in `auto` mode (§3.1's reason).

## 7. The SPA and the api serving it

When a changeset touches the api the inspector (16) is connected to:

1. **Before.** `validate`'s plan names the SPA's own api — the hello carries `apiId` (15). The SPA says the connection will drop for a moment. If the change touches `listen`, `tls` or `publicUrl`, it also says how to get back in if the api does not come back (§6.2).
2. **After the answer.** Redirect only when the URL changes:

   ```ts
   const urlOf = (e: WsEntry) => e.publicUrl
     ?? `${e.tls ? 'https' : 'http'}://${isWildcard(e.listen.host) ? location.hostname : e.listen.host}:${e.listen.port}/`;

   if (urlOf(next) !== urlOf(prev)) location.assign(urlOf(next));   // otherwise reconnect in place
   ```

   With `publicUrl` set and unchanged there is no redirect, even when the port changes — a reverse proxy in front is the admin's.
3. **Reconnect** with backoff to the same URL; once connected, read `config.reload`.
4. **No connection within 30 s** → an "api unreachable" page: what was changed, and how to get back in (§6.2).

## 8. Testing

Tier 1 (unit; `basics/03-Testing.md`), against a fake `MainControl` and a fixture file system:

- Readings follow `snapshot`/`onChange`; a left-out entry shows `state: 'left-out'` with its issues.
- `apply`: a stale `baseRevision` is `conflict`; a second apply while one runs is `busy`; `invalid` writes nothing; the answer precedes the first prepare.
- A fixture plugin that throws on import: `describe` answers `load-failed`, its `plugins` entry turns `error`, and the fake `main` never resolves it.
- Write order (§5.2): stopped after each step, the files on disk read back consistent; the missing revision copy is written at startup.
- Revisions: pruning beyond `keepRevisions`; a secret survives while a kept revision refers to it; `rollback` makes a new revision.
- Secrets (§4): a ref keeps the value, a plain value gets a new ref, a left-out optional member is removed; a ref from another entry is `sensitive-missing`; no reading, issue or log line ever holds a stored value.
- Static mode: every write is `static-config`; readings, `describe`, `restart` and `reload` work.
- Bootstrap: `auto` opens and closes as `wsSeesMain` changes; `always` redirects; POST answers 409 when a ws api sees `main`, 422 with issues, 201 with the created entry.
- `urlOf` (§7): `publicUrl` unchanged with a new port → no redirect; no `publicUrl` and a new port or host → redirect; a wildcard host keeps the browser's hostname.

## 9. Open

- **Installing and removing plugins** (§2.5) → M3.15: where plugin packages live and how the manifest finds them is package bootstrapping.
- **A plugin's config inside a module's config is opaque to `validate`** — DALI's `ctrl` (12 §2) is checked only at the driver's `configure()`, so a bad one shows as a failed instance after apply, not as an issue. → M3.10, which designs the DALI inspector plugin.
