# 02b — Plugins

## 1. Scope

How kapsle is extended without changing its own code: packages, the plugins they contribute, the kinds those belong to. How a package declares them, how they are found, checked and loaded, how a plugin sits inside a module's config, and how packages are installed. Each kind's own doc states only its type and its guard (§5.2); everything they share is here.

It assumes 02 (config, startup §5, runner §6) and 03a (values). Not here: what a driver or an api must do (05, 13); the `main` driver's methods that manage packages (02a §2.5).

## 2. Terms

| Term | Means | Example |
|---|---|---|
| **package** | an npm package — what is installed, updated, removed | `@acme/kapsle-wm3f` |
| **plugin** | one entry in a package's `contributes`: a kind, an id, where to load it | driver `acme.wm3f` |
| **kind** | a family of plugins with one shape, defined by one package | `home-template` |
| **owner** | the package that defines a kind — the only code that runs its plugins | `driver-home` for `home-template` |
| **built-in** | a package shipped in the `kapsle` Debian package | `@kapsle/driver-onboard` |

Nothing distinguishes a built-in plugin from any other but who is to blame when it is broken (§7).

## 3. The manifest

Every package declares itself in its own `package.json`:

```json
{
  "name": "@acme/kapsle-wm3f",
  "version": "1.4.0",
  "peerDependencies": { "@kapsle/module-sdk": "^1.2", "@kapsle/driver-home": "^1.2" },
  "kapsle": {
    "manifest": 2,
    "namespaces": ["acme"],
    "requires": { "kapsle": ">=1.2 <2" },
    "contributes": [
      { "kind": "device",        "id": "acme.wm-relay",     "path": "./dist/index.js", "export": "WmRelay" },
      { "kind": "modbus-binder", "id": "acme.wm-relay",     "path": "./dist/index.js", "export": "wmRelayBinder" },
      { "kind": "hw-definition", "id": "modbus/acme/wm-3f", "path": "./defs/wm-3f.yaml" },
      { "kind": "home-template", "id": "acme.plug-from-wm", "path": "./dist/home.js",  "export": "PlugFromWm" }
    ]
  }
}
```

A package that owns kinds lists them in `defines`:

```json
{
  "name": "@kapsle/driver-home",
  "kapsle": {
    "manifest": 2,
    "defines": [
      { "kind": "home-template", "path": "./dist/kinds.js", "export": "homeTemplateKind" },
      { "kind": "home-bundle",   "path": "./dist/kinds.js", "export": "homeBundleKind" },
      { "kind": "home-rule",     "path": "./dist/kinds.js", "export": "homeRuleKind" }
    ],
    "contributes": [
      { "kind": "driver",        "id": "home",               "path": "./dist/index.js" },
      { "kind": "device",        "id": "home.OnOffLight",    "path": "./dist/types.js", "export": "OnOffLight" },
      { "kind": "home-template", "id": "dimmable-from-dali", "path": "./dist/templates.js", "export": "DimmableFromDali" }
    ]
  }
}
```

| Key | Means |
|---|---|
| `manifest` | the format's version, not the package's. Only `2` is read. |
| `namespaces` | a plugin package's namespaces (§4). A built-in leaves it out. |
| `requires` | package name → semver range. `kapsle` is the release — the version of `@kapsle/main`. Any other name is another package, e.g. the owner of a kind this one contributes to (§5.3). |
| `defines` | kinds this package owns: `kind`, `path`, `export` → a `KindDefinition` (§5.1). |
| `contributes` | plugins: `kind`, `id`, `path`, `export`. |

- `path` is relative to the package root. For a `node` or `browser` kind it names built JavaScript, never source; for a `data` kind, a data file (§5.1). `export` defaults to `default`.
- A package without a `kapsle` key is not read further.
- Description, author, license and homepage are the `package.json`'s own fields — not repeated here.
- `@kapsle/*` are `peerDependencies`, never `dependencies` (§9.3).

## 4. Ids and namespaces

An id is unique within its kind. Kinds are separate: a driver `RO` and a device `RO` never collide.

