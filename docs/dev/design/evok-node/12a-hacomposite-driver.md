# 12a — Home Automation Composite driver

## 1. Scope

Package: `packages/driver-hacomposite` (`@evok-node/driver-hacomposite`). Config `type: hacomposite`.

This driver assembles home-automation devices from the devices of other drivers already running in the same daemon — a `unipi.ro` relay becomes an `OnOffLight`, a `dali.gear` becomes a `DimmableLight`, a `unipi.di` becomes a `GenericSwitch`. Each assembled device is exposed on its own tail (`hacompos.<DeviceType>.<n>`), in evok-node's own terms (05a §3): field names, units and value shapes chosen for evok-node consumers, never copied from another protocol's spec.

It depends on `driver-kit` (05a) and the KV-store driver (06) for devices, templates and the hierarchy (§4, §6; 05a §3.6), and on whichever drivers its templates name as sources — reached as `RemoteDevice`s (05a §3.8a), sanctioned the same way reaching a shared transport or KV namespace is (01 §7).

Devices are never declared in config. They are created, edited and removed at runtime through this driver's own management endpoints (§5), via the nextgen api (15) and its Inspector UI plugin (16, 17) — never hand-authored by a config file.

**Matter compatibility.** Each `DeviceType` is shaped so the hacomposite Matter api (16a) can project it onto one Matter device type without holding device state of its own (13): every value a Matter attribute or event needs is present as a field, and every value a Matter controller may write has a field to land on. Cluster mapping, Descriptor/Identify/label clusters, semantic tags, Matter-side length limits and bridging are 16a's. This driver holds no Matter or fabric-scoped data — bindings, groups, scenes, ACLs, fabric tables and keys all live in 16a (13's protocol identity state).

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
| `identify` | the template | only when its template supplies an `indicator` role (§3); otherwise left unbound and listed in the device's `unbound` (05a §4) |
| everything else | the template | `assemble()` (§3) |

Tags are evok-node vocabulary — `position` (`left`/`right`/`top`/`bottom`/`middle`), `index` (1-based) — plus anything else a user finds useful. No length limits here; 16a maps the keys it knows to Matter semantic tags, ignores the rest, and truncates labels to whatever Matter allows.

### 2.2. Device types

No hacompos `DeviceType` declares `'@'` — every field is named. The whole device is still one round trip: `GET` with `returnFields: '*'` (05a §3.5a, `RemoteDevice.getAll`, 05a §3.8a) for a snapshot, `SUBSCRIBE` on the device's own tail (05a §6) for every field's changes.

| DeviceType | Matter counterpart (16a) | Fields beyond `CommonFields` |
|---|---|---|
| `GenericSwitch` | Generic Switch | `switch` reading `{position, lastEvent}` · `multiPressMax` reading |
| `OnOffLight` | On/Off Light | `onOff` channel\<bool\> |
| `DimmableLight` | Dimmable Light | `onOff` · `level` channel\<uint8, 0–254\> |
| `ColorTemperatureLight` | Color Temperature Light | `onOff` · `level` · `colorTemp` channel\<uint16, mired\> · `colorTempRange` reading `{min, max}` |
| `WindowCovering` | Window Covering | `position` reading `{current, target, motion}` (%) · `goTo` method `{percent}` · `stop` method |
| `DoorLock` | Door Lock | `state` reading `locked`/`unlocked`/`jammed`/`unknown` · `lock` method · `unlock` method |
| `ContactSensor` | Contact Sensor | `contact` reading\<bool\> |
| `AirQualitySensor` | Air Quality Sensor | `airQuality` reading `good`/`fair`/`moderate`/`poor`/`veryPoor`/`extremelyPoor`/`unknown` |
| `TemperatureSensor` | Temperature Sensor | `temperature` reading\<float32, °C\> |
| `HumiditySensor` | Humidity Sensor | `humidity` reading\<float32, %\> |
| `OccupancySensor` | Occupancy Sensor | `occupied` reading\<bool\> |
| `LightSensor` | Light Sensor | `illuminance` reading\<float32, lx\> |
| `RoomAirConditioner` | Room Air Conditioner | `onOff` · `mode` channel `off`/`cool`/`heat`/`auto`/`fan`/`dry` · `setpoint` channel\<float32, °C\> · `temperature` reading · `fanMode` channel `auto`/`low`/`medium`/`high` |

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

