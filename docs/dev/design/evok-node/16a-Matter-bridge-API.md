# 16a — Matter bridge API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** expose home devices (12a) as bridged Matter devices, so any Matter controller (Apple
Home, Google Home, …) can control them.

**Covers**

- **Projection only.** One home `DeviceType` → one Matter device type, from the fields 12a
  shapes for it (12a §1, §2): cluster mapping, Descriptor/Identify/label clusters, semantic tags
  from 12a's tags, Matter-side length limits.
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
FixedLabel and UserLabel.

| Home `DeviceType` | Matter device type | Clusters |
|---|---|---|
| `GenericSwitch` | Generic Switch `0x000F` | Switch |
| `OnOffLight` | On/Off Light `0x0100` | OnOff |
| `DimmableLight` | Dimmable Light `0x0101` | OnOff, LevelControl |
| `ColorTemperatureLight` | Color Temperature Light `0x010C` | OnOff, LevelControl, ColorControl |
| `ExtendedColorLight` | Extended Color Light `0x010D` | OnOff, LevelControl, ColorControl |
| `OnOffPlugInUnit` | On/Off Plug-in Unit `0x010A` | OnOff |
| `WindowCovering` | Window Covering `0x0202` | WindowCovering |
| `DoorLock` | Door Lock `0x000A` | DoorLock |
| `ContactSensor` | Contact Sensor `0x0015` | BooleanState |
| `AirQualitySensor` | Air Quality Sensor `0x002C` | AirQuality |
| `TemperatureSensor` | Temperature Sensor `0x0302` | TemperatureMeasurement |
| `HumiditySensor` | Humidity Sensor `0x0307` | RelativeHumidityMeasurement |
| `OccupancySensor` | Occupancy Sensor `0x0107` | OccupancySensing |
| `LightSensor` | Light Sensor `0x0106` | IlluminanceMeasurement |
| `RoomAirConditioner` | Room Air Conditioner `0x0072` | OnOff, Thermostat, FanControl |
| `Timer` | — | ignored |

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
