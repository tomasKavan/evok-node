# 12a — Home Automation Composite driver

## 1. Scope

Package: `packages/driver-hacomposite` (`@evok-node/driver-hacomposite`). Config `type: hacomposite`.

This driver assembles home-automation devices from the endpoints of other drivers already running in the same daemon — a pair of `unipi.RO` relays becomes an `OnOffLight`, a `dali.gear` becomes a `DimmableLight`, a `unipi.DI` becomes a `GenericSwitch`. Each assembled device is exposed on its own tail (`hacompos.<DeviceType>.<n>`), shaped as close to the matching Matter device type as evok-node's endpoint model allows (05a §3), so a future Matter api (13) has a translation to write, never a redesign.

It depends on `driver-kit` (05a) and the KV-store driver (06) for devices, templates and the hierarchy (§4, §7; 05a §3.6), and on whichever drivers its templates name as sources — reaching another driver's own exposed devices is sanctioned the same way reaching a shared transport or KV namespace is (01 §7).

Devices are never declared in config. They are created, edited and removed at runtime through this driver's own management endpoints (§5), via the nextgen api (15) and its Inspector UI plugin (16, 17) — never hand-authored by a config file.

## 2. DeviceType catalogue

Each `DeviceType` (05a §3.3) mirrors one Matter device type's core clusters — close enough that the future Matter api only has to translate field names and units, never invent behaviour this driver doesn't already have.

| DeviceType | Modeled after | Core clusters mirrored |
|---|---|---|
| `GenericSwitch` | Generic Switch | Switch (momentary action events) |
| `OnOffLight` | On/Off Light | OnOff |
| `DimmableLight` | Dimmable Light | OnOff, LevelControl |
| `ColorTemperatureLight` | Color Temperature Light | OnOff, LevelControl, ColorControl (temperature mode only) |
| `WindowCovering` | Window Covering | WindowCovering |
| `DoorLock` | Door Lock | DoorLock |
| `ContactSensor` | Contact Sensor | BooleanState |
| `AirQualitySensor` | Air Quality Sensor | AirQuality |
| `TemperatureSensor` | Temperature Sensor | TemperatureMeasurement |
| `HumiditySensor` | Humidity Sensor | RelativeHumidityMeasurement |
| `OccupancySensor` | Occupancy Sensor | OccupancySensing |
| `LightSensor` | Light Sensor | IlluminanceMeasurement |
| `RoomAirConditioner` | Room Air Conditioner | Thermostat, FanControl |

Two, as `device()` definitions — the rest follow the same shape:

```ts
const GenericSwitch = device('hacompos.GenericSwitch', {
  '@': reading(Codecs.string({ enumValues: ['press', 'release', 'longPress', 'longRelease'] }), { subscribe: true }),
});

const DimmableLight = device('hacompos.DimmableLight', {
  '@':    channel(Codecs.bool(), { subscribe: true }),
  level:  channel(Codecs.uint8({ min: 0, max: 254 }), { subscribe: true }),   // mirrors LevelControl's own CurrentLevel
});
```

A cluster this driver has no evok-node equivalent for yet (Matter's `Scenes`, say) is simply not a field — never a stub that answers nothing. Custom, non-Matter control a device needs beyond its mirrored clusters (12-DALI-driver.md's fade behaviour, say, surfaced on a `DimmableLight` assembled from `dali.gear`) is a genuine sibling field on that `DeviceType`, under a non-Matter field key (`fadeTime`, say) — present on the evok-node side, never translated or exposed once the Matter api (13) exists.

## 3. Templates

A **template** is a named recipe for assembling one `DeviceType` from other drivers' endpoints. The same `DeviceType` can have several — `DimmableLight` is assembled differently from a `dali.gear` than from a PWM `unipi.AO` — and a template declares only the *roles* it needs, never a concrete tail; the concrete tail for each role is chosen per device, at creation time (§4).

```ts
interface AssemblyTemplate<F extends Record<string, EndpointType | OptionalEndpointType>> {
  readonly id: string;                 // 'dimmable-from-dali', 'dimmable-from-pwm', ...
  readonly deviceType: DeviceType<F>;
  readonly roles: Record<string, { driverKind: string; endpointKind: string }>;   // e.g. { gear: { driverKind: 'dali', endpointKind: 'dali.gear' } }
  assemble(sources: Readonly<Record<string, BoundEndpoint<unknown>>>): { readonly [K in keyof F]?: BindHandlers<unknown, unknown> };
}
```

`assemble()` returns `onGet`/`onSet`/`onCall` handlers (05a §3.5) built by closing over the role endpoints it was handed — a `dimmable-from-dali` template's `level` handler reads and writes `gear.@`'s own `intensity` field (12 §9.1) directly; it never re-derives Matter semantics from scratch. Each built-in `DeviceType` (§2) ships with the templates its own built-in source drivers warrant — `dali`- and relay-pair templates for the lights, a single-`unipi.DI` template for `GenericSwitch` — and a template is itself a manifest-loaded, `kind`-resolved module (01 §10), so a driver plugin for hardware this driver doesn't know about yet can ship its own template for an existing `DeviceType` without touching this package.

