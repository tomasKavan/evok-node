# 12 — Fan, air purifier and heat recovery units

**Research, not design.** What Matter defines for Fan, Air Purifier and Extractor Hood, Fan Control and filter monitoring; how controllers show them; how other systems model a heat recovery unit; how well Matter's Fan fits one. Feeds 12c's `Fan` (M3.3: "fit for heat recovery units"). The 2VV unit and its Modbus interface are in [`../16-airgenio.md`](../16-airgenio.md).

Input from Tomas (2026-10-28): each flat has a 2VV Venus heat recovery unit with AirGENIO control on RS-485 to the flat's PLC; a dedicated driver is likely.

Spec data from the connectedhomeip data model `1.2`–`1.7` (S1); spec prose from matter.js model resources (S2).

## 1. Matter

### 1.1. Device types

| Device type | Since | Server clusters [V-src S1] | Notes |
|---|---|---|---|
| Fan `0x002B` | 1.0 | Identify, Groups, **Fan Control**; On/Off O | "typically standalone or mounted on a ceiling or wall and is used to circulate air in a room" [V-src S2]. Rev 2: "composed with a Thermostat for fan heaters"; rev 3: On/Off; rev 5 (1.7): Groupcast |
| Air Purifier `0x002D` | 1.2 | Identify, Fan Control; Groups, On/Off, **HEPA Filter Monitoring** `0x0071`, **Activated Carbon Filter Monitoring** `0x0072` — all O | "designed to clean the air in a room … has a fan … Optionally, it can report on the condition of its filters". May be composed with Air Quality Sensor, Thermostat, Temperature Sensor, Humidity Sensor [V-src S2]. Rev 4 (1.7): Humidity Conditioner |
| Extractor Hood `0x007A` | 1.3 | Fan Control (no `RCK`, `WND`, `DIR`); Identify, HEPA, carbon filter O | a kitchen hood; "extracting the air above the cooking surface or … recirculating and filtering it"; may contain a light [V-src S1, S2] |
| Room Air Conditioner `0x0072` | 1.0 | Fan Control O, filter monitoring O (1.5+) | see [11 §1.2](11-thermostat.md) |
| Thermostat `0x0301` | 1.0 | Fan Control as a **client** | see [11 §1.2](11-thermostat.md) |

- **No ventilation or heat recovery device type** exists in 1.0–1.7. None of the device type or cluster files contains "ventilation", "heat recovery", "ERV", "HRV" or "MVHR" outside the Closure clusters' vent position [V-src S1].
- New in 1.7: Humidity Conditioner, Humidistat cluster [V-src S1]. Not read further.

### 1.2. Fan Control `0x0202`

Revision 5 in 1.5; 7 in 1.7 (Zigbee leftovers removed; `On` and `Smart` modes obsolete; Q quality on `PercentCurrent`, `SpeedCurrent`) [V-src S1]. Features and attributes are in [11 §1.3](11-thermostat.md). The rules that matter here [V-src S2]:

| Rule | |
|---|---|
| `FanModeSequence` is fixed. `Low` is supported only if the sequence is < 4; `Medium` only for 0 or 2 | e.g. `OffHighAuto` (4) has no Low |
| `Auto` only with feature `AUT`. In Auto, `PercentSetting` and `SpeedSetting` are **null**; `PercentCurrent` "may vary across the range" | |
| Writing `FanMode` sets `PercentSetting`/`SpeedSetting`; writing `PercentSetting` sets `FanMode` | the mapping ("Percent Rules", §4.4.6.3.1): [GAP] |
| `PercentCurrent` may differ from the setting "due to other system requirements" — e.g. staying higher to dissipate heat | |
| A write the fan can't take now → `INVALID_IN_STATE`; a mode outside the sequence → `CONSTRAINT_ERROR`; a null write changes nothing | |
| "Attempting to set this attribute to Off may not be allowed by the system" when other clusters depend on the fan | |
| `Step(Increase/Decrease, Wrap, LowestOff)` — for a wall toggle; its effect is implementation-specific | |
| `AirflowDirection` Forward / Reverse | |

One `PercentSetting`, one `PercentCurrent`: Fan Control models **one** air stream [I].

### 1.3. On/Off with Fan Control

On/Off is independent of `FanMode` Off. With On/Off, Off keeps `FanMode`, `PercentSetting` and `SpeedSetting`; only `PercentCurrent`/`SpeedCurrent` go to 0. On restores the old speed. With `FanMode` Off the speed is lost [V-src S2 — Fan and Air Purifier device types].

Example: unit at 60 %, On/Off → false: `FanMode` Medium, `PercentSetting` 60, `PercentCurrent` 0. On/Off → true: back to 60 %.

### 1.4. Filter monitoring `0x0071`, `0x0072`

