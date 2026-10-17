# 12a — Home Automation Composite driver

## 1. Scope

Package: `packages/driver-hacomposite` (`@evok-node/driver-hacomposite`). Config `type: hacomposite`.

This driver assembles home-automation devices and exposes each on its own tail (§4.1), in evok-node's own terms (05a §3): field names, units and value shapes chosen for evok-node consumers, never copied from another protocol's spec. A device has one of three **origins** — where it is composed:

| Origin | Composed from | Example |
|---|---|---|
| `local` | other drivers' devices in the same daemon, by a template (§3) — or none, for a virtual device such as `Timer` (§2.2) | a `unipi.ro` relay → `OnOffLight`, a `dali.gear` → `DimmableLight`, a `unipi.di` → `GenericSwitch` |
| `matter` | an endpoint of a Matter node paired to this driver's own controller (§4a) | a Matter contact sensor → `ContactSensor` |
| `remote` | a `local` device of another evok-node's hacomposite driver (§4b) | the garden PLC's `OnOffLight` |

It is a composite driver (01 §7): besides reaching other drivers' devices and its KV namespace, it owns two transports of its own — the Matter controller and the peer links — and shares one failure domain with them.

It depends on `driver-kit` (05a), on matter.js (§4a), and on the KV-store driver (06) for devices, templates, remotes, rules (12b), the Matter controller's storage and the hierarchy (§4, §6; 05a §3.6), and on whichever drivers its templates name as sources — reached as `RemoteDevice`s (05a §3.8a), sanctioned the same way reaching a shared transport or KV namespace is (01 §7).

Devices are never declared in config. They are created, edited and removed at runtime through this driver's own management endpoints (§5) — never hand-authored by a config file. `local` devices and remotes come from the Inspector UI (16, 17); `matter` devices from pairing, in the Inspector UI or the user-facing SPA (api-hacomposite); `remote` devices from import (§4b), never by hand.

**Rules.** This driver also runs rules: a change on one of its devices controls others. They are designed in 12b.

**Matter compatibility.** Not every `DeviceType` has a Matter counterpart — `Timer` (§2.2) has none — and the hacomposite Matter api (16a) ignores those that don't; which `DeviceType` maps to which Matter device type is 16a's mapping table. Each one that does is shaped so 16a can project it onto that Matter device type without holding device state of its own (13): every value a Matter attribute or event needs is present as a field, and every value a Matter controller may write has a field to land on. Cluster mapping, Descriptor/Identify/label clusters, semantic tags, Matter-side length limits and bridging are 16a's. This driver holds none of the bridge's data — the bridge's bindings, groups, scenes, ACLs, fabric tables and keys live in 16a (13's protocol identity state). What it does hold is its own controller's fabric (§4a): there this driver is the client, and that fabric is its user data.

## 2. DeviceType catalogue

### 2.1. Common fields

Every hacompos `DeviceType` spreads one shared set of fields. Reuse is a plain TypeScript constant — no builder of its own, nothing new in 05a:

```ts
// @evok-node/driver-hacomposite
const Label = Codecs.struct({ label: Codecs.string(), value: Codecs.string() });
const Tag   = Codecs.struct({ key: Codecs.string(), value: Codecs.string() });   // e.g. { key: 'position', value: 'left' }, { key: 'index', value: '2' }

export const CommonFields = {
  name:       channel(Codecs.string(), { subscribe: true }),
  userLabels: channel(Codecs.array(Label), { subscribe: true }),
  info:       reading(Codecs.struct({ fixedLabels: Codecs.array(Label), tags: Codecs.array(Tag) })),
  reachable:  reading(Codecs.bool(), { subscribe: true }),
  origin:     reading(Codecs.string({ enumValues: ['local', 'matter', 'remote'] })),
  exposed:    reading(Codecs.bool(), { subscribe: true }),
  identify:   optional(method('mutates', Codecs.void, Codecs.struct({ seconds: Codecs.uint16() }))),   // seconds: 0 stops
};
export type CommonKey = keyof typeof CommonFields;
```