## 4. Device storage and lifecycle

A **device record** is this driver's own user data (01 §2), stored in its KV namespace (06) alongside templates and the hierarchy (§7):

```ts
interface DeviceRecord {
  readonly tail: string;               // 'OnOffLight.3' — this driver's own tail, sans the hacompos. prefix
  readonly deviceType: string;         // DeviceType.kind
  readonly templateId: string;
  readonly label: string;
  readonly sources: Readonly<Record<string, Tail>>;   // one concrete tail per role the chosen template declares
  readonly groupId?: string;           // §7
}
```

`configure()` replays every stored `DeviceRecord` the same way 12-DALI-driver's own stored gears are replayed (12 §10.1, 05a §3.6): resolve `templateId` → `AssemblyTemplate`, resolve each `sources` entry to the live `BoundEndpoint` it names on the owning driver (01 §7), call `assemble()`, and `bindDevice()` the result under `hacompos.<tail>`. A source tail that doesn't resolve — its driver isn't configured, or no longer exposes that endpoint — is a configuration-time fatal for that one device only, logged and skipped, never for the daemon as a whole (05 §2's isolation carried over to driver-to-driver dependencies).

Creating, editing or removing a device writes or deletes its `DeviceRecord` first, then binds or unbinds it live (§5) — the same persist-before-apply order 06 §7 already states for any driver's own dynamic binding.

## 5. Management endpoints

Listing an assembled device's own fields is `$introspect`/`kit.list()` (05a §3.5), same as any other driver — never duplicated here. What needs its own surface is managing the `DeviceRecord`s themselves, on a single, non-bus-indexed management tail, exposed in whatever shape the nextgen api (15) and its Inspector UI plugin (16, 17) want, never Matter-shaped:

```ts
// methods on the `manage` tail
listDeviceTypes(): readonly { kind: string; templates: readonly string[] }[];
listTemplates(deviceType: string): readonly { id: string; roles: Record<string, { driverKind: string; endpointKind: string }> }[];
createDevice(deviceType: string, templateId: string, sources: Record<string, Tail>, label: string): DeviceRecord;
updateDevice(tail: string, patch: Partial<Pick<DeviceRecord, 'label' | 'sources' | 'groupId'>>): DeviceRecord;
removeDevice(tail: string): void;
listDevices(): readonly DeviceRecord[];
```

`createDevice`/`updateDevice` validate `sources` against the chosen template's own `roles` — a role missing, or naming an endpoint whose `driverKind`/`endpointKind` doesn't match, is `bad-payload` before anything is persisted or bound (05a §3.5's own fatal-check discipline, answered as a domain error here rather than thrown, since a human picking tails in the Inspector UI is exactly the caller this is for).

## 7. Grouping hierarchy — group, room, level

A three-level hierarchy, this driver's own user data (06), authored in the Inspector UI (16) alongside devices and templates, and read — never written — by the separate, user-facing controller app:

```ts
interface Level { readonly id: string; readonly name: string; }
interface Room  { readonly id: string; readonly name: string; readonly levelId: string; }
interface Group { readonly id: string; readonly name: string; readonly roomId: string; }
```

A `DeviceRecord` (§4) belongs to at most one `Group` via its own `groupId`; a device with no `groupId` is simply ungrouped, never an error. Nothing about this hierarchy is Matter's own Groups/Scenes cluster — no group names diverging across devices here, because a name lives once, on the `Group` record, never per-device. It exists only to let the controller app and the Inspector UI organise devices for a human, and plays no part in how a device's own fields are assembled or addressed.

## 8. Testing

Tier 1, against fixture drivers (no hardware) that each expose a handful of `bindDevice`'d endpoints the same way a real `unipi`/`dali` driver would:

- A template's `assemble()` wires its returned handlers to the fixture role endpoints it was handed — a `channel` written through the assembled device reaches the fixture endpoint's own `onSet`, never a copy.
- `createDevice` with `sources` missing a declared role, or naming a fixture endpoint of the wrong `endpointKind`, is rejected `bad-payload` before any `DeviceRecord` is written or anything is bound.
- A `DeviceRecord` restored from a KV fixture at `configure()` resolves its own `sources`, rebuilds via `assemble()`, and binds — exercised the same way 12 §12 exercises stored-gear replay.
- A `sources` entry naming a driver/tail the fixture config doesn't have skips only that one device at `configure()`; every other stored device still binds.
- `removeDevice` unbinds the device and deletes its `DeviceRecord`; a later `configure()` never re-creates it.
- Hierarchy: `listDevices()` reports a device's own `groupId` unchanged by anything except `updateDevice`; removing a `Group` a device still references is rejected, never silently orphaning the reference.
