# 16a — Matter bridge API

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../../plan/roadmap.md); do not implement against a memo.

**Job:** expose hacomposite devices (12a) as bridged Matter devices, so any Matter controller (Apple
Home, Google Home, …) can control them.

**Covers**

- **Projection only.** One hacompos `DeviceType` → one Matter device type, from the fields 12a
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
- **Writes to an unreachable device:** 12a answers `unreachable` (12a §3); which Matter status that
  becomes.

**Inputs:** 12a · 13 · 06 §5a

**Open:** the mapping table itself, which waits for 12a's per-origin device details.