Both derive from Resource Monitoring [V-src S1]:

| Element | Values |
|---|---|
| Features | `CON` condition %, `WRN` warning, `REP` replacement product list |
| `Condition` + `DegradationDirection` | percent, Up or Down (`CON`) |
| `ChangeIndication` | OK, Warning (`WRN`), Critical |
| `InPlaceIndicator`, `LastChangedTime` | bool, epoch-s |
| `ResetCondition()` | command |

Listed on Air Purifier, Extractor Hood and RAC — not on Fan [V-src S1]. Example for a time-based filter: `Condition` = 100 − hours used / max hours × 100, `DegradationDirection` Down, `ChangeIndication` Critical when the unit reports "filter info" [I].

### 1.5. matter.js

- `FanControlServer` only defaults `fanMode` to Off; no coupling of mode, percent and speed [V-src S2]. The bridge must do the Percent Rules itself [I].
- Endpoint classes `FanDevice`, `AirPurifierDevice` exist (`devices/fan.ts`, `air-purifier.ts`) [V-src S2].

### 1.6. What Matter has no place for

For a heat recovery unit, all [I] from §1.1–§1.4:

- **Two fans.** Supply and extract run at separate levels (balance, night ventilation with the exhaust fan off).
- **Heat recovery state:** bypass, free cooling, frost protection.
- **Boost with a timer**, away/nonoccupied, fire mode.
- **Supply air temperature.** Only through a composed Thermostat — a second thermostat next to the room's.
- **Faults.** Fan Control has no fault or error attribute.
- **Filters on a Fan.** The cluster exists, but the Fan device type does not list it.

## 2. Controllers

| Controller | Fan | Air Purifier | Filter |
|---|---|---|---|
| Apple Home | supported (S9 via [README §2](README.md)). Speed control: an Apple forum answer "Looks like yes!" to whether Fan Control works [V S5]. A Fan gets "a single Oscillation toggle"; WindMode and the rock directions: "no, not currently" — Home maps Matter onto existing HomeKit properties (Jul 2026) [V S4] | since iOS 18 [V S6]. A purifier shows power, a 1–100 speed slider and "manual and auto options" [V S7] | [GAP] |
| Google Home | listed: Fan Control, On/Off (1.0) [V S8] | listed: Fan Control, On/Off, HEPA, carbon filter (1.2) [V S8] | as Air Purifier clusters [V S8]; UI: [GAP] |
| Home Assistant | a `fan` entity for **any** endpoint with Fan Control (`FanMode`, `PercentCurrent`, `PercentSetting`), whatever the device type. Presets low/medium/high/auto from `FanModeSequence`; natural/sleep wind with `WND`; oscillate with `RCK`; direction with `DIR`; On/Off taken as a mains power switch [V-src S3] | same entity | `Condition` → % sensor; `ResetCondition` → button [V-src S3] |
| SmartThings | [GAP] | [GAP] | [GAP] |

A bridge that exposes Home Assistant fans to Matter: "controllers are only offered the speeds and modes the HA fan actually accepts, no more phantom Medium or Auto"; "Apple no longer warns about fans, air purifiers and air quality" [V S18].

## 3. Real products

| Product | Declared as | Facts |
|---|---|---|
| AiDot Orein bath fan OA118 | Fan `0x002B`, Matter 1.3 | "Matter Smart Bathroom Fan with Light", certified 2025-09-09 [V S10] |
| Inovelli White Series fan switch | the Matter "Fan profile" | 3 speeds; ceiling or exhaust fans; Alexa doesn't support it [V S11] |
| Bosch Climate 7000i, Air 2000i/4000i/6000i | Matter | AC and air purifiers; no ventilation unit [V S12] |
| Vortice BRA.VO M / Q | HomeKit (not Matter) | decentralised units with heat recovery; accessory type not stated [V S13] |

- matter-survey.org saw 15 Fan products in Oct 2026 ([11 §3](11-thermostat.md)).
- **No heat recovery unit with Matter was found** — Zehnder, Vallox, Brink, Helios, Pluggit, Atrea, Aldes, 2VV included [GAP]. Ventilation makers connect over Modbus, KNX, their own apps or HomeKit [I].

## 4. How other systems model a heat recovery unit

| System | Model | Source |
|---|---|---|
| Home Assistant, Vallox | one `fan` entity "to control the entire unit": on/off, speed, **presets Home, Away, Boost, Fireplace** (Extra, Auto on newer firmware); actions to set each profile's fan speed; a switch locks the bypass; numbers for supply temperatures; sensors incl. filter life; a date for the filter change | [V S14] |
| Home Assistant, ComfoConnect (core) | `fan`: speeds 1–3 as percent; "away is not included in speeds and instead mapped to off"; preset `auto` | [V-src S15] |
| ComfoConnect (custom) | fan speed and auto/manual; selects for balance mode, bypass mode, temperature profile | [V S16] |
| Homebridge, Systemair | three speeds Low / Medium / High as fan %; target temperature | [V S17] |
| Loxone ventilation | presence and absence levels, timed boost (Stoßlüften), quiet pause, free cooling, timer, off; CO₂ and humidity; filter runtime | [V S19] |