export const DimmableLight = device('hacompos.DimmableLight', {
  ...CommonFields,
  onOff: onOffField,
  level: levelField,
});
```

`lastEvent` carries a full press/release/long-press/multi-press sequence as consecutive values — a short press is `press` → `release`, a long one `press` → `longPress` → `longRelease`, a double press ends `multiPressComplete` with `count: 2` — so a consumer that needs discrete events (16a) can rebuild each one from a subscription, and a gap in `seq` tells it one was coalesced away (03 §6.3).

A function a device type has no evok-node equivalent for yet is simply not a field — never a stub that answers nothing.

### 2.3. Settings live in management, not on the device

How a device *behaves or is assembled* — a `GenericSwitch` template's long-press threshold and multi-press window, a DALI-sourced light's fade time (the template writes it to the gear's own `fadeTime`, 12 §9.1) — is a **setting**: declared by the template (§3), stored in `DeviceRecord.settings` (§4), edited only through `manage` (§5), never a device field. A device field is only what a consumer needs to read or control at runtime. A setting a consumer still needs to *see* — `multiPressMax`, which 16a must report — is additionally exposed as a plain `reading` whose value comes from `settings`; it is never writable through the device.

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
  readonly id: string;               // 'dimmable-from-dali', 'dimmable-from-pwm', 'switch-from-di', ...
  readonly deviceType: DeviceType<F>;   // the exported hacompos DeviceType object (05a §3.5: one kind, one object)
  readonly roles: R;                 // e.g. { gear: { type: DaliGear } }, { input: { type: UnipiDi }, indicator: { type: UnipiLed, optional: true } }
  readonly settings: TypedCodec<S>;  // Codecs.void when the template has none
  readonly defaults: S;
  assemble(ctx: AssemblyContext<R, S>):
    { readonly [K in Exclude<keyof F, CommonKey>]?: BindHandlers<…> } & { readonly identify?: BindHandlers<…> };
}
```

A role names a source by its `DeviceType` alone, never a driver kind: a kind already names its own family (`dali.gear`), and which driver serves it is the source's address (§4). `assemble()` returns handlers for the device type's own fields, plus `identify` when an `indicator` role is bound, and never for any other `CommonKey` — a template that does is a packaging mistake, rejected when the template is resolved.

Handlers answer from memory, the way every driver does (01): `assemble()` subscribes to the source fields it needs and emits on its own bound fields as they change, so `onGet` reads the last known value, never a round trip. A `switch-from-di` template turns `input`'s edges into `SwitchState` values using its own settings (long-press threshold, multi-press window, `multiPressMax`); a `dimmable-from-dali` template's `level` reads `gear`'s own `intensity` (12 §9.1) and its `onSet` forwards a write to it.

**Open:** `onSet` has no `unreachable`/`timeout` arm (05a §3.5) — only `onCall`'s `CallOutcome` does. A `SET` forwarded to a source that doesn't answer has no correct reply today: `RejectedPayload` would misreport it as the caller's fault, a throw as a bug. Needs either such an arm in 05a or a different forwarding rule here.

Each built-in `DeviceType` (§2) ships with the templates its own built-in source drivers warrant — `dali`- and relay templates for the lights, a single-`unipi.di` template for `GenericSwitch` — and a template is itself a manifest-loaded, `kind`-resolved module (01 §10), so a driver plugin for hardware this driver doesn't know about yet can ship its own template for an existing `DeviceType` without touching this package. It imports that `DeviceType` from `@evok-node/driver-hacomposite`; it never rebuilds one under the same kind (05a §3.5).

## 4. Device storage and lifecycle

### 4.1. Device record

A **device record** is this driver's own user data (01 §2), stored in its KV namespace (06) alongside templates and the hierarchy (§6):

```ts
interface DeviceRecord {
  readonly tail: string;               // 'OnOffLight.3' — this driver's own tail, sans the hacompos. prefix
  readonly deviceType: string;         // DeviceType.kind
  readonly templateId: string;
  readonly sources: Readonly<Record<string, Address>>;   // one driver-qualified address per bound role (03 §3); an unbound optional role is absent
  readonly settings: Value;            // decoded by the template's own `settings` codec
  readonly name: string;               // backs CommonFields.name
  readonly userLabels: readonly { label: string; value: string }[];   // backs CommonFields.userLabels
  readonly fixedLabels: readonly { label: string; value: string }[];  // backs CommonFields.info
  readonly tags: readonly { key: string; value: string }[];           // backs CommonFields.info
  readonly groupId?: string;           // §6
}
```

