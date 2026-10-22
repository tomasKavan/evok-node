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
- **Discrete events** (Generic Switch) rebuilt from 12a's `switch.lastEvent` sequence (12a §2.2).
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