Common pattern: **one fan-like control for the whole unit** (power, level, a few named modes), everything else as separate sensors, switches or selects [I].

## 5. Fit: Matter Fan for the AirGENIO unit

Register numbers from [16 §3](../16-airgenio.md).

| Unit function | Matter element | Fit |
|---|---|---|
| on / standby (21001) | On/Off | good — keeps the flow level, as §1.3 |
| manual level 20–100 % in 10 % steps (21002, ‰) | `PercentSetting`; optional `SPD` with `SpeedMax` 9 (20…100 %) | good; a value under 20 % needs a rule [I] |
| actual level (15013/15014) | `PercentCurrent` | partial — two fans, one value |
| DCV or evok-node demand control | `FanMode` Auto (`AUT`) | good |
| Low / Medium / High | `FanMode` with `OffLowMedHighAuto` | good, if the levels are fixed percentages [I] |
| boost (21009, timer) | — | none; `High` has no timer |
| nonoccupied (21010) | — | none (Fan has no presets) |
| night ventilation (21011) | — | none |
| fire, frost, bypass | — | none — and not for the user |
| filter (15044/15045, 21016) | HEPA Filter Monitoring | only on Air Purifier |
| temperatures EXT1, EXT3, INT1, INT2 | Temperature Sensor endpoints | good as composed endpoints [I] |
| supply setpoint (21003) | composed Thermostat | poor — a second thermostat in the flat |
| errors (15002–15004) | — | none |

**Fan vs Air Purifier** for the projection [I]:

| | Fan | Air Purifier |
|---|---|---|
| Meaning | "circulate air in a room" | "clean the air in a room" |
| Filter | not listed | HEPA / carbon filter monitoring |
| Composition | Thermostat | Air Quality, Temperature, Humidity Sensor, Thermostat |
| Apple Home | speed, oscillation | speed, manual/auto (§2) |

Neither means "ventilate a dwelling with heat recovery". Both carry power, level and auto, which is what users touch every day (§4).

## 6. Simple fans

Matter Fan fits fans on Unipi outputs directly [I]:

| Hardware | Matter |
|---|---|
| exhaust fan on one RO | `FanModeSequence` OffHigh; % 0 or 100 |
| three-speed fan on three ROs (one at a time) | OffLowMedHigh; % ↔ L/M/H |
| EC fan on an AO 0–10 V | % = AO; Auto only if something drives it |
| bath fan with run-on | Fan + a `TimerRelay` in a rule (12c-05) |

Today 12c-02 lists "a fan" as an `OnOffPlugInUnit` use [V 12c-02 §1] — Apple shows it as a plug, not a fan [I].

## 7. evok-node today

| Where | What |
|---|---|
| M3.3, 12c index | "`Fan` — fit for heat recovery units"; `Pump` deferred, a relay pump is an `OnOffPlugInUnit` |
| 12c-02 §1 | `OnOffPlugInUnit` "for a switched load that isn't a light — a socket, a fan, a heater, a small pump" |
| 12c-05 §1 | `TimerRelay`: "a fan that runs on" |
| 12c-10 | `RoomAirConditioner.fanMode` auto/low/medium/high (Fan Control on the RAC); `boost: { active, until? }` with `boostMin` |
| 12a §3a | bundles: one bridged device with child endpoints (e.g. `iaq-unipi`) |

## 8. Proposals for 12c (not binding)

- **P1 — `Fan` as a Matter-shaped home type** for simple fans: `onOff?`, `mode` (subset of off/low/medium/high/auto from a `modes` setting), `percent { setting, current }`, `direction?`. Templates over RO(s) and AO (§6). Matter Fan `0x002B`.
- **P2 — the heat recovery unit: two options.**
  - **A — one type with extras** (as `RoomAirConditioner` has `policy`, `boost` beyond Matter): `VentilationUnit` = `Fan` fields + `boost`, `away`, `nightVentilation`, `filter`, temperatures, `fault`. Only the Fan part is projected.
  - **B — a bundle**: a `Fan` + `TemperatureSensor`s (outdoor, supply, extract) + a filter state, as one bridged device with child endpoints (12a §3a).
  ```ts
  // option A, sketch
  interface VentilationUnitFields extends FanFields {
    boost:  { active: boolean; until?: Timestamp };     // 12c-10 naming
    away:   boolean;                                     // 21010
    nightVentilation: { enabled: boolean; active: boolean };   // 21011, 15000 bit 8
    filter: { conditionPct?: number; change: 'ok' | 'warning' | 'critical' };
    fault?: { code: string };
  }
  ```