Who binds what:

| Field | Bound by | Backed by |
|---|---|---|
| `name`, `userLabels` | this driver | `DeviceRecord` (§4) — a `SET` persists the record before it answers, then emits |
| `info` | this driver | `DeviceRecord.fixedLabels`/`tags`, authored through `manage` (§5) only |
| `reachable` | this driver | computed — §4.2 |
| `origin` | this driver | `DeviceRecord.origin.kind` (§4.1) — what a peer reads to import only `local` devices (§4b) |
| `exposed` | this driver | `DeviceRecord.exposed`, written through `manage` only; on a `remote` device, the remote's own value |
| `identify` | the origin | `local`: only when its template supplies an `indicator` role (§3); otherwise left unbound and listed in the device's `unbound` (05a §4). `matter`/`remote`: **Open** (§4.1) |
| everything else | the origin | `local`: `assemble()` (§3). `matter`/`remote`: **Open** (§4.1) |

`exposed: false` hides a device from user control, not from the system: 16a ignores it; api-hacomposite still lists it and lets a user put it in rules (12b), but offers no control for it; the Inspector UI still controls it.

Tags are evok-node vocabulary — `position` (`left`/`right`/`top`/`bottom`/`middle`), `index` (1-based) — plus anything else a user finds useful. No length limits here; 16a maps the keys it knows to Matter semantic tags, ignores the rest, and truncates labels to whatever Matter allows.

### 2.2. Device types

No hacompos `DeviceType` declares `'@'` — every field is named. The whole device is still one round trip: `GET` with `returnFields: '*'` (05a §3.5a, `RemoteDevice.getAll`, 05a §3.8a) for a snapshot, `SUBSCRIBE` on the device's own tail (05a §6) for every field's changes.

| DeviceType | Matter counterpart (16a) | Fields beyond `CommonFields` |
|---|---|---|
| `GenericSwitch` | Generic Switch | `switch` reading `{position, lastEvent}` · `multiPressMax` reading |
| `OnOffLight` | On/Off Light | `onOff` channel\<bool\> |
| `DimmableLight` | Dimmable Light | `onOff` · `level` channel\<uint8, 0–254\> · `move` method `{direction}` · `stop` method |
| `ColorTemperatureLight` | Color Temperature Light | `onOff` · `level` · `move` · `stop` · `colorTemp` channel\<uint16, mired\> · `colorTempRange` reading `{min, max}` |
| `WindowCovering` | Window Covering | `position` reading `{current, target, motion}` (%) · `goTo` method `{percent}` · `stop` method |
| `DoorLock` | Door Lock | `state` reading `locked`/`unlocked`/`jammed`/`unknown` · `lock` method · `unlock` method |
| `ContactSensor` | Contact Sensor | `contact` reading\<bool\> |
| `AirQualitySensor` | Air Quality Sensor | `airQuality` reading `good`/`fair`/`moderate`/`poor`/`veryPoor`/`extremelyPoor`/`unknown` |
| `TemperatureSensor` | Temperature Sensor | `temperature` reading\<float32, °C\> |
| `HumiditySensor` | Humidity Sensor | `humidity` reading\<float32, %\> |
| `OccupancySensor` | Occupancy Sensor | `occupied` reading\<bool\> |
| `LightSensor` | Light Sensor | `illuminance` reading\<float32, lx\> |
| `RoomAirConditioner` | Room Air Conditioner | `onOff` · `mode` channel `off`/`cool`/`heat`/`auto`/`fan`/`dry` · `setpoint` channel\<float32, °C\> · `temperature` reading · `fanMode` channel `auto`/`low`/`medium`/`high` |
| `Timer` | — (16a ignores it) | `running` reading\<bool\> · `remaining` reading\<uint32, s\> · `elapsed` reading `{seq, at}` · `start` method `{seconds}` · `cancel` method |

Every reading and channel above is `subscribe: true`. A source's own staleness never appears per field — it folds into `reachable` (§4.2). Two in full; the rest follow the same shape:

```ts
const SwitchState = Codecs.struct({
  position:  Codecs.uint8(),                       // 0 = released, 1 = pressed
  lastEvent: Codecs.struct({
    type:  Codecs.string({ enumValues: ['press', 'release', 'longPress', 'longRelease', 'multiPress', 'multiPressComplete'] }),
    count: Codecs.uint8(),                         // presses counted so far; 0 outside a multi-press
    seq:   Codecs.uint32(),                        // +1 per event — two identical presses are two values, never one
    at:    Codecs.timestamp(),
  }),
});

export const GenericSwitch = device('hacompos.GenericSwitch', {
  ...CommonFields,
  switch:        reading(SwitchState, { subscribe: true }),
  multiPressMax: reading(Codecs.uint8({ min: 2 })),   // the template's own setting (§2.3), exposed read-only
});

const onOffField = channel(Codecs.bool(), { subscribe: true });   // shared by every light and RoomAirConditioner
const levelField = channel(Codecs.uint8({ min: 0, max: 254 }), { subscribe: true });
const moveField  = method('mutates', Codecs.void, Codecs.struct({ direction: Codecs.string({ enumValues: ['up', 'down'] }) }));   // shared by both dimmable lights
const stopField  = method('mutates', Codecs.void, Codecs.void);

export const DimmableLight = device('hacompos.DimmableLight', {
  ...CommonFields,
  onOff: onOffField,
  level: levelField,
  move:  moveField,
  stop:  stopField,
});
```

`lastEvent` carries a full press/release/long-press/multi-press sequence as consecutive values — a short press is `press` → `release`, a long one `press` → `longPress` → `longRelease`, a double press ends `multiPressComplete` with `count: 2` — so a consumer that needs discrete events (16a) can rebuild each one from a subscription, and a gap in `seq` tells it one was coalesced away (03 §6.3).

`move` changes `level` until `stop` or the end of the range. How — a DALI gear's own `UP`/`DOWN`, a ramp on the `Clock` (04 §4) — and how fast are the template's (§3, §2.3). It lets a rule dim on a long press without waiting itself (12b §2.1).

`Timer` is a virtual device: its template has no roles (§3). It is how a rule waits, since rules never do (12b §1). `start` (re)starts it for `seconds`; when it runs out, `running` turns false and `elapsed` emits with `seq` +1; `cancel` stops it without `elapsed`. Timers are not persistent: after a restart every timer is stopped.

A function a device type has no evok-node equivalent for yet is simply not a field — never a stub that answers nothing.

### 2.3. Settings live in management, not on the device

