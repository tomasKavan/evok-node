# 16a — Matter bridge API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** expose home devices (12a) as bridged Matter devices, so any Matter controller (Apple
Home, Google Home, …) can control them.

**Covers**

- **Projection only.** One home `DeviceType` → one Matter device type, from the fields 12a
  shapes for it (12a §1, §2): cluster mapping, Descriptor/Identify/label clusters, semantic tags
  from 12a's tags, Matter-side length limits. Devices that are one product are composed under one
  bridged node — below.
- **What is exposed is 12a's decision, not this api's.** Only devices with `exposed: true`
  (12a §2.1), never a device of unknown type (12a §4a). Bridged endpoints are added and removed as
  12a's devices and their `exposed` change.
- **No device state, no exposure state.** Values come from 12a's devices by subscription; nothing
  beyond translation state (13).
- **Protocol identity state — the one thing it persists** (13): fabric table, operational keys,
  IPK and group keys, setup passcode, ACLs, fabric-scoped bindings/groups/scenes, the
  tail → endpoint-number map, message counters. Losing it un-pairs every controller; a changed
  endpoint number loses the device's rooms and automations in the controller. Stored in `api.<id>`
  (06), secrets as sensitive keys (06 §5a).
- **Behaviours, not servers, for device clusters** — below.
- **HS colour.** Home keeps CIE xy (12c-01 §2). If a controller needs HueSaturation (Apple Home?), this
  api converts HS ↔ xy.
- **Writes to an unreachable device:** 12a answers `unreachable` (12a §3); which Matter status that
  becomes.

**Inputs:** 12a · 13 · 06 §5a

- **Target vs current.** 12a stores a `SET`'s target at once (12a §4a); Matter's `CurrentLevel` and
  its like mean the current value. How each is reported while a device moves: per type, 12c (M3.3).
- **Duplicates.** A device two PLCs both bridge shows twice in a controller — the admin's to avoid,
  with `exposed` (12a §4b).

**Mapping table.** One table, implemented once in `@evok-node/driver-home/matter-map` and imported by
12a §4a and by this api — never copied. Device level below; field ↔ attribute, command or event per
type is 12c's (M3.3). Every endpoint also carries Descriptor, Identify, BridgedDeviceBasicInformation,
FixedLabel and UserLabel — on a composed device, BridgedDeviceBasicInformation sits on the parent only (below).
A device with `battery` bound (12a §2.1) also carries Power Source with the battery feature: `BatChargeLevel`,
`BatPercentRemaining` = `percent × 2` (null when absent), `BatReplacementNeeded`, `BatReplaceability` unspecified.

| Home `DeviceType` | Matter device type | Clusters |
|---|---|---|
| `GenericSwitch` | Generic Switch `0x000F` | Switch |
| `OnOffLight` | On/Off Light `0x0100` | OnOff |
| `DimmableLight` | Dimmable Light `0x0101` | OnOff, LevelControl |
| `ColorTemperatureLight` | Color Temperature Light `0x010C` | OnOff, LevelControl, ColorControl |
| `ExtendedColorLight` | Extended Color Light `0x010D` | OnOff, LevelControl, ColorControl |
| `OnOffPlugInUnit` | On/Off Plug-in Unit `0x010A` | OnOff |
| `WindowCovering` | Window Covering `0x0202` | WindowCovering |
| `Closure` | Closure `0x0230`; Closure Panel `0x0231` child with a % (12c-07 §4). Ignored for `kind` `garageDoor`, `gate`, `door` for now | ClosureControl; ClosureDimension on the panel |
| `DoorLock` | — for now; Door Lock `0x000A` when exposed (12c-09 §4) | ignored |
| `WaterValve` | Water Valve `0x0042` | ValveConfigurationAndControl (12c-08 §4) |
| `IrrigationSystem` | Irrigation System `0x0040`, parent of its zones (below) | OperationalState |
| `WaterLeakDetector` | Water Leak Detector `0x0043` | BooleanState; BooleanStateConfiguration when `sensorFault` is bound |
| `ContactSensor` | Contact Sensor `0x0015` | BooleanState |
| `AirQualitySensor` | Air Quality Sensor `0x002C` | AirQuality; CarbonDioxideConcentrationMeasurement, Pm25ConcentrationMeasurement when bound (12c-04 §4) |
| `TemperatureSensor` | Temperature Sensor `0x0302` | TemperatureMeasurement |
| `HumiditySensor` | Humidity Sensor `0x0307` | RelativeHumidityMeasurement |
| `OccupancySensor` | Occupancy Sensor `0x0107` | OccupancySensing |
| `LightSensor` | Light Sensor `0x0106` | IlluminanceMeasurement |
| `Thermostat` | Thermostat `0x0301` | Thermostat, ThermostatUserInterfaceConfiguration (12c-10 §4) |
| `RoomAirConditioner` | Room Air Conditioner `0x0072` — tested with controllers in M3.13 (12c-10 §6) | OnOff, Thermostat, FanControl, ThermostatUserInterfaceConfiguration (12c-10 §4) |
| `TimerRelay` | — | ignored |
| `RainwaterTank` | — | ignored (12c-11 §4) |
| `Fan` | Fan `0x002B` | OnOff, FanControl (12c-12 §4) |
| `VentilationUnit` | Fan `0x002B` — Air Purifier `0x002D` tested in M3.13 (12c-12 §6) | OnOff, FanControl (12c-12 §4) |