- **P3 — project as Fan or Air Purifier.** Air Purifier brings filter monitoring and composed sensors; Fan matches the spec text better (§5). Check Apple's rendering of both with a real endpoint before deciding.
- **P4 — `Auto` = demand control.** Either the unit's DCV (needs an AQS wired to the unit) or evok-node's loop on the rooms' IAQ CO₂ writing the level ([16 P4](../16-airgenio.md)).
- **P5 — percent rule.** Below the unit's minimum: 0 → standby, 1–19 → 20 %; levels rounded to 10 % [I].
- **P6 — supply setpoint stays off Matter.** Room temperature belongs to the room thermostats (12c-10); the unit's setpoint is a commissioning value.

## 9. Gaps

- Fan Control "Percent Rules" table (spec §4.4.6.3.1).
- Apple Home: filter monitoring, Fan with `AUT`, Air Purifier composed sensors, `SPD` steps.
- Google Home and SmartThings UI for Fan and Air Purifier.
- Any heat recovery unit with Matter; how one would declare itself.

## 10. Sources

- S1 — connectedhomeip `data_model/1.2/`–`1.7/` at commit `8fd0af0` (2026-10-28): `device_types/Fan.xml`, `AirPurifier.xml`, `ExtractorHood.xml`, `RoomAirConditioner.xml`, `HumidityConditioner.xml`; `clusters/FanControl.xml`, `ResourceMonitoring.xml`: https://github.com/project-chip/connectedhomeip/tree/8fd0af079246c6bfddcedcafc12a74f5f8f8cbab/data_model
- S2 — matter.js `99a7747` (2026-10-28): `packages/model/src/standard/resources/fan-control.resource.ts`, `fan.resource.ts`, `air-purifier.resource.ts`, `extractor-hood.resource.ts`; `packages/node/src/behaviors/fan-control/FanControlServer.ts`; `packages/node/src/devices/fan.ts`, `air-purifier.ts`: https://github.com/matter-js/matter.js
- S3 — Home Assistant core `b6b5a86` (2026-10-28), `homeassistant/components/matter/fan.py`, `sensor.py`, `button.py`: https://github.com/home-assistant/core/tree/b6b5a86/homeassistant/components/matter
- S4 — Apple developer forum, "Apple Home missing Wind/Rock Mode controls for Matter Tower Fan" (Jul 2026): https://developer.apple.com/forums/thread/837127
- S5 — Apple developer forum, "Does the Home App support the Matter fan_control attribute?": https://developer.apple.com/forums/thread/743900
- S6 — Matter Alpha, "Apple finally supports air purifiers" (2024-09-21): https://www.matteralpha.com/news/apple-finally-supports-air-purifiers
- S7 — HomeKit News, SwitchBot Air Purifier Table review (2025-03-20): https://homekitnews.com/2025/03/20/switchbot-air-purifier-table-review/
- S8 — Google Home Developers, Matter supported device types: https://developers.home.google.com/matter/supported-devices
- S9 — connectedhomeip `docs/guides/darwin.md` — as [README](README.md) S2
- S10 — CSA, Orein bath fan OA118: https://csa-iot.org/csa_product/orein-bath-fan-oa118/
- S11 — Inovelli, White Series smart fan switch: https://inovelli.com/products/thread-matter-white-series-smart-fan-switch-3-speed-ceiling-on-off-exhaust
- S12 — Bosch Home Comfort, Matter for AC and air purifiers: https://www.bosch-homecomfort.com/de/de/wohngebaeude/unternehmen/presse/matter-geraeteintegration-fuer-bosch/
- S13 — HomeKit News, Vortice HomeKit ventilation (2020-10-23): https://homekitnews.com/2020/10/23/homekit-ventilation-system-announced-by-vortice/
- S14 — Home Assistant, Vallox integration: https://home-assistant.io/integrations/vallox
- S15 — Home Assistant core, `comfoconnect/fan.py` (mirror): https://git.sudo.is/home-assistant/core/src/branch/dev/homeassistant/components/comfoconnect/fan.py
- S16 — michaelarnauts, home-assistant-comfoconnect: https://github.com/michaelarnauts/home-assistant-comfoconnect
- S17 — homebridge-systemair-ventilator 1.1.14 README: https://unpkg.com/homebridge-systemair-ventilator@1.1.14/README.md
- S18 — RiDDiX, home-assistant-matter-hub README: https://github.com/RiDDiX/home-assistant-matter-hub
- S19 — Loxone, Lüftungssteuerung: https://www.loxone.com/dede/produkte/heizungssteuerung/lueftungssteuerung/