- **The namespace** of an id is the part before its first `.` — `acme.wm-relay` → `acme`. A kind may say otherwise (`namespaceOf`, §5.1): `hw-definition` takes the second path segment, `modbus/acme/wm-3f` → `acme`. An id without one — `onboard` — is **unprefixed**.
- **Built-ins** use unprefixed ids and any namespace they need (`unipi`, `home`, `dali`, `dyp`…). Every namespace a built-in uses is reserved.
- **A plugin package** lists its `namespaces`. Every id it contributes and every kind it defines is in one of them; unprefixed or reserved is refused.
- **One namespace, one plugin package.** A second package claiming it is refused at install (02a §2.5); found at startup, both are `conflict` (§7).

```yaml
drivers:
  PLC: { type: onboard }       # built-in
  WM:  { type: acme.wm3f }     # plugin
```

## 5. Kinds

### 5.1. `KindDefinition`

```ts
// @kapsle/module-sdk
interface KindDefinition<T> {
  readonly kind: string;                          // equals the manifest's defines[].kind
  readonly meta: PluginMeta;                      // the kind itself — "Home template", for grouping in the UI
  readonly target: 'node' | 'browser' | 'data';
  readonly nestable?: true;                       // T is Configurable and may sit in a module's config — §8
  guard(mod: unknown, id: string): T;             // throws on a bad shape or an id disagreement
  metaOf?(p: T): PluginMeta;                      // default: p.meta
  forms?(p: T): Readonly<Record<string, ValueSchema>>;   // describe (§6.2): 'settings', 'options'… — 'config' of a Configurable is added for it
  namespaceOf?(id: string): string;               // default: the part before the first '.'
}

interface PluginMeta {
  readonly label: LocalizedText;                  // 04 §7
  readonly description?: LocalizedText;           // one or two sentences — a list, a picker
  readonly helpMd?: LocalizedText;                // Markdown — 03a §4
  readonly docsUrl?: string;
}

interface Configurable<C> {                       // driver, api, and every nestable kind
  readonly meta: PluginMeta;
  readonly config: ValueType<C>;                  // 03a
  rules?(config: C): readonly Issue[];            // code 'rule' — 03a §5
  declaredLinks?(config: C): { readonly drivers: readonly DriverId[] };   // 03 §8
}
```

| `target` | `path` names | Loaded |
|---|---|---|
| `node` | an ES module | `import()` in the process that asks |
| `browser` | an ES module for a browser | never in the daemon; served to the Inspector (M3.9) |
| `data` | a YAML or JSON file | read and parsed; the guard gets the parsed value |

- **Every plugin has a `PluginMeta`** — `metaOf(p)`, by default its export's own `meta`. The registry checks `label` after the guard.
- **An export that names its own id** — `DeviceType.kind`, `ModbusKindBinder.kind`, `AssemblyTemplate.kind` — must equal the manifest's `id`. The guard checks it.
- **Guards are duck-typed**, never `instanceof`: a plugin is built against its own copy of `module-sdk`'s types.

### 5.2. The catalogue

| Kind | Owner | Target | Nestable | Resolves to | Doc |
|---|---|---|---|---|---|
| `driver` | `module-sdk` | node | top level | `ModuleDescriptor` | 02 §4, 05 |
| `api` | `module-sdk` | node | top level | `ModuleDescriptor` | 02 §4, 13 |
| `device` | `module-sdk` | node | — | `DeviceType` | 05a §3.3, §3.5 |
| `ws-extension` | `ws-kit` | node | yes | `WsExtensionDescriptor` | 15 |
| `modbus-binder` | `modbus-kit` | node | — | `ModbusKindBinder` | 07a §7 |
| `modbus-handshake` | `modbus-kit` | node | — | `ModbusHandshake` | 07a §9 |
| `hw-definition` | `hw-definitions` | data | — | a hardware definition | 07a §3, 09 §7, 10 §4 |
| `dali-controller` | `driver-dali` | node | yes | `DaliControllerFactory` | 12 §3 |
| `home-template` | `driver-home` | node | — | `AssemblyTemplate` | 12a §3 |
| `home-bundle` | `driver-home` | node | — | `TemplateBundle` | 12a §3a |
| `home-rule` | `driver-home` | node | — | `RuleKind` | 12b §2 |
| `inspector-panel` | `ui` | browser | — | not designed | 17, M3.9 |

