# 02 — Plug-in units and mounted load controls

**Research, not design.** Matter On/Off Plug-in Unit and Mounted On/Off Control: what the spec requires, how controllers show them, real devices, Apple Home support. Feeds 12c's `OnOffPlugInUnit` section. The dimmable variants are listed for comparison only.

Spec data from the connectedhomeip data model, `data_model/1.5/` (S1, S2). Spec prose from matter.js, generated from Matter 1.6.1 (S3).

## 1. Device types

All four are endpoint-scoped simple devices [V-src S1].

| Device type | Since | On/Off | Level Control | Identify, Groups, Scenes Mgmt | Occupancy Sensing client |
|---|---|---|---|---|---|
| On/Off Plug-in Unit `0x010A` | 1.0 | M, LT | **O** (if present: OO + LT, 1–254) | M (`TriggerEffect` M) | O |
| Mounted On/Off Control `0x010F` | 1.4 | M, LT | **O** (same) | M | O |
| Dimmable Plug-in Unit `0x010B` | 1.0 | M, LT | M, OO + LT | M | O |
| Mounted Dimmable Load Control `0x0110` | 1.4 | M, LT | M, OO + LT | M | O |

- On/Off Plug-in Unit and Mounted On/Off Control have **identical cluster requirements**; so do the two dimmable types. Each Mounted type is classified as `superset` of its Plug-in type since 1.4.2 [V-src S1] [V S3].
- What each is for [V S3]:
  - Plug-in Unit — "smart plugs and other power switching devices that are not permanently connected, and which can be unplugged from their power source".
  - Mounted On/Off Control — "any wall-mounted or hardwired load controller". An endpoint of this type should also list On/Off Plug-in Unit in its Descriptor `DeviceTypeList`, for clients older than 1.4.
- Before 1.4, mounted units used the Plug-in Unit type. The spec gives clients a heuristic based on the device type revision found on the endpoint [V S3]; the heuristic table itself is [GAP] — not in S3's text.
- Level Control on an on/off unit is recommended, for a consistent result when it is grouped with dimmable lights and "with on/off" commands are used. It must not change the output except through those commands [V S3].
- Identify `TriggerEffect` and `OffWithEffect` are light effects; an on/off unit may replace them with plain on/off effects [V S3].
- Matter 1.7 (Plug-in Unit revision 5) adds only a Groupcast listener condition on the root node [V-src S1].

## 2. On/Off cluster on these types

LT is mandatory [V-src S1], so everything in [01 §2](01-lights.md) applies to a plug as well. What matters for a relay:

| Element | Fact |
|---|---|
| `OnWithTimedOff` | On for `OnTime`, then off. Units 1/10 s, max `0xFFFE` ≈ 109 min. A second command while on extends to the longer of the two times. `OffWaitTime` then blocks further `OnWithTimedOff` from switching it back on. `0xFFFF` = stay on, no countdown [V-src S2] [V S3, S4] |
| `OnTime`, `OffWaitTime` | Writable (operate). A write only changes a running countdown, never starts one [V S3] |
| `StartUpOnOff` | After power-up: off, on, toggle, or null = previous value. Not applied after an OTA reboot. Write needs Manage privilege [V-src S2] [V S3] |
| `DF` (Dead Front) | Optional. For appliances: while off, other clusters may reject commands with `INVALID_IN_STATE`. Not required by these types [V-src S1, S2] |
| `OFFONLY` | Conformance is "optional if not LT"; LT is mandatory here, so an on/off unit can never be off-only [V-src S1, S2] |

matter.js `OnOffServer` implements the Timed On / Delayed Off state machine and `StartUpOnOff` itself, with a 100 ms tick [V-src S4]. A bridged endpoint built on it gets a working `OnWithTimedOff` without its own code; the countdown then runs in matter.js and ends with `off()` [V-src S4]. It does not apply `StartUpOnOff` on an endpoint under an aggregator — a bridged one [V-src S4].

## 3. Energy measurement

A plug that meters adds an **Electrical Sensor** `0x0510` (since 1.3, utility class): Power Topology mandatory, Electrical Power Measurement and/or Electrical Energy Measurement — at least one [V-src S1]. Apple Home display of Matter energy data: [GAP].

## 4. Controllers