**Composed bridged devices.** One bridge, always: one Matter node with an Aggregator, and one bridged
device per exposed home device — or per product, when several home devices are one. A product is
composed as a parent bridged-node endpoint with one child endpoint per member device:

```
ep1  Aggregator
├─ ep2  Bridged node "Hall light"         ← one device, one endpoint
│        Dimmable Light
└─ ep3  Bridged node "Living room"        ← bundle iaq-unipi (12c-04 §3.10)
     ├─ ep4  Temperature Sensor            "Living room – Temperature"
     ├─ ep5  Humidity Sensor               "Living room – Humidity"
     ├─ ep6  Light Sensor                  "Living room – Light"
     └─ ep7  Air Quality Sensor            "Living room – Air quality"
```

| Product link | Members | Parent's name |
|---|---|---|
| `bundle.id` (12a §3a, §4.1) — `local` | the bundle's devices | the bundle's `name` |
| `origin.nodeId` (12a §4.1) — `matter` | the node's devices | its devices' `product.name` (from Basic Information, 12a §4a) |
| an `IrrigationSystem` (12c-08 §3.3) — any origin | its `zones`; never its master or pump | its own `name`. The parent carries the system's own device type and clusters, not only BridgedDeviceBasicInformation |
| none — `remote`, or a device on its own | — | flat, one endpoint |

- Only exposed members are children. A product with one exposed member is flat — except an `IrrigationSystem`, whose parent is a device itself and stays composed with one zone.
- A zone that is also a bundle's member or in a second irrigation system: the admin's to avoid; the first irrigation system by tail order takes it.
- The parent carries BridgedDeviceBasicInformation (`NodeLabel`, `reachable` = every child's
  `reachable`), and Power Source when a member has `battery` — a Matter node's battery is the same for
  every member (12a §2.1). Children carry their own device type, clusters, Descriptor, Identify and labels.
- **Apple Home needs one reading per endpoint** (research/matter/04 §6). An `AirQualitySensor` with
  `temperature` or `humidity` bound — a `matter` ALPSTUGA — gets them as child Temperature Sensor /
  Humidity Sensor endpoints under its parent, not as clusters on its own endpoint. Re-bridged this way,
  such a device's temperature reaches Apple Home where the device's own endpoint does not.
- **Endpoint numbers stay.** The parent is keyed `bundle:<id>`, `node:<nodeId>` or, for an irrigation system, its tail, children by their
  tail (and `:temperature`/`:humidity` for split-out readings), all in the tail → endpoint map. A member
  added or removed adds or removes a child; the parent keeps its number, so the controller keeps its room.