`main` owns no kind. It resolves `driver` and `api` like any other consumer (02 §5).

### 5.3. A kind of your own

Any package may define a kind — a plugin package too, inside its own namespace:

```json
// @acme/kapsle-solar
"namespaces": ["acme"],
"defines":     [{ "kind": "acme.inverter-profile", "path": "./dist/kinds.js", "export": "profileKind" }],
"contributes": [{ "kind": "driver", "id": "acme.solar", "path": "./dist/driver.js" }]

// @other/solar-profiles
"namespaces": ["other"],
"requires":    { "kapsle": ">=1.2 <2", "@acme/kapsle-solar": "^2" },
"contributes": [{ "kind": "acme.inverter-profile", "id": "other.fronius-gen24", "path": "./dist/gen24.js" }]
```

- Only the owner's code resolves and runs the kind's plugins — `acme.solar` through `ctx.plugins` (§6.2). `main` and the Inspector only list and describe them.
- A package contributing to a plugin kind names the owner in `requires`: plugin kinds change with their owner's release, not with kapsle's.
- An owner that is not active takes its kind along: the kind's plugins are `unknown-kind`.

## 6. Discovery and loading

### 6.1. Assembly

Once, at startup (02 §5 step 1). Nothing is imported.

1. **Roots**, in order: built-in, system, user (§9.1). In each, the top-level `node_modules` entries, and one level below an `@scope/`.
2. **Read** each `package.json` with a `kapsle` key and check the block's shape.
3. **Skip** a package `plugins.json` disables (§9.2). The same package name in a later root is `conflict`; the earlier root's copy is used.
4. **Check** each package: namespaces (§4), ids unique within each kind, `requires` met.
5. **Mark** each plugin whose kind no active package defines: `unknown-kind`.

Steps 4–5 repeat until nothing changes: a package that drops out takes its kinds with it, and a package that `requires` it drops out too.

The result is the **manifest** — plain strings, nothing loaded:

```ts
type Manifest = {
  kinds:   ReadonlyMap<string, { package: string; path: string; export?: string }>;                        // kind → its KindDefinition
  plugins: ReadonlyMap<string, ReadonlyMap<string, { package: string; path: string; export?: string }>>;    // kind → id → where
};
```

Every process gets the whole manifest at spawn (02 §6): any instance may meet any kind.

### 6.2. `PluginRegistry`

```ts
// @kapsle/module-sdk — one per process, built from the manifest at spawn; ctx.plugins (03 §9)
interface PluginRegistry {
  has(kind: string, id: string): boolean;                       // the manifest only — nothing loaded
  list(kind: string): readonly string[];                        // ids, the manifest only
  resolve<T>(kind: string, id: string): Promise<T>;             // memoized per (kind, id)
  describe(kind: string, id: string): Promise<PluginDescription>;
}

interface PluginDescription {
  readonly meta: PluginMeta;
  readonly forms: Readonly<Record<string, ValueSchema>>;        // kind.forms(p), plus 'config' for driver, api and a nestable kind
}
```

```
resolve('home-template', 'acme.plug-from-wm')
  1. the kind's KindDefinition   — loaded from defines, once per kind
  2. the plugin                  — import(), or read and parse for a data kind
  3. kind.guard(mod, id)         — shape, own id
  4. metaOf(p).label present
  → T, memoized; a failure is memoized too — no retry until the next start
```

- **Lazy.** An id nobody names is never loaded, so a broken plugin nobody uses costs nothing.
- **A rejection means this plugin cannot be used.** What follows is the caller's: a static instance is fatal and a dynamic one is left out (02 §5); a driver's `configure()` rejects (07a, 12); the home driver marks the device `missing` (12a §4.2).
- **No registration API.** A built-in plugin is in the manifest like any other. Importing an export directly — for its types, or to pass a `DeviceType` to `bindDevice` — is allowed; there is one copy of each package (§9.3), so the object is the manifest's.