How a device *behaves or is assembled* — a `GenericSwitch` template's long-press threshold and multi-press window, a DALI-sourced light's fade time (the template writes it to the gear's own `fadeTime`, 12 §9.1) — is a **setting**: declared by the template (§3), stored in `DeviceRecord.settings` (§4), edited only through `manage` (§5), never a device field. A device field is only what a consumer needs to read or control at runtime. A setting a consumer still needs to *see* — `multiPressMax`, which 16a must report — is additionally exposed as a plain `reading` whose value comes from `settings`; it is never writable through the device.

### 2.4. Option specs

What a human fills in is described by `OptionSpec`, so the Inspector UI and the SPA can render an input for each one without knowing the kind behind it. Rule options use it (12b §3). Template settings (§2.3) moving to it is **Open**.

```ts
// @evok-node/driver-hacomposite
interface DeviceSelection {
  readonly types: readonly DeviceType[];   // allowed DeviceTypes; on the wire, their `kind` strings
  readonly min: number;
  readonly max: number;
}

interface OptionBase {
  readonly key: string;                    // what the function reads the value by
  readonly label: LocalizedText;           // 04 §7
  readonly hint?: LocalizedText;
}

type OptionSpec =
  | OptionBase & { readonly type: 'string'; readonly minLength?: number; readonly maxLength?: number; readonly default?: string }
  | OptionBase & { readonly type: 'number'; readonly min?: number; readonly max?: number; readonly step?: number; readonly default?: number }
  | OptionBase & { readonly type: 'select'; readonly choices: readonly { readonly key: string; readonly label: LocalizedText }[];
                   readonly multi?: boolean; readonly default?: string | readonly string[] }
  | OptionBase & { readonly type: 'device' } & DeviceSelection;
```

| `type` | Stored value |
|---|---|
| `string` | string |
| `number` | number |
| `select` | the choice's `key`; with `multi`, an array of keys |
| `device` | an array of device tails (§4.1) |

An option without `default` is required; a `device` option has none. The values are validated by one codec built from the specs (05a §3.1); a `device` value is also checked against this driver's devices and `types`.

## 3. Templates

A **template** is a named recipe for assembling one `DeviceType` from other drivers' devices. The same `DeviceType` can have several — `DimmableLight` is assembled differently from a `dali.gear` than from a PWM `unipi.ao` — and a template declares only the *roles* it needs, never a concrete address; the concrete source for each role is chosen per device, at creation time (§4).

```ts
// @evok-node/driver-hacomposite
interface Role<F extends Record<string, EndpointType | OptionalEndpointType>> {
  readonly type: DeviceType<F>;    // the source driver's own exported DeviceType — imported, never redeclared
  readonly optional?: boolean;     // e.g. `indicator`
}

type Sources<R extends Record<string, Role<any>>> = {
  readonly [K in keyof R]: R[K]['optional'] extends true ? RemoteDevice<FieldsOf<R[K]['type']>> | undefined : RemoteDevice<FieldsOf<R[K]['type']>>;
};

interface AssemblyContext<R extends Record<string, Role<any>>, S> {
  readonly sources: Sources<R>;
  readonly settings: S;
  markStale(stale: boolean): void;   // §4.2 — for a source that is present and well-shaped but reports its own data stale
}

interface AssemblyTemplate<F extends Record<string, EndpointType | OptionalEndpointType>, R extends Record<string, Role<any>>, S> {
  readonly kind: string;               // 'dimmable-from-dali', 'dimmable-from-pwm', 'switch-from-di', 'timer', ... — must equal the manifest's templateKind
  readonly deviceType: DeviceType<F>;   // the exported hacompos DeviceType object (05a §3.5: one kind, one object)
  readonly roles: R;                 // e.g. { gear: { type: DaliGear } }, { input: { type: UnipiDi }, indicator: { type: UnipiLed, optional: true } }
  readonly settings: TypedCodec<S>;  // Codecs.void when the template has none
  readonly defaults: S;
  assemble(ctx: AssemblyContext<R, S>):
    { readonly [K in Exclude<keyof F, CommonKey>]?: BindHandlers<…> } & { readonly identify?: BindHandlers<…> };
}
```

A role names a source by its `DeviceType` alone, never a driver kind: a kind already names its own family (`dali.gear`), and which driver serves it is the source's address (§4). `assemble()` returns handlers for the device type's own fields, plus `identify` when an `indicator` role is bound, and never for any other `CommonKey` — a template that does is a packaging mistake, rejected when the template is resolved.

A template may declare no roles: its device is virtual, assembled from nothing — the built-in `timer` template for `Timer` (§2.2) — and is always `reachable` (§4.2).

Handlers answer from memory, the way every driver does (01): `assemble()` subscribes to the source fields it needs and emits on its own bound fields as they change, so `onGet` reads the last known value, never a round trip. A `switch-from-di` template turns `input`'s edges into `SwitchState` values using its own settings (long-press threshold, multi-press window, `multiPressMax`); a `dimmable-from-dali` template's `level` reads `gear`'s own `intensity` (12 §9.1) and its `onSet` forwards a write to it.

A `SET` forwarded to a source that can't take it — not up, not answering — throws `SourceUnreachable` (05a §3.5) and is answered `unreachable`. It is never queued and replayed later.

Each built-in `DeviceType` (§2) ships with the templates its own built-in source drivers warrant — `dali`- and relay templates for the lights, a single-`unipi.di` template for `GenericSwitch`, the role-less `timer` for `Timer` — and a template is itself a manifest-loaded, `kind`-resolved module (01 §10; `{ "kind": "hacompos-template", "templateKind": "dimmable-from-dali", … }`), so a driver plugin for hardware this driver doesn't know about yet can ship its own template for an existing `DeviceType` without touching this package. It imports that `DeviceType` from `@evok-node/driver-hacomposite`; it never rebuilds one under the same kind (05a §3.5).

## 4. Device storage and lifecycle

### 4.1. Device record

A **device record** is this driver's own user data (01 §2), stored in its KV namespace (06) alongside templates, remotes and the hierarchy (§4b, §6):

```ts
type DeviceOrigin =
  | { readonly kind: 'local';                               // §3
      readonly templateKind: string;
      readonly sources: Readonly<Record<string, Address>>;  // one driver-qualified address per bound role (03 §3); an unbound optional role is absent
      readonly settings: Value; }                           // decoded by the template's own `settings` codec
  | { readonly kind: 'matter';                              // §4a
      readonly nodeId: string;                              // decimal Matter NodeId — json has no bigint
      readonly uniqueId?: string;                           // BridgedDeviceBasicInformation.uniqueId, when the endpoint has one
      readonly endpoint: number; }
  | { readonly kind: 'remote';                              // §4b
      readonly remoteId: string;
      readonly driverId: string;                            // the remote's hacomposite driver
      readonly tail: string; };                             // the remote device's own tail, verbatim

interface DeviceRecord {
  readonly tail: string;               // this driver's own tail — see below
  readonly deviceType?: string;        // DeviceType.kind; absent only for a `matter` endpoint of unknown type (§4a)
  readonly origin: DeviceOrigin;
  readonly exposed: boolean;           // backs CommonFields.exposed
  readonly name: string;               // backs CommonFields.name
  readonly userLabels: readonly { label: string; value: string }[];   // backs CommonFields.userLabels
  readonly fixedLabels: readonly { label: string; value: string }[];  // backs CommonFields.info
  readonly tags: readonly { key: string; value: string }[];           // backs CommonFields.info
  readonly groupId?: string;           // §6
}
```

Tails are `device.<origin>.<origin-specific>`. For `remote`, the origin-specific part is `<remoteId>.<driverId>.<tail>` — e.g. `device.remote.garden.hacompos.<the remote's tail>`; the remote's tail is carried, never parsed (01 §6). A `remote` origin is another evok-node (§4b); 05a's `RemoteDevice` is only the handle a `local` device uses to reach a source in this daemon.

**Open:** the `local` and `matter` origin-specific tail parts, and what a `matter` or `remote` device binds for each field — designed separately.

`configure()` replays every stored `DeviceRecord`. A `local` one the same way 12-DALI-driver's own stored gears are replayed (12 §10.1, 05a §3.6): resolve `templateKind` → `AssemblyTemplate`, build one `remoteDevice(ctx, address, role.type)` (05a §3.8a) per `sources` entry, call `assemble()`, and `bindDevice()` the result under its tail. A `matter` or `remote` one is bound the same way, ahead of its node or peer link. A device is bound whether or not its sources are up yet, so start order never matters; until they are, the device is simply not `reachable`. A record without `deviceType` is never bound.

Who writes a record depends on its origin: a `local` one through `createDevice`/`updateDevice`/`removeDevice` (§5), a `matter` one through pairing (§4a), a `remote` one through import (§4b). Every write persists the record first, then binds, re-binds or unbinds the device live — the same persist-before-apply order 06 §7 states for any driver's own dynamic binding. A change to a `local` device's `sources` or `settings` re-binds it (unbind, `assemble()`, bind) under the same tail and kind; a change to `name`, labels, tags or `exposed` only emits on the affected common field.

### 4.2. `reachable`

Computed per origin; it emits only when the result flips:

```
local:   every bound source passes its watchDevice check  &&  the template hasn't called markStale(true)
matter:  node.subscriptionActive  &&  endpoint in the node's PartsList  &&  (BridgedDeviceBasicInformation.reachable ?? true)
remote:  peer link up  &&  the remote device's own `reachable`
```

For `local`, each bound device runs one `watchDevice` (05a §4b) per bound source, with `check = (ref, kind) => ref !== null && kind !== undefined && matchesDeviceType(ref, kind, role.type)` (05a §4a). This also covers a source driver reloaded with a table that no longer matches — a source that disappears or changes shape makes the device unreachable rather than broken, and it recovers on its own when a matching table returns.

A `local` device with no roles has no source to check: it is always `reachable`.

For `matter`, a sleepy device (ICD) is reachable while its subscription is alive — it is never expected to answer at once.

Last known values stay readable meanwhile; `reachable` is what tells a consumer not to trust them.

### 4.3. `status`

Management (§5) reports one `status` per device — for a human, beside the `reachable` field consumers read:

| `status` | Meaning |
|---|---|
| `ok` | `reachable` |
| `unreachable` | not `reachable`; its source still exists |
| `missing` | its source is gone — a `matter` endpoint left the node's PartsList, a `remote` device left the remote's introspection |

A `missing` device keeps its record and its tail; it is never removed automatically. A rule using it is `errored` (12b §7). It returns to `ok` on its own when its source comes back — a `matter` endpoint matched by `uniqueId` first (§4a) — or the user removes it (§5).

## 4a. Matter controller

This driver runs one Matter controller, on its own fabric, built on matter.js. It owns that transport (01 §7).

- **No BLE.** `@matter/nodejs-ble` is never a dependency — it is the only part of matter.js with native bindings (01 §8). Pairing is on-network only: a phone app commissions the device first, then opens a pairing window (Matter multi-admin) whose pairing code `commission` (§5) takes.
- **Storage** is a matter.js `StorageDriver` backed by this driver's KV namespace (06) — never matter.js's own file storage, which would make this driver a second owner of the filesystem (01 §7). Multi-key writes go through `batch`; keys are sensitive (06 §5a). matter.js process-level defaults are switched off: signal handlers, argv/env mapping, config-file loading, default storage path.
- **One node, several devices.** A device maps to an endpoint, by its Descriptor's device type list — never to a node. Root and aggregator endpoints are not devices. The node's PartsList is followed: a new endpoint becomes a device, a vanished one becomes `missing` (§4.3).
- **Identity** is `BridgedDeviceBasicInformation.uniqueId` when the endpoint has one — a Matter bridge may renumber its endpoints — and the endpoint number otherwise.
- **Unknown device type** — no hacompos `DeviceType` matches: stored and listed, never bound, never exposed (16a). It can only be unpaired.
- **Unpairing** calls `decommission()`, which removes this fabric from the device. If the device can't be reached, `delete()` drops it locally only, and the answer says so — the device may need a factory reset.

**Open:** which hacompos `DeviceType` each Matter device type maps to, and how its fields bind.

## 4b. Remote PLCs

A **remote** is another evok-node with a hacomposite driver. This driver imports that driver's devices, so one PLC can use another's devices in its own rules, SPA and Matter bridge.

```ts
interface RemoteRecord {
  readonly id: string;         // local handle, e.g. 'garden' — appears in tails (§4.1)
  readonly url: string;        // the remote's nextgen api (15)
  readonly driverId: string;   // the remote's hacomposite driver instance
}                              // credentials: 15's auth design — Open until then
```

- Added and removed at runtime (§5), stored in KV — never in config.
- This driver is a client of the remote's nextgen api and owns that connection (01 §7).
- It follows the remote driver's introspection (05a §4b) and imports every device whose `origin` is `local` — automatically, no picking. The remote's `matter` and `remote` devices are never imported, so mirrors are one level deep and two PLCs can import each other without a loop.
- An imported device's management is read-only here: name, labels, tags and `exposed` are the remote's. Control works: `GET` answers the last value the link delivered, a `SET` or call is forwarded, and one that can't reach the remote answers `unreachable` (§3). Rules on the remote stay the remote's.
- A device the remote drops becomes `missing` (§4.3).

**Open:** how an imported device fits this driver's hierarchy (§6).

## 5. Management endpoints

Listing an assembled device's own fields is `$introspect`/`kit.list()` (05a §3.5), same as any other driver — never duplicated here. What needs its own surface is managing records, Matter nodes and remotes, on non-bus-indexed management tails, exposed in whatever shape the nextgen api (15) and its Inspector UI plugin (16, 17) want, never Matter-shaped:

```ts
type DeviceStatus = 'ok' | 'unreachable' | 'missing';   // §4.3

// devices
listDeviceTypes(): readonly { kind: string; templates: readonly string[] }[];
listTemplates(deviceType: string): readonly {
  kind: string;
  roles: Record<string, { kind: string; optional: boolean }>;
  settings: ValueSchema;               // the template's settings schema, for the Inspector UI to render
  defaults: Value;
}[];
createDevice(args: {                   // always a `local` device
  deviceType: string; templateKind: string;
  sources: Record<string, Address>;
  name: string;
  settings?: Value;                    // omitted ⇒ the template's defaults
  exposed?: boolean;                   // omitted ⇒ true
  fixedLabels?: readonly { label: string; value: string }[];
  tags?: readonly { key: string; value: string }[];
}): DeviceRecord;
updateDevice(tail: string, patch: {
  name?: string; exposed?: boolean; groupId?: string;
  fixedLabels?: readonly { label: string; value: string }[];
  tags?: readonly { key: string; value: string }[];
  sources?: Record<string, Address>; settings?: Value;   // `local` only
}): DeviceRecord;
removeDevice(tail: string): void;
listDevices(): readonly (DeviceRecord & { status: DeviceStatus })[];

// Matter (§4a)
commission(args: { pairingCode: string }): { nodeId: string; devices: readonly DeviceRecord[] };   // unknown types included
unpair(nodeId: string): { decommissioned: boolean };   // false ⇒ removed locally only; the device may need a factory reset
listNodes(): readonly { nodeId: string; devices: readonly string[] }[];   // record tails

// remotes (§4b)
addRemote(r: RemoteRecord): RemoteRecord;
removeRemote(id: string): void;        // removes its imported devices too
listRemotes(): readonly (RemoteRecord & { linkUp: boolean })[];
```

`userLabels` are not here: they are written through the device's own `userLabels` field, by a human or by an api.

`removeDevice` removes a `local` device, or any device that is `missing`. A present `matter` device leaves with its node (`unpair`), a present `remote` one with its remote (`removeRemote`). Rules never block a removal: a rule using the device becomes `device-removed` (12b §7).

Every method validates before anything is persisted or bound, and answers `domain-error` (05a §3.5) — never a throw — since a human in the Inspector UI or the SPA is exactly the caller this is for. `errorKinds`:

- `unknown-device-type`, `unknown-template`, `unknown-device`, `unknown-node`, `unknown-remote`, `duplicate-remote`.
- `invalid-sources` — a required role missing, an unknown role named, or a source whose driver's current introspection fails `matchesDeviceType` against the role's `type` (05a §4a). A device is never created against a source nobody has seen; once created, a missing source only makes it unreachable (§4.2).
- `invalid-settings` — `settings` fails the template's own codec.
- `read-only` — `updateDevice` on a `remote` device; `sources`/`settings` on a non-`local` one; `removeDevice` on a present `matter`/`remote` one.
- `pairing-failed` — `commission` couldn't pair: bad or expired code, device not found on the network.

**Open:** how these methods split across management tails, and which of them api-hacomposite (the SPA's api) may reach. Rule management (12b §8) is reachable from it.

## 6. Grouping hierarchy — group, room, level

A three-level hierarchy, this driver's own user data (06), authored in the Inspector UI (16) alongside devices and templates. Which parts the user-facing SPA (api-hacomposite) may write is **Open** (§5):

```ts
interface Level { readonly id: string; readonly name: string; }
interface Room  { readonly id: string; readonly name: string; readonly levelId: string; }
interface Group { readonly id: string; readonly name: string; readonly roomId: string; }
```

A `DeviceRecord` (§4) belongs to at most one `Group` via its own `groupId`; a device with no `groupId` is simply ungrouped, never an error. Nothing about this hierarchy is Matter's own Groups/Scenes cluster — no group names diverging across devices here, because a name lives once, on the `Group` record, never per-device. It exists only to let the SPA and the Inspector UI organise devices for a human, and plays no part in how a device's own fields are assembled or addressed.

## 7. Testing

Tier 1, against fixture drivers (no hardware) that each expose a handful of `bindDevice`'d devices the same way a real `unipi`/`dali` driver would; `matter` and `remote` cases against an in-process matter.js test node and a fixture nextgen server:

- A template's `assemble()` wires its returned handlers to the fixture source devices it was handed — a `channel` written through the assembled device reaches the fixture source's own `onSet`, never a copy; a `GET` answers the last value the source emitted without a round trip.
- Every assembled device binds every `CommonFields` member except `identify`; `identify` is bound exactly when the template's `indicator` role is, and otherwise appears in the device's `unbound` (05a §4).
- A template returning handlers for a `CommonKey` other than `identify` is rejected when the template is resolved.
- `SET` on `name`/`userLabels` persists the `DeviceRecord` before the reply; after a restart, `GET` returns the written value.
- `GET` with `returnFields: '*'` on an assembled device returns every readable field in one response, with no `'@'` key.
- `GenericSwitch` from a fixture `unipi.di`: two identical short presses produce two `switch` values with consecutive `seq`; a long press produces `press` → `longPress` → `longRelease`; a double press ends with `multiPressComplete`, `count: 2`; `multiPressMax` reflects the device's `settings`.
- `reachable`: false while a source's driver isn't up, true once it binds a matching device, false again when that driver re-binds the tail under a different kind or drops it, and false while the template has `markStale(true)`; emits only on a flip.
- `createDevice` with a required role missing, an unknown role, a source of the wrong kind, or a source no driver currently has, answers `invalid-sources` before any `DeviceRecord` is written or anything is bound; bad `settings` answer `invalid-settings`.
- A `DeviceRecord` restored from a KV fixture at `configure()` binds whether or not its sources' drivers are up yet — exercised the same way 12 §12 exercises stored-gear replay.
- `updateDevice` changing `sources` or `settings` re-binds under the same tail and kind; changing only `name`/labels/tags never re-binds.
- `removeDevice` unbinds the device and deletes its `DeviceRecord`; a later `configure()` never re-creates it.
- Hierarchy: `listDevices()` reports a device's own `groupId` unchanged by anything except `updateDevice`; removing a `Group` a device still references is rejected, never silently orphaning the reference.
- `SET` on a `local` device whose source is down answers `unreachable`, never `internal-error`; once the source returns, the write is not replayed.
- `origin` and `exposed` reflect the record; `updateDevice` changing `exposed` persists before it emits.
- Matter: commissioning a node with N mapped endpoints creates N bound devices, plus an unbound record per unknown endpoint; an endpoint leaving the PartsList becomes `missing` and keeps its record; a bridged endpoint returning under a new number with the same `uniqueId` returns to `ok` on its old tail; `unpair` of an unreachable node answers `decommissioned: false` and removes its records.
- Matter, restart: the controller's storage restores from KV and the paired nodes reconnect without pairing again.
- Remote: only `origin: local` devices are imported, never `matter` or `remote` ones; a device the remote drops becomes `missing`; `updateDevice` on an imported device answers `read-only`; with the link down, `reachable` is false and `SET` answers `unreachable`.
- `DimmableLight` from a fixture source: `move` up raises `level` until `stop`, and stops on its own at 254.
- `Timer` on a fake `Clock`: `start` → after `seconds`, `running` is false and `elapsed.seq` +1; `start` while running restarts the count; `cancel` never emits `elapsed`; after a restart every timer is stopped.
- A template with no roles binds a device that is `reachable` at once.