| Controller | On/Off Plug-in Unit | Mounted On/Off Control |
|---|---|---|
| Apple Home | Supported, shown as outlet [V S5]. "Display as" offered for a Matter plug (TP-Link KP125M), not for a Matter wall switch (KS205) [V S6]. Whether this follows the device type: [I] | Not in Apple's list [GAP] — S5 may be outdated |
| Google Home | Type "Outlet". User can pick another type (e.g. fan) at commissioning, so Assistant won't cut it with "lights off". Google recommends On/Off Light if the unit only controls a light [V S7] | Not listed — "not officially supported" [V S7] |
| Home Assistant | `switch` entity, class `outlet` [V-src S8] | No own mapping; falls into the generic OnOff `switch`, class `outlet` [V-src S8] |
| `StartUpOnOff` | Home Assistant exposes it as a config `select` [V-src S8]. Apple Home and Google Home don't let the user edit it [V S9] | same |

Apple Home has a second use for this type: a Water Valve, which Apple refuses, is exposed as an On/Off Plug-in Unit as a workaround (README §2) [V].

## 5. Real devices

| Device | Matter device type |
|---|---|
| Shelly 1 Mini Gen3/Gen4, 1PM Mini Gen4, Shelly 2 Gen3 — in-wall relays | listed under On/Off Plug-in Unit [V S10] |
| Shelly Plug S MTR Gen3, Power Strip 4 Gen4 | On/Off Plug-in Unit [V S10] |
| Shelly 1 Gen4, third-party Thread firmware | chosen at flash time: Light → On/Off Light; Outlet → On/Off Plug-in Unit; Opener → Plug-in Unit + Contact Sensor. "Light and Outlet are electrically identical"; the type can't be changed after commissioning [V S9] |

No product certified as Mounted On/Off Control was found; hardwired relays on the market still use On/Off Plug-in Unit [I].

## 6. Proposals for 12c (not binding)

- **P1 — Matter type for a Unipi relay.** A DIN-rail relay is hardwired, so the spec's choice is Mounted On/Off Control, with On/Off Plug-in Unit also in `DeviceTypeList` (§1). Exposing both keeps Apple and Google working (§4). The evok-node `DeviceType` name could then stay `OnOffPlugInUnit` (what clients see) or become neutral; 12c decides.
- **P2 — light vs load.** A relay that switches only a light is better an `OnOffLight` (Google's advice, §4); `OnOffPlugInUnit` is for loads that aren't lights — socket, pump, fan, heater.
- **P3 — timed on.** LT makes `OnWithTimedOff` mandatory on a bridged unit (§2). Input for the `TimerRelay` / `onFor` decision: Matter already has "on for N" on every on/off unit, max ≈ 109 min. Either matter.js runs the countdown (16a sees only `SET onOff`), or 16a maps it to evok-node's own timer.
- **P4 — `StartUpOnOff`.** Mandatory attribute; a candidate for a template setting (12a §2.3), exposed read-only. Ecosystems mostly don't edit it (§4).

## 7. Sources

- S1 — connectedhomeip `data_model/1.5/device_types/` (OnOffPlug-inUnit, MountedOnOffControl, DimmablePlug-InUnit, MountedDimmableLoadControl, ElectricalSensor .xml); `data_model/1.7/` for revision 5: https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/data_model/1.5/device_types/OnOffPlug-inUnit.xml
- S2 — connectedhomeip `data_model/1.5/clusters/OnOff.xml`: https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/data_model/1.5/clusters/OnOff.xml
- S3 — matter.js generated device and cluster docs (spec 1.6.1 §5.1, §5.3; cluster §1.5): `packages/node/src/devices/on-off-plug-in-unit.ts`, `mounted-on-off-control.ts`, `packages/types/src/clusters/on-off.d.ts`: https://github.com/project-chip/matter.js/blob/main/packages/node/src/devices/mounted-on-off-control.ts
- S4 — matter.js `OnOffServer.ts`: https://github.com/project-chip/matter.js/blob/main/packages/node/src/behaviors/on-off/OnOffServer.ts
- S5 — connectedhomeip `docs/guides/darwin.md`: https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/docs/guides/darwin.md
- S6 — TP-Link community, "KS205 - No 'Display as' in Apple Homekit": https://community.tp-link.com/us/smart-home/forum/topic/671294
- S7 — Google Home Developers, Matter supported devices: https://developers.home.google.com/matter/supported-devices
- S8 — Home Assistant `components/matter/switch.py`, `select.py`: https://github.com/home-assistant/core/blob/dev/homeassistant/components/matter/switch.py
- S9 — automatous-io, Shelly 1 Gen4 Matter over Thread firmware: https://github.com/automatous-io/shelly-1-gen4-matter-thread
- S10 — Matter Alpha, Shelly On/Off Plug-in Units: https://www.matteralpha.com/category/smart-plug-on-off/shelly