## 7. Failure policy and status

| Problem | Built-in package | Plugin package |
|---|---|---|
| `kapsle` block malformed | fatal at startup | `invalid` |
| id outside its namespaces, unprefixed, or in a reserved namespace | fatal | `invalid` |
| namespace claimed by another package | fatal | `conflict` |
| duplicate id within a kind; same package in two roots | fatal | `conflict` |
| `requires` not met | fatal | `incompatible` |
| a plugin of a kind no active package defines | fatal | that plugin `unknown-kind` |
| fails to load, or fails its guard | where it is used (§6.2) | the same |

- **A problem in a built-in package is our bug**: the daemon does not start.
- **A plugin package that drops out never stops the daemon by itself.** What uses it follows 02 §5: a static entry whose `type` is gone is fatal, a dynamic one is left out. So the `main` driver refuses to disable or remove a package a static entry uses (`in-use`, 02a §2.5).

```ts
type PackageStatus = 'active' | 'disabled' | 'invalid' | 'conflict' | 'incompatible';
type PluginStatus  = 'unresolved' | 'ok' | 'load-failed' | 'unknown-kind';   // ok / load-failed: as the main driver last resolved it
```

Every status other than `active`, `unresolved` and `ok` carries a `detail` naming the cause.

## 8. A plugin inside a module's config — `Values.plugin`

```ts
// @kapsle/module-sdk — 03a §3
Values.plugin(kind: string, a?: Annotations): ValueType<PluginRef>;
type PluginRef = { readonly use: string; readonly config: Value };   // config defaults to {}
```

```yaml
drivers:
  DALI1:
    type: dali
    ctrl: { use: dali-foxtron-ASCII }                    # 12 §2
    transport: { kind: line, line: { kind: serial, path: /dev/ttyUSB0, baudRate: 19200 } }
apis:
  ws:
    type: ws
    drivers: ['*', main]
    extensions:                                          # 15
      - { use: auth, config: { idp: auth } }
      - { use: acl,  config: { idp: auth } }
```

- **Only a `nestable` kind.** `Values.plugin` of another kind is rejected when the value type is built. The schema is a struct `{ use: string, config: json }` annotated `plugin: { kind }` (03a §2).
- **`main` checks it like a body**, wherever it sits in a module's config (02 §5 step 4): resolve `use` under `kind`; `checkValue` the `config` against the plugin's `config`, binding; decode; `rules`. Issue paths continue the ref's — `['ctrl', 'config', 'unitId']`. A nested plugin's config may hold `Values.plugin` in turn.
- **Links.** A nested plugin's `declaredLinks` join its module's links (03 §8). An api relays to its clients only its own `drivers:` (13 §3).
- **The module gets `{ use, config }`** with `config` still plain data. It resolves `use` through `ctx.plugins` and decodes `config` with that plugin's own value type.
- **Forms.** A picker lists the kind's plugins with their labels (02a §2.3), then shows the chosen plugin's `config` form (`describe`).
- **Equality.** The module's `isConfigEqual` and `rules` see the ref as plain data. A changed nested config is a changed module config (02 §5.1).

## 9. Packages

### 9.1. Sources

| Source | Root | Installed by | Inspector |
|---|---|---|---|
| `builtin` | the daemon's own `node_modules` | the `kapsle` Debian package | read-only |
| `system` | `/usr/lib/kapsle/plugins/node_modules` | another Debian package | enable, disable |
| `user` | `/var/lib/kapsle/plugins/current/node_modules` | the `main` driver (02a §2.5), or `kapsle plugins sync` (§9.5) | managed, unless locked (§9.5) |

A built-in package cannot be disabled.

### 9.2. The user root