- A product turning flat (one exposed member left), or flat turning composed, re-creates its endpoints:
  controllers re-read them, rooms may be lost. The admin's to avoid, like `exposed` itself.
- SmartThings ignores child endpoints (research/matter/04 §6) — a known limit, not worked around. Irrigation zones are the exception: it maps each as a child device (research/matter/09 §1.3.7).

**matter.js: behaviours, not servers, for device clusters.** Home owns how a device behaves —
templates, `onFor`, fades, press gestures (12c). A matter.js `…Server` brings that logic again,
with its own timers and state, so the two would decide twice and race. Per cluster kind:

| Cluster | matter.js | Its logic |
|---|---|---|
| device — Switch, OnOff, LevelControl, ColorControl, WindowCovering, DoorLock, … | the generated `XxxBehavior.with(features)`, extended here | none — commands forward to home, attributes mirror home, events come from home's values |
| protocol — Descriptor, BridgedDeviceBasicInformation, FixedLabel, UserLabel, Identify | the `…Server` as it is | Matter plumbing only. `IdentifyServer` counts `IdentifyTime` down; this api calls home's `identify` when bound (12c-02 §4) |

What the device servers would do on their own (research/matter/01–03): `SwitchServer` detects
gestures with its own long-press and multi-press timings; `OnOffServer` runs `OnWithTimedOff` on a
100 ms timer and handles scenes; `LevelControlServer` sets `CurrentLevel` to `OnLevel` itself when
the light turns on, and can run its own fades.

```ts
// pseudocode — a dimmable light; the full field ↔ command mapping is 12c-01 §4
class HomeOnOff extends OnOffBehavior.with(OnOff.Feature.Lighting) {
  on()  { return home.set(tail, 'onOff', true); }
  off() { return home.set(tail, 'onOff', false); }
  onWithTimedOff({ onOffControl, onTime }) {
    return home.call(tail, 'onFor', { seconds: ceil(onTime / 10), onlyWhenOn: onOffControl.acceptOnlyWhenOn });
  }
  // toggle, offWithEffect, onWithRecallGlobalScene: the same, one forward each
}
class HomeLevel extends LevelControlBehavior.with(LevelControl.Feature.OnOff, LevelControl.Feature.Lighting) {
  moveToLevel({ level, transitionTime }) {
    return transitionTime == null ? home.set(tail, 'level', level)
                                  : home.call(tail, 'moveToLevel', { level, transitionMs: transitionTime * 100 });
  }
  // move, step, stop and the …WithOnOff variants: forwards
}
class HomeSwitch extends SwitchBehavior.with(/* from `features`, 12c-03 §4 */) {}

subscribe(tail, v => {                                // home → Matter, the only direction values flow
  endpoint.set({ onOff: { onOff: v.onOff, onTime: v.onForRemaining * 10 },
                 levelControl: { currentLevel: v.level, remainingTime: 0 } });
});
subscribe(switchTail, v => {                          // a switch: position, then one event per lastEvent
  endpoint.set({ switch: { currentPosition: v.switch.position } });
  switchEndpoint.events[v.switch.lastEvent.type].emit(payload(v.switch.lastEvent), context);
});
```

- **Commands answer after home does.** A forward that home answers `unreachable` becomes a Matter
  status (above); nothing is applied locally first.
- **Values flow one way**, home → Matter, by `endpoint.set`. A mirror write is never turned back
  into a command [I — verify in matter.js].
- **Every mandatory command** of the chosen features is implemented — a bare behaviour has none.
- **Features are fixed per endpoint.** They come from the device (12c-03's `features`, a light's
  type) when the endpoint is created. If they change, the endpoint is re-created under the same
  endpoint number (tail → endpoint map); controllers re-read it.
- **Switch events** are emitted per `switch.lastEvent`, with the payload of 12c-03 §4; a gap in
  `seq` is not filled in. matter.js's own `SwitchServer` does the same `events.<name>.emit(…)`
  call (research/matter/03 §5).
- **Boolean State `StateChange`** is emitted on every change of a `WaterLeakDetector`'s `leak` —
  mandatory on that device type (12c-08 §4).