`configure()` replays every stored `DeviceRecord` the same way 12-DALI-driver's own stored gears are replayed (12 §10.1, 05a §3.6): resolve `templateId` → `AssemblyTemplate`, build one `remoteDevice(ctx, address, role.type)` (05a §3.8a) per `sources` entry, call `assemble()`, and `bindDevice()` the result under `hacompos.<tail>`. A device is bound whether or not its sources are up yet — a `RemoteDevice` is only a handle, so driver start order never matters; until its sources appear, the device is simply not `reachable`.

Creating, editing or removing a device writes or deletes its `DeviceRecord` first, then binds, re-binds or unbinds it live (§5) — the same persist-before-apply order 06 §7 already states for any driver's own dynamic binding. A change to `sources` or `settings` re-binds the device (unbind, `assemble()`, bind) under the same tail and kind; a change to `name`, labels or tags only emits on the affected common field.

### 4.2. `reachable`

Each bound device runs one `watchDevice` (05a §4b) per bound source, with `check = (ref, kind) => ref !== null && kind !== undefined && matchesDeviceType(ref, kind, role.type)` (05a §4a). `reachable` is true only when every bound source's check passes and the template hasn't called `markStale(true)`. It emits only when that result flips.

This also covers a source driver reloaded with a table that no longer matches — a source that disappears or changes shape makes the device unreachable rather than broken, and it recovers on its own when a matching table returns. Last known values stay readable meanwhile; `reachable` is what tells a consumer not to trust them.

## 5. Management endpoints

Listing an assembled device's own fields is `$introspect`/`kit.list()` (05a §3.5), same as any other driver — never duplicated here. What needs its own surface is managing the `DeviceRecord`s themselves, on a single, non-bus-indexed management tail, exposed in whatever shape the nextgen api (15) and its Inspector UI plugin (16, 17) want, never Matter-shaped:

```ts
// methods on the `manage` tail
listDeviceTypes(): readonly { kind: string; templates: readonly string[] }[];
listTemplates(deviceType: string): readonly {
  id: string;
  roles: Record<string, { kind: string; optional: boolean }>;
  settings: ValueSchema;               // the template's settings schema, for the Inspector UI to render
  defaults: Value;
}[];
createDevice(args: {
  deviceType: string; templateId: string;
  sources: Record<string, Address>;
  name: string;
  settings?: Value;                    // omitted ⇒ the template's defaults
  fixedLabels?: readonly { label: string; value: string }[];
  tags?: readonly { key: string; value: string }[];
}): DeviceRecord;
updateDevice(tail: string, patch: Partial<Pick<DeviceRecord, 'name' | 'sources' | 'settings' | 'fixedLabels' | 'tags' | 'groupId'>>): DeviceRecord;
removeDevice(tail: string): void;
listDevices(): readonly DeviceRecord[];
```

`userLabels` are not here: they are written through the device's own `userLabels` field, by a human or by an api.

`createDevice`/`updateDevice` validate before anything is persisted or bound, and answer `domain-error` (05a §3.5) — never a throw — since a human picking sources in the Inspector UI is exactly the caller this is for. `errorKinds`:

- `unknown-device-type`, `unknown-template`, `unknown-device`.
- `invalid-sources` — a required role missing, an unknown role named, or a source whose driver's current introspection fails `matchesDeviceType` against the role's `type` (05a §4a). A device is never created against a source nobody has seen; once created, a missing source only makes it unreachable (§4.2).
- `invalid-settings` — `settings` fails the template's own codec.

## 6. Grouping hierarchy — group, room, level

A three-level hierarchy, this driver's own user data (06), authored in the Inspector UI (16) alongside devices and templates, and read — never written — by the separate, user-facing controller app:

```ts
interface Level { readonly id: string; readonly name: string; }
interface Room  { readonly id: string; readonly name: string; readonly levelId: string; }
interface Group { readonly id: string; readonly name: string; readonly roomId: string; }
```

A `DeviceRecord` (§4) belongs to at most one `Group` via its own `groupId`; a device with no `groupId` is simply ungrouped, never an error. Nothing about this hierarchy is Matter's own Groups/Scenes cluster — no group names diverging across devices here, because a name lives once, on the `Group` record, never per-device. It exists only to let the controller app and the Inspector UI organise devices for a human, and plays no part in how a device's own fields are assembled or addressed.

## 7. Testing

Tier 1, against fixture drivers (no hardware) that each expose a handful of `bindDevice`'d devices the same way a real `unipi`/`dali` driver would:

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