```
/var/lib/kapsle/plugins/
  plugins.json         { "disabled": ["@acme/kapsle-wm3f"] }   — system and user packages
  current  → gen-0007/
  previous → gen-0006/
  next     → gen-0008/      staged — becomes current at the next start
  gen-0007/  package.json  package-lock.json  node_modules/…
```

- **A generation** is one npm project; its `dependencies` are the installed user packages.
- **`current` is never changed while the daemon runs**: a plugin may still be loaded from it lazily (§6.2). Install, update and remove build the next generation from a copy of `next`, or of `current` when nothing is staged.
- **At startup, before assembly:** with a `next`, `previous` := `current`, `current` := `next`, `next` removed. Any other generation is deleted.
- **Rollback** stages `previous` as `next`.
- **`plugins.json`** is read at assembly; a change takes effect at the next start too.

### 9.3. Installing

```sh
# run by the main driver in the next generation, as a child process
npm install <spec> --omit=dev --ignore-scripts --legacy-peer-deps --registry <main.plugins.registry>
```

- **`<spec>`** is `name@range` from the registry, an uploaded `.tgz` (02a §2.5), or a `file:` tarball on the PLC (§9.5).
- **No install scripts.** Native code comes prebuilt for the PLC's `cpu` and `os` (e.g. `prebuildify`). A package without a build for this machine is `incompatible`.
- **`@kapsle/*` is always the host's copy.** A plugin lists them as `peerDependencies`; they are never installed into a generation, and one that ends up with its own copy is refused. One copy matters: a template hands the home driver the very `DeviceType` object the home driver binds (05a §3.5).
- **Checked before staging.** After npm, the `main` driver runs assembly (§6.1) over the would-be roots. A package that would not be `active` is refused, and nothing is staged.
- **The registry** is `main.plugins.registry` (02 §5 step 3), by default `https://registry.npmjs.org`. A private registry's credentials: not in v1.

### 9.4. Activation

A staged change takes effect at a daemon restart — the manifest is assembled once, and a loaded module cannot be unloaded. `restartDaemon` (02a §2.4) stops every instance (02 §6) and exits; systemd starts the daemon again (`Restart=always`, basics/01 §3.2.2), and the SPA reconnects (02a §7).

### 9.5. Provisioned deployments

A fleet set up by automation (Ansible, say) gets a fixed set of user packages, declared in the static config, and the Inspector cannot change it:

```yaml
# /etc/kapsle/config.yaml — written by Ansible
main:
  dynamicConfig: false
  plugins:
    locked: true
    packages:                                                   # npm specs
      '@acme/kapsle-wm3f': 1.4.2
      '@other/solar-profiles': 2.1.0
      '@acme/kapsle-x': file:/opt/pkgs/acme-x-1.0.0.tgz     # offline
```

- **`locked`** freezes the user root and `plugins.json` for the `main` driver: every package write answers `plugins-locked` (02a §2.5). It is independent of `dynamicConfig` — a static config may still leave packages to the Inspector, for home templates and rules, which live in KV, not in config.
- **`packages`** is the user root's whole content. It needs `locked: true` — without it, the issue `packages-need-lock`, fatal like any static-file issue (02 §5). Exact versions keep every PLC of a fleet identical; a range is allowed.
- **`kapsle plugins sync`** (basics/01 §3.2.1) builds a generation with exactly `packages` (§9.2, the npm flags and checks of §9.3) and stages it as `next`. It runs as the daemon's user, as every `kapsle` subcommand does; started as root — Ansible's `become` — it switches to that user, so the user root never holds a file the daemon cannot write. The daemon need not run; it never installs anything itself, so a boot never needs the network.
- **One staging at a time.** `plugins sync` and the `main` driver's package writes (02a §2.5) take `/var/lib/kapsle/plugins/.lock`; a second one waits for it — the `main` driver answers `busy` instead.

```
kapsle plugins sync [--config file] [--update]
  packages read from file — by default the static config
  current built from the same packages (same specs; a file: spec also the same sha512) → prints "unchanged", exit 0
  otherwise → builds and checks a generation, stages it as next              → prints "staged", exit 0
  a package that would not be active, npm fails, no packages declared       → the reason, exit 1, nothing staged
  --update: rebuild even when unchanged — picks up newer versions in a range
```

```yaml
# Ansible — packages first, so the config is checked against the plugins it names
- template: { src: config.yaml.j2, dest: /etc/kapsle/config.candidate.yaml }
- command: kapsle plugins sync --config /etc/kapsle/config.candidate.yaml
  register: sync
  changed_when: "'staged' in sync.stdout"
  notify: restart kapsle
- template:
    src: config.yaml.j2
    dest: /etc/kapsle/config.yaml
    validate: kapsle config check %s      # against the staged plugins — basics/01 §3.2.1
  notify: restart kapsle
```

A config that fails the check is never written, the play fails, and the restart handler does not run: the staged generation waits, unused, for the next run.

- **Drift.** At startup, a `current` not built from the declared `packages` — a hand change, a sync not run — is the issue `plugins-drift` in `main:config` (02a §2.3), naming the packages that differ. It is not fatal; a static entry whose plugin is then missing is (02 §5).

## 10. Security

- **A plugin runs inside the daemon, with its rights.** There is no sandbox and no permission model: installing a package is trusting its author.
- **Managing packages is `administer` with proof** (02a §2.5, 05a §3.1b). A locked deployment (§9.5) leaves it to whoever may write the static config and run `plugins sync` on the PLC.
- **Before an install** the Inspector shows the name, version, publisher and the npm `integrity` (sha512) — `inspectPackage`. Signatures: not in v1.
- **Install scripts never run** (§9.3). Plugin text is rendered without raw HTML (03a §4).

## 11. Testing

Tier 1 (unit; `basics/03-Testing.md`) — `module-sdk` and `main`, fixture packages under a fixture root, injected into assembly:

- Shape: a malformed `kapsle` block in a built-in is fatal; in a plugin package, that package is `invalid` and the rest start.
- Namespaces (§4): an unprefixed plugin id and a reserved namespace are `invalid`; two plugin packages with one namespace are both `conflict`; `hw-definition`'s `namespaceOf` takes the second segment.
- Ids: a duplicate within a kind is `conflict`; the same id under two kinds is accepted; the same package in two roots uses the earlier root's.
- `requires` and cascade: an unmet range is `incompatible`; a disabled owner turns its kind's plugins `unknown-kind` and its dependants `incompatible`.
- Laziness: assembly imports nothing (a fixture's load counter stays 0); `resolve` twice loads once; a failed `resolve` is not retried.
- `resolve` order: a plugin without `meta.label` is rejected; an export whose own id differs from the manifest's is rejected; a `data` plugin's guard gets the parsed file.
- `Values.plugin` (§8): a non-nestable kind is rejected when the value type is built; an unknown `use`, and a nested `config` issue at its prefixed path, are issues of the module's body; nested `declaredLinks` join the module's; a nested ref inside a nested config is checked.
- Generations (§9.2): `next` becomes `current` at start and `previous` is kept; an install never writes into `current`; rollback stages `previous`; a generation with its own `@kapsle/*` copy is refused; a fixture install script never runs.
- Provisioned (§9.5), against a fake npm: a `sync` started as root writes files the daemon's user owns; a `sync` while the `main` driver stages waits for the lock; `plugins sync` stages a generation with exactly `packages`; a second run prints `unchanged` and stages nothing; a changed spec, a `file:` tarball with a new sha512, and `--update` stage again; a would-be `conflict` exits 1 and stages nothing; `packages` without `locked` is `packages-need-lock`; a `current` that differs from `packages` gives `plugins-drift` and the daemon starts.

## 12. Open

- **Package bootstrapping** → M3.15: how a generation finds the host's `@kapsle/*`; `npm` on the PLC (a dependency of the Debian package); the daemon's own install path.
- **Usage outside config** → M3.9: a removed home template still named by device records shows as `missing` devices (12a §4.2), but nothing tells the Inspector before the removal. A "who uses this plugin" query for kind owners is not designed.
- **`inspector-panel`** — its shape and how the SPA loads it → M3.9.
