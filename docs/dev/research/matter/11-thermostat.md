# 11 — Thermostat and room air conditioner

**Research, not design.** What Matter defines for Thermostat, Room Air Conditioner and Fan Control; how controllers and other systems run one room with several heat sources; the Samsung AC and Wolf boiler interfaces. Feeds 12c's `Thermostat` and `RoomAirConditioner`.

Input from Tomas (2026-10-25):

- A house with 4 flats and common areas. One shared Wolf gas boiler with an ISM8i and equitherm (weather-compensated) control; one mixer circuit per flat, 5 mixers in total.
- Rooms have radiators, some have floor-heating loops. Each radiator and each loop can get an electronic (thermal) valve, driven by the flat's Unipi Patron, not by the boiler.
- Each room has a Unipi IAQ (temperature, CO2). Many rooms have a Samsung WindFree Avant 2 split AC; the outdoor units have a Modbus unit.
- Experience: equitherm works well without valves (bedroom radiators are switched off). Users sometimes want to tweak the temperature a bit.
- Leaning to: one thermostat per room with a setpoint and a heat-source policy, and a separate device or cluster for the Samsung specialities.

Spec data from the connectedhomeip data model, `data_model/1.3/`–`1.7/` (S1); spec prose from matter.js's model resources, which cite Matter 1.6.1 (S5). The 1.5 wording may differ slightly.

## 1. Matter

### 1.1. Thermostat cluster `0x0201`

Cluster revision 6 (1.3), 8 (1.4), 9 (1.5), 10 (1.5.1), 11 (1.6), 12 (1.7) [V-src S1].

**Units:** setpoints and temperatures are in 0.01 °C. `MinSetpointDeadBand`, `LocalTemperatureCalibration` and the `SetpointRaiseLower` amount are in **0.1 °C** [V-src S1, S2, S4].

#### 1.1.1. Features

| Bit | Code | Meaning | Conformance [V-src S1] |
|---|---|---|---|
| 0, 1 | `HEAT`, `COOL` | heating, cooling | both mandatory with `AUTO`; otherwise at least one |
| 2 | `OCC` | occupancy | O |
| 3 | `SCH` | Zigbee schedules | deprecated in 1.5, obsolete in 1.7 |
| 4 | `SB` | setback | deprecated in 1.5.1, obsolete in 1.7 |
| 5 | `AUTO` | automatic heat/cool changeover | O |
| 6 | `LTNE` | local temperature not exposed | O |
| 7 | `MSCH` | Matter schedules (1.4+) | O |
| 8 | `PRES` | presets (1.4+) | O |
| 9 | `TEVT` | events (1.6+) | provisional |
| 10 | `TSUGGEST` | thermostat suggestions (1.6+) | O with `PRES` |
| 11 | `SENSORS` | scheduling of sensors (1.7) | provisional |

#### 1.1.2. Main attributes (1.5)

| ID | Attribute | Facts [V-src S1, S5] |
|---|---|---|
| `0x00` | `LocalTemperature` | nullable, read-only; with `LTNE` "shall always report null" |
| `0x01` | `OutdoorTemperature` | nullable, optional |
| `0x02` | `Occupancy` | bit 0 Occupied; `OCC` |
| `0x03`–`0x06` | `AbsMin/MaxHeat/CoolSetpointLimit` | fixed; defaults 7, 30, 16, 32 °C |
| `0x11` / `0x12` | `OccupiedCoolingSetpoint` / `OccupiedHeatingSetpoint` | write with **Operate**; defaults 26 / 20 °C |
| `0x13` / `0x14` | `Unoccupied…Setpoint` | `OCC` only |
| `0x15`–`0x18` | `Min/MaxHeat/CoolSetpointLimit` | write with Manage; user limits inside the Abs limits |
| `0x19` | `MinSetpointDeadBand` | `AUTO` only; default 2.0 °C (1.5+; 2.5 °C before), range 0–12.7 °C. "Optionally writeable. However any writes … shall be silently ignored" |
| `0x1A` | `RemoteSensing` | bits: LocalTemperature, OutdoorTemperature, Occupancy — the value comes from a remote sensor. With `LTNE`, setting bit 0 → `CONSTRAINT_ERROR` |
| `0x1B` | `ControlSequenceOfOperation` | mandatory; writes are "silently ignored" ⇒ in practice fixed |
| `0x1C` | `SystemMode` | mandatory; write with **Manage**, not Operate; "limited by the ControlSequenceOfOperation attribute" |
| `0x1E` | `ThermostatRunningMode` | Off 0, Cool 3, Heat 4; `AUTO` only |
| `0x29` | `ThermostatRunningState` | optional bitmap: Heat, Cool, Fan, **HeatStage2**, CoolStage2, FanStage2, FanStage3 |
| `0x10` | `LocalTemperatureCalibration` | int8, 0.1 °C; out-of-range write → SUCCESS and clamped |
| `0x23`, `0x24`, `0x52` | `TemperatureSetpointHold`, `…HoldDuration` (min, ≤ 1440; 1.7: ≥ 1), `SetpointHoldExpiryTimestamp` | optional; expiry = now + duration |
| `0x30`–`0x32` | `SetpointChangeSource` (Manual, Schedule, External), `…Amount`, `…Timestamp` | optional, read-only |
| `0x07` / `0x08` | `PICoolingDemand` / `PIHeatingDemand` | deprecated in 1.6, obsolete in 1.7 ([09 §1.5](09-water.md)) |

`SystemMode` values [V-src S1]: Off 0, Auto 1 (`AUTO`), Cool 3, Heat 4, EmergencyHeat 5, Precooling 6, FanOnly 7, Dry 8, Sleep 9. Off is "does not generate demand for Cooling or Heating"; Auto: "Demand is generated for either Cooling or Heating, as required" [V-src S1].

`ControlSequenceOfOperation` values [V-src S1]: CoolingOnly 0, CoolingWithReheat 1 (no Heat), HeatingOnly 2, HeatingWithReheat 3 (no Cool), CoolingAndHeating 4, CoolingAndHeatingWithReheat 5 ("All modes are possible"). A CoolingAndHeating thermostat "will usually support the Auto SystemMode" [V-src S5].

- CHIP checks a `SystemMode` write against the features only, not against `ControlSequenceOfOperation` [V-src S2]. matter.js rejects Heat under value 5 — against the spec text; likely a bug [V-src S4, I].
- The full spec table "SystemMode allowed per ControlSequence": [GAP].

#### 1.1.3. Rules

- **Deadband in `AUTO`:** a write does not fail; the server moves the other setpoint. "If [OccupiedHeatingSetpoint] is set to a value that is greater than (OccupiedCoolingSetpoint − MinSetpointDeadBand), the value of OccupiedCoolingSetpoint shall be adjusted to (OccupiedHeatingSetpoint + MinSetpointDeadBand)." Mirror rule for cooling and for the Unoccupied pair [V-src S5]. If the moved setpoint would leave its limits, CHIP pulls the written one back instead [V-src S2].
- **Limits:** a setpoint outside Min/Max limit → `CONSTRAINT_ERROR`. A limit write that conflicts with a setpoint moves the setpoint "by the minimum amount" [V-src S5].
- **Presets:** a client's setpoint change sets `ActivePresetHandle` to null [V-src S5].

Example, `AUTO`, deadband 2.0 °C [I — from the rule above]:

```
heat 21.00, cool 24.00
write heat = 23.00   →  heat 23.00, cool 25.00   (cool moved, write accepted)
```

#### 1.1.4. Presets (`PRES`, 1.4+)

| Element | Facts [V-src S1, S5] |
|---|---|
| `PresetTypes` `0x48` | fixed list, 1–7 types: `{PresetScenario, NumberOfPresets, PresetTypeFeatures: Automatic, SupportsNames}` |
| `NumberOfPresets` `0x4A` | fixed, ≥ 1 |
| `Presets` `0x50` | list of `{PresetHandle, PresetScenario, Name?, CoolingSetpoint, HeatingSetpoint, BuiltIn}`; write with Manage, **atomic write** only (`AtomicRequest` Begin / Commit / Rollback, timeout in ms) |
| `ActivePresetHandle` `0x4E` | nullable |
| `SetActivePresetRequest` `0x06` | Operate; null = no active preset |
| `PresetScenarioEnum` | Occupied 1, Unoccupied 2, Sleep 3, Wake 4, Vacation 5, GoingToSleep 6, UserDefined 254 |
| BuiltIn | "can be modified, but it cannot be deleted"; a new preset can't be BuiltIn |

Schedules (`MSCH`): `Schedules` `0x51`, atomic write, `SetActiveScheduleRequest` `0x05`. matter.js: "not implemented yet" [V-src S1, S4].

#### 1.1.5. AC attributes

All optional, write with Manage [V-src S1]:

| ID | Attribute | Values |
|---|---|---|
| `0x40` | `ACType` | Unknown, CoolingFixed, HeatPumpFixed, CoolingInverter, HeatPumpInverter |
| `0x41`, `0x47` | `ACCapacity`, `ACCapacityFormat` | uint16; BTUh only |
| `0x44` | `ACErrorCode` | bits: CompressorFail, RoomSensorFail, OutdoorSensorFail, CoilSensorFail, FanFail |
| `0x45` | `ACLouverPosition` | Closed 1, Open 2, Quarter 3, Half 4, ThreeQuarters 5 |
| `0x46` | `ACCoilTemperature` | nullable, read-only |

#### 1.1.6. Other elements

- `SetpointRaiseLower(Mode: Heat | Cool | Both, Amount int8 in 0.1 °C)`, Operate [V-src S1, S5].
- `EmergencyHeatDelta` `0x3A`: optional [V-src S1]. Its meaning (auxiliary heat): [GAP] — prose not read.
- **1.6:** thermostat suggestions (`AddThermostatSuggestion(PresetHandle, EffectiveTime, ExpirationInMinutes 30–1440)`, `ThermostatSuggestionNotFollowingReason` with `OngoingHold`, `Schedule`, `Occupancy`, …); events `SystemModeChange`, `SetpointChange`, `RunningStateChange`, `ActivePresetChange`, … (`TEVT`, provisional) [V-src S1]. Controllers "submit a time-bound suggestion tied to the thermostat's supported presets" [V S30].
- **1.7:** `CriticalFreezeProtection`, `CriticalOverheatProtection` (provisional); `SENSORS` (lists of remote sensors with node/endpoint/cluster, a sensor schedule); new provisional **Thermostat Mode cluster `0x0063`** (Mode Base, tags such as Auto, Quick, Quiet, Off, Cool, Heat) [V-src S1].

### 1.2. Device types

| Device type | Server clusters | Client clusters | Notes [V-src S1, S6] |
|---|---|---|---|
| Thermostat `0x0301` (rev 4 in 1.5) | Identify, Groups (if active), Thermostat; optional Thermostat UI Configuration, Energy Preference | **Fan Control**, Temperature Measurement, RH Measurement, Occupancy Sensing — all optional | Fan Control is a client here, not a server |
| Room Air Conditioner `0x0072` (rev 3) | Identify, **On/Off with `DF` (dead front)**, Thermostat; optional Groups, Scenes, HEPA / carbon filter monitoring (1.5+), Fan Control, Thermostat UI Configuration, Temperature and RH Measurement | — | optional child Temperature Sensor and Humidity Sensor |
| Heat Pump `0x0309` (1.4+) | Identify O; Power Source, Device Energy Management, Electrical Sensor (composed) | Thermostat O | an energy appliance, not a room unit |
| Fan `0x002B` | Identify, Groups, Fan Control; On/Off O (1.5+) | — | rev 2: "Added ability to be composed with a Thermostat for fan heaters" |
| Heating/Cooling Unit `0x0300` | — | — | only in 1.0–1.2; gone from 1.3+ |

**RAC and On/Off:** "the Off command of the On/Off cluster shall move the device into the 'dead front' state". With `DF`, other clusters "may respond with failures … INVALID_IN_STATE" and may set attributes to best-effort values [V-src S6]. No text found that Off changes `SystemMode` [GAP]. The table of best-effort values: [GAP].

### 1.3. Fan Control `0x0202`

Features: `SPD` multi-speed, `AUT` auto, `RCK` rocking, `WND` wind, `STEP`, `DIR` airflow direction — all optional [V-src S1].

| Attribute | Values [V-src S1] |
|---|---|
| `FanMode` | Off, Low, Medium, High, Auto (`AUT`); On and Smart deprecated |
| `FanModeSequence` | fixed: OffLowMedHigh, OffLowHigh, OffLowMedHighAuto, OffLowHighAuto, OffHighAuto, OffHigh |
| `PercentSetting` / `PercentCurrent` | 0–100 %; setting null in Auto (S7 cites spec 4.4.6.3) |
| `SpeedMax`, `SpeedSetting`, `SpeedCurrent` | `SPD` |
| `RockSupport` / `RockSetting` | bits RockLeftRight, RockUpDown, RockRound |
| `WindSupport` / `WindSetting` | bits SleepWind, NaturalWind |
| `AirflowDirection` | Forward, Reverse |
| `Step(Direction, Wrap, LowestOff)` | `STEP` |

matter.js `FanControlServer` does no coupling of mode, percent and speed [V-src S4].

### 1.4. Thermostat User Interface Configuration `0x0204`

`TemperatureDisplayMode` (Celsius, Fahrenheit; write Operate), `KeypadLockout` (0–5; Manage), `ScheduleProgrammingVisibility` (optional) [V-src S1].

### 1.5. matter.js `ThermostatServer`

- Implements all features except `MSCH`, `SCH` and `SB`; since 0.18 no feature is on by default [V-src S4].
- Deadband and limits: one pass mirroring CHIP `Setpoints::Fix()`; writes to `MinSetpointDeadBand` and `ControlSequenceOfOperation` are reverted [V-src S4].
- Presets validated as the spec; `setActivePresetRequest` also copies the preset's setpoints ("additionally to specification requirements!") [V-src S4].
- **External sensor:** `LocalTemperature` from a Temperature Measurement cluster on another endpoint, or from the state `externalMeasuredIndoorTemperature`; occupancy the same way. "RemoteSensing attribute need to be set correctly … by the developer" [V-src S4].
- Optional `useAutomaticModeManagement` derives running mode from temperature [V-src S4].
- `RoomAirConditionerDevice`: On/Off with `DeadFrontBehavior`, Identify, Thermostat (features chosen by the developer) [V-src S4].

### 1.6. What Matter has no place for

All [I], from §1.1–§1.3:

- **Which heat source to use.** No attribute for "radiators vs AC". The nearest elements are `ThermostatRunningState` (`Heat`, `HeatStage2`) — a report, not a choice — and `EmergencyHeat`, a separate `SystemMode`.
- **Valve opening:** `PIHeatingDemand` is gone in 1.7 ([09 §1.5](09-water.md)).
- **Samsung WindFree:** no match. `WND` (SleepWind, NaturalWind) is a fan pattern, not WindFree's closed vanes with micro-holes. Quiet, Fast and Eco could fit Thermostat Mode `0x0063` tags in 1.7, but that cluster is provisional.
- **Swing:** `RockSetting` RockUpDown / RockLeftRight fits; `ACLouverPosition` fits a fixed position.

## 2. Controllers

| Controller | Thermostat | Room Air Conditioner | Presets, fan |
|---|---|---|---|
| Apple Home | supported (S9, S3). Shows Heat, Cool, Auto, Off; FanOnly shows as Off; deadband only in the maker's app; automations "only work reliably in Auto mode" (Mysa) [V S19]. A bridge fix: "re-enable AutoMode for full HVAC thermostats to fix Apple Home active display", "use hvac_action for thermostatRunningState" [V S29] | not in darwin.md (S3); an Apple engineer earlier: "currently not supported" [V S10]. In 2026 it renders, with a bug: "Apple Home sends Cool instead of Auto for Matter Room AC device type (works correctly as Thermostat)", FB25164477 [V S11] | Presets in the UI: [GAP]. Apple has "not published any guidance on Matter thermostat support" [V S12]; Aqara W200 with `PRES` supports Adaptive Temperature [V S13, S14]. A compound Thermostat + Fan shows inconsistent tiles; a fan gets only an oscillation toggle [V S11] |
| Google Home | supported (Matter 1.0); trait TemperatureSetting, OccupancySensing with `OCC` [V S16, S17]. Shows Heat, Cool, Auto, Off; FanOnly as "Fan"; enforces the deadband (Mysa) [V S20] | not listed: "Device types other than the ones listed here are not officially supported" [V S16]; the Home APIs have a `RoomAirConditionerDevice` class [V S18] | Fan Control → FanSpeed [V S17]; presets: [GAP] |
| Home Assistant | `climate` entity for Thermostat and RAC. Off 0, heat_cool 1, cool 3, heat 4; Dry and FanOnly only for an allow-list of vendors ("The Matter spec is missing a feature flag"). `AUTO` → range of two setpoints. `hvac_action` from `ThermostatRunningState`. Setpoint writes go to Occupied only; min/max from Abs limits [V-src S7] | On/Off false → mode off; `turn_on` sends On first ("Dead front may reject mode writes") [V-src S7] | `PRES` → preset modes; scenario → name (home, away, sleep, …), user-defined by Name; "none" sends a null handle. `fan`: percent, FanModeSequence presets, natural/sleep wind with `WND`, oscillate = all of `RockSupport` or 0 [V-src S7] |
| SmartThings | mode list from `ControlSequenceOfOperation` and seen `SystemMode` values; deadband ÷ 10 [V-src S8] | profiles `room-air-conditioner…` with switch, thermostatMode, both setpoints, operating state, fan mode, fan speed %, **windMode**; no oscillation; Samsung's own RAC (VID 0x10E1) has its own profile [V-src S8] | no preset code [V-src S8] |

## 3. Real products

matter-survey.org (5512 devices seen): Thermostat `0x0301` 35–38 products, **Room Air Conditioner `0x0072` and Heat Pump `0x0309` "not yet seen"**, Fan 15 [V S21, S22].

| Product | Declared as | Facts |
|---|---|---|
| Google Nest Learning Thermostat 4th gen | Thermostat + Temperature and Humidity Sensor endpoints | `HEAT` only, `MinSetpointDeadBand`, `SetpointRaiseLower` [V S24] |
| Aqara Thermostat Hub W200 | Thermostat + bridged sensors | `HEAT`, `COOL`, `AUTO`, **`PRES`**; atomic writes; Matter 1.4 [V S25, S14] |
| Eve Thermo (radiator valve) | Thermostat | `HEAT` only; `LocalTemperatureCalibration`, `RemoteSensing`, Temperature Measurement client [V S26] |
| tado Smart Radiator Thermostat X | Thermostat + Humidity Sensor | `HEAT` only [V S27] |
| Midea_AC | **Thermostat**, not RAC | `COOL` only; On/Off and Fan Control (no features) on the same endpoint [V S23]; Midea window AC certified as `0x0301` [V S28] |
| TCL, Hisense ACs | Thermostat | in the survey's Thermostat list [V S22] |

ACs ship as Thermostat with On/Off and Fan Control on the same endpoint, not as RAC — likely for controller support [I]. ecobee, Netatmo, Danfoss Ally, LG, Daikin: not found [GAP].

## 4. One room, several sources

### 4.1. KNX room controllers

**Basic stage + additional stage** (Grundstufe / Zusatzstufe):

| Maker | Additional stage starts | Its control | Source |
|---|---|---|---|
| Gira 2100 | setpoint minus a "stage offset" (heating; plus in cooling); 0 = both stages together; a setpoint shift moves both | own algorithm: PI continuous, PI switching (PWM) or 2-point | [V S62] |
| Theben RAMSES 718 | "distance to main stage" 0–4 K, 0.5 K steps; base 21 °C, distance 1 K ⇒ 20 °C | P, band 1–8.5 K, % or PWM 3–30 min (default 5) | [V S64] |
| Siemens UP237K | by **output**: "sequence 2 starts from" 5–95 % of sequence 1, default 50 % | own output | [V S65] |
| KNX Association | offset "usually set around two degrees" | — | [V S66] |

Two triggers recur: a temperature offset below the setpoint, or stage 1 saturated [I].

**Heating/cooling changeover and dead zone:**

- Gira: automatic — cooling above the cooling setpoint, heating below the heating setpoint, nothing in between; a too narrow dead zone causes constant switching. Changeover by object ignores the dead zone [V S62].
- MDT: dead zone 1–10 K, default 2 K; cooling comfort = comfort + dead zone. Or independent setpoints, defaults heat/cool: comfort 21/23, standby 19/24, night 18/25 °C [V S63].
- Siemens 0.25–1.5 K, Theben 0–6 K; Theben stops cooling on a dew-point alarm [V S65, S64].

**Setpoint shift** (Sollwertverschiebung) — the "tweak a bit":

| Maker | Range | On a mode change | Source |
|---|---|---|---|
| Gira 2100 | limits set in ETS, 0.5 °C steps | shift **discarded** unless made permanent | [V S62] |
| Siemens | ±2, ±3, ±4 or ±5 K | — | [V S65] |
| Theben | ±1 to ±5 K; 0 resets | after night mode: keep or reset to 0 K | [V S64] |

**Modes:** DPT 20.102 HVAC mode: 0 Auto, 1 Comfort, 2 Standby, 3 Night, 4 Frost/heat protection; "the controller always reacts to the last value sent" [V S63, S66]. MDT defaults: standby −2 K, night −3 K, frost 7 °C, heat protection 35 °C [V S63]. A window contact forces frost/heat protection (Gira, Theben, Siemens with 4 contacts OR-ed and an optional 30 s delay) [V S62, S64, S65].

**PI presets per emitter** (Gira) [V S62]:

| Emitter | Xp | Tn | Output |
|---|---|---|---|
| Hot-water radiator | 5 K | 150 min | continuous or PWM 15 min |
| Underfloor heating | 5 K | 240 min | PWM 15–20 min |
| Split unit (heat/cool) | 4 K | 90 min | PWM 10–15 min |
| Fan convector | 4 K | 90 min | continuous |

- Theben radiator: 2.5 K / 90 min [V S64]. Theben's floor-heating value as read ("30 h") looks wrong — [GAP].
- Siemens: a PWM period not shorter than the drive's travel time [V S65]. MDT: 2-point is unsuitable for slow systems [V S68].

### 4.2. Loxone

| Block | Facts | Source |
|---|---|---|
| Intelligent Room Controller (IRC) | comfort heating 21°, cooling 23° (or one setpoint 22°); eco = 2° outside these; frost 5°, heat protection 28°. Modes: auto heat/cool, heat only, cool only | [V S70] |
| IRC, sources | up to **3 sources**, each heat, cool or both. Each mode has a **priority list**: demand goes to the first source that can deliver, **plus lower sources marked "cheap"**; option "use all sources at once". "Expensive" sources are "only requested when no higher-priority sources are available". No cooling source ⇒ no cooling in auto | [V S70, S69, S72, S75] |
| IRC outputs | 0–10 per source, or PWM 10–60 min | [V S70] |
| Heating and Cooling Controller | room demand = (target − actual) × area; changeover once valves are > 30 % open on average; heating blocked above 18° outdoor, cooling below 15° (48 h forecast average); stage 2 after 60 min, not below −6° outdoor | [V S72, S74] |
| AC Unit Controller | the AC regulates itself; the block sends targets from the IRC; hysteresis 0.5°; window contact pauses the unit (7200 s) | [V S71] |
| AC and the room sensor | with a room temperature connected, some brands get it **forwarded to the indoor unit** (Fujitsu, Gree, LG, Daikin P1P2); others keep their own sensor and get **setpoint compensation** (Daikin S21, Mitsubishi, Toshiba, Panasonic). The formula: [GAP] | [V S71] |
| Flow Temperature Calculator | per-room flow setpoint from a curve plus room deviation; outputs the highest; pump on when a valve is > 35 % open | [V S73] |

### 4.3. Heat pump + second source (dual fuel)

| Product | Choice of source | Source |
|---|---|---|
| Google Nest, dual fuel | **breakpoint** by outdoor temperature (default 30 °F ≈ −1 °C, set by hand); alternate heat **never runs together** with the heat pump; changeover timer 4 h; outdoor temperature from weather data | [V S76] |
| Google Nest, heat pump + aux | Heat Pump Balance: Max Comfort, Balanced, Max Savings, Off; aux upstage after 90 min | [V S76, S77] |
| ecobee, dual fuel | compressor min outdoor temp 25–40 °F (the changeover point); aux max outdoor temp ≥ 5 °F above; aux not simultaneous; compressor-to-aux delta 3 °F | [V S78] |
| Honeywell T6 Pro | compressor lockout (balance point) 5–60 °F; backup heat droop 2–15 °F; upstage timer 30 min–16 h | [V S81] |
| Daikin Altherma Hybrid (heat pump + gas) | economical mode uses entered gas and electricity prices: heat pump only, both, or boiler only | [V S86] |
| tado, radiator valves + Smart AC in one room | not documented; a V3+ device talks to one zone only | [GAP] S82–S85 |

Common pattern: an outdoor-temperature lockout, a time to upstage, a temperature droop, and usually no simultaneous run in dual fuel [I].

### 4.4. Home Assistant

| Integration | Facts | Source |
|---|---|---|
| `generic_thermostat` | one switch; `ac_mode` makes it a cooler; tolerances 0.3; presets away, comfort, eco, home, sleep, activity | [V S87] |
| `dual_smart_thermostat` | roles heater, cooler, fan, dryer, heat pump; a role may be a `climate` entity. Auto mode priority: safety → urgent (2× tolerance) → normal → fan → idle; keeps the chosen sub-mode until its goal | [V S89] |
| `dual_smart_thermostat`, second stage | the secondary heater starts after the primary was on for the whole `secondary_heater_timeout`; then the primary turns off unless `dual_mode`. If aux ran today, the next cycle starts with aux | [V-src S89] |
| Better Thermostat | radiator valves plus an optional cooler (AC); each preset has a heating min and a cooling max; the cooler gets the cooling target and is switched by the room sensor; the heating target is a hard floor | [V-src S90] |
| Versatile Thermostat | types over_switch (TPI), over_valve, over_climate (AC or TRV with its own control); no single entity mixing hydronic and AC | [V S88], [I] |

### 4.5. AC with its own sensor, room sensor elsewhere

| Method | How | Source |
|---|---|---|
| Forward the room temperature | the unit controls on the external value | Loxone for some brands [V S71] |
| Setpoint compensation, P | `S_AC = S_user − (T_room − T_AC)`. Example: set 22, room 20, AC reads 24 ⇒ AC set to 26 | Intesis Samsung gateway [V S45] |
| Setpoint compensation, PI | `error = T_set − T_room`; `acc += error·Δt` (halved on sign change with overheat protection), clamped; `offset = kp·error + ki·acc + k_ext·(T_room − T_out)`, clamped to ±`offset_max`; sent = `round(T_set + offset)` to the device step. Sent only if the change ≥ a threshold and a minimum period has passed | Versatile Thermostat `pi_algorithm.py` [V-src S88] |
| PI presets | light: kp 0.2, ki 0.05, k_ext 0.05, max 1.5; medium: 0.3, 0.05, 0.1, 2; strong: 0.4, 0.08, 0, 5 | [V S88] |
| Static offset | `heater_setpoint_offset`, `cooler_setpoint_offset` added to the target | dual_smart [V S89] |
| On/off by room sensor | AC set to the target, switched on/off when the room passes target ± tolerance | Better Thermostat cooler [V-src S90] |

### 4.6. Manual overrides and changes on the device

| System | Override lasts | Change on the device itself | Source |
|---|---|---|---|
| KNX | shift discarded on the next mode change (Gira), or kept | — | [V S62, S64] |
| Loxone IRC | comfort extension 1 h; app button until the next schedule entry, max 48 h | a manual change on the AC block counts as presence: comfort **for that day** | [V S69–S71] |
| tado | timer up to 12 h / until the next time block / until resumed | IR remote: [GAP] | [V S82, S83] |
| ecobee | 2 h, 4 h, until next activity, until changed, ask each time | — | [V S100] |
| Versatile Thermostat | `manual_override_duration_min` (0 = permanent); timed preset up to 24 h | "follow underlying temp changes": changes on the AC remote or TRV knob are taken over | [V S88] |
| dual_smart | — | `keep_alive` does not resync an IR AC after a press on its remote | [V S89] |

Three conventions: until the next switch point, a fixed timer, permanent until cancelled [I].

## 5. Weather-compensated heating with room valves

| Topic | Facts | Source |
|---|---|---|
| Reference room | with room influence, **all radiator valves in the reference room must be fully open** (Vaillant VRC 700; Wolf BM-2 the same) | [V S91, S57] |
| Setting the curve | open the valves in test rooms; lower the curve in 3 K steps, watch 2 weeks. Radiators: curve −5 K ≈ room −2.5 K; floor heating: −2 K ≈ −2 K. A curve too high is hidden by the valves ("everyone is satisfied") while losses rise | [V S92] |
| ⇒ | the curve just reaches the setpoint with open valves; room valves only correct downward — matching Tomas's experience | [I] |
| Pump mode | proportional pressure (Δp-v) with TRVs; constant pressure (Δp-c) with zone valves and floor-heating actuators | [V S97] |
| Overflow valve | with a Δp pump, remove or block it ("two control loops might have a disruptive influence"), but follow the boiler maker first; a fixed-speed pump needs it when valves close | [V S98] |
| All valves closed | an automatic bypass keeps a minimum flow for small gas boilers; closing valves can lead to "potentially dead heating pumps" | [V S99] |
| Wolf CGB-2 | "Kein Überströmventil" (pump spread control); overflow bridge kit and hydraulic separator are accessories. No Wolf rule found on zone valves on a mixer circuit | [V S59], [GAP] |
| Wolf MM module | MI02 caps the mixer flow temperature (floor protection), does not replace the maximum thermostat | [V S60] |
| Balancing | each floor circuit needs a balancing device (DIN EN 1264-4); Uponor autobalancing sets PWM duty by loop length (≈ 20 % short, ≈ 60 % long loop) | [V S93, S96] |
| Floor self-regulation | q = 8.92·(θ_floor − θ_room)^1.1 W/m²; floor 23 °C: ≈ 30 W/m² at room 20 °C, ≈ 20 W/m² at 21 °C | [V S93] |
| Floor time constant | "almost 10 hours" for a heavy room to reach setpoint after a 19 → 22 °C step; 2-point ±0.5 K control was 34–97 % of the time outside the band | [V S95] |
| Floor cooling + fan coil | Uponor: floor cooling starts "a couple of degrees below setpoint", the fan coil at setpoint | [V S96] |

Thermal actuators, PWM periods and valve exercise: [09 §4.3](09-water.md).

## 6. Samsung WindFree Avant 2 over Modbus

### 6.1. Interface chain

For the FJM multi-split actually installed, and corrections to §6.2, see [`../18-mim-b19n.md`](../18-mim-b19n.md): an FJM outdoor unit takes the MIM-B19N without a MIM-R10N; quiet and away (B+28, B+29) are EHS only.

| Fact | Source |
|---|---|
| MIM-B19N / MIM-B19NT: Samsung's Modbus RTU module, in the outdoor unit's electrical box, on R1/R2 and 12 V DC from the outdoor main board; indoor units stay on F1/F2. One outdoor system, up to 48 indoor units (address 0–47) | [V S31] |
| Its list of supported units: DVM/CAC indoor units, hydro kit, ERV, chiller, FCU, EHS — **RAC (wall splits) not listed** | [V S31] |
| WindFree Avant S2 sheet: "A MIM-R10N Interface is required to connect the Outdoor Unit (ODU) to the centralised controller" | [V S37] |
| MIM-R10N: a board in the outdoor unit (CN320), gives R1/R2 and 12 V DC to a module "such as the MIM-B19N" | [V S41] |
| A reseller: RAC "(AR18–24) require the separate MIM-R10N add-on board"; another: AR09–12 cannot be connected | [V S34, S40] — conflicts with S37, which names no size limit [I] |
| Likely setup: MIM-R10N + MIM-B19N per outdoor unit. The generation (S2 codes AR70F…) needs the nameplate | [I] |
| "Use of central control" (option SEG5) must be on in each indoor unit, else error E604. How to set it on a RAC: [GAP] | [V S31] |
| Samsung's own central controllers can't be used together with the MIM-B19N | [V S31] |
| RTU 9600 8E1; FC 03, 04, 06, 16; address 1–247 by DIP + rotary, read at power-up; ≥ 10 ms between commands | [V S31] |
| Practice: bursts made it ignore writes or return zeros; 50 ms gaps and staggered polling were stable | [V S33] |

### 6.2. Register map

PDU address = register number − 1. Per indoor unit: **B = 50 + 50·IU** (IU0 power at PDU 52) [V S31, S32].

| PDU | Name | R/W | Values [V S31] |
|---|---|---|---|
| 0 | module error | R | bits: address, R1/R2 comms, tracking |
| 1 | outdoor error code | R | 0 none, 100–999 |
| 2 | outdoor defrost | R | 0 or 0xFF = off, else defrost |
| 4… | custom outdoor values | R(/W) | NASA message IDs written to PDU 6000… with FC16 |
| B+0 | comms status | R | control works only at 7 (exists, type OK, ready) |
| B+2 | power | R/W | 0 off, 1 on |
| B+3 | mode | R/W | 0 Auto, 1 Cool, 2 Dry, 3 Fan, 4 Heat |
| B+4 | fan | R/W | 0 Auto, 1 Low, 2 Mid, 3 High |
| B+5 | up/down swing | R/W | 0 off, 1 on |
| B+6 / B+7 | filter alarm / clear | R / W | 1 = alarm / clear |
| B+8 | setpoint | R/W | °C ×10; cool 18–30, heat 16–30 ("Nordic models" heat 8–30) |
| B+9 | room temperature | R | °C ×10 |
| B+10 | discharge air temperature | R | °C ×10 |
| B+13 | indoor error code | R | 0 none, 100–999 |
| B+14 | remote-control restriction | R/W | write 0x0000 none, 0x6363 restrict |
| B+30 | WindFree | R/W | 0 none, 9 WindFree |
| B+32… | custom indoor values | — | NASA IDs written to PDU 7000… |

- Not in the table: left/right swing, Fast, Sleep, Eco, Quiet (EHS only), thermo-on, energy [V S31]. Reachable as custom NASA IDs: [I].
- Which sensor B+9 reports (return air or a wired remote); the real setpoint step on RAC (0.5 or 1 °C): [GAP].

NASA message IDs (ESPHome project) [V-src S44]: `0x4000` power, `0x4001` mode, `0x4006`/`0x4007` fan set/actual, `0x4011`/`0x407E` up-down/left-right swing, `0x4028` thermo on/off, `0x402E` indoor defrost, **`0x4060` alternative mode: sleep 1, quiet 2, fast 3, long-reach 6, eco 7, WindFree 9**, `0x4201` target, `0x4203` room temperature (ignored by the code), `0x4204` "modified current temp" (used as room temperature), `0x8204` outdoor temperature, `0x8235` error, `0x8413`/`0x8414` energy. Whether the MIM-B19N accepts these as custom writes: [GAP].

### 6.3. Room temperature from outside

- No MIM-B19N register for an external room temperature [V S31].
- Intesis Samsung gateway: register "ambient temperature from external sensor" is **not sent to the unit**; the gateway shifts the setpoint (formula in §4.5) [V S45].
- CoolMasterNet's temperature `feed` is not offered for Samsung [V S46]. ESPHome's `room_temperature_offset` only changes the reported value [V-src S44].

### 6.4. Remote, SmartThings, local changes

- The manual: users may operate the unit with a remote, so the BMS must poll the status. A holding register updates when the unit reports a change; every write is sent, also identical repeats [V S31].
- B+14 = 0x6363 restricts the remote; which inputs exactly (IR, SmartThings): [GAP] [V S31].
- Behaviour is last write wins; local changes are seen by polling and comparing with the last write [I].

### 6.5. Alternatives

| Option | Exposes | Limits | Source |
|---|---|---|---|
| ESPHome NASA bus (`esphome_samsung_hvac_bus`) | power, mode, fan, both swings, presets incl. WindFree, filter, room/outdoor temperature, errors, energy | needs F1/F2; some RAC models without comms wires don't work; no room temperature write | [V S44] |
| Intesis INMBSSAM001R000 | on/off, mode, fan, both vanes, setpoint, room temperature, window contact, remote disable, external temperature | commercial F3/F4 bus; RAC not named | [V S45] |
| CoolMasterNet | Samsung DVM lines | no temperature feed | [V S46] |

### 6.6. Heating performance (WindFree Avant S2)

| Size | 07 | 09 | 12 | 15 | 18 | 24 |
|---|---|---|---|---|---|---|
| Heating at +7 °C (kW) | 2.2 | 3.2 | 4.0 | 4.7 | 6.0 | 7.4 |
| Heating at −15 °C (kW) | 3.57 | 3.72 | 4.1 | 4.16 | 4.13 | 5.12 |
| SCOP (average climate) | 4.8 | 4.8 | 4.8 | 4.6 | 4.1 | 4.3 |

All [V S37]. Heating −15 to 24 °C outdoor, cooling −10 to 46 °C; R32. **WindFree is a cooling mode only**; other modes: Fast Cooling, Good Sleep, Eco, Quiet, auto changeover [V S37]. Defrost behaviour: [GAP].

## 7. Wolf ISM8i

Superseded for the driver by [`../19-ism8i.md`](../19-ism8i.md) — protocol, datapoints, BM-2/MM behaviour.

### 7.1. Protocol

- The ISM8i is the **TCP client**: it connects to one IP and port (default 12004) set in its web page; the integration is the server. One target only; a change needs the boiler fully powered off [V S52, S48].
- Pushes on change and periodically; every telegram must be acknowledged or it is re-sent up to 5 times. "Read all" service 0xD0, write 0xF0 0xC1; values in KNX DPTs [V S53, V-src S47, V S51].
- Covers up to 4 boilers, **mixer modules MM 1–3**, cascade, solar, ventilation; needs a BM-2 or AM [V S50, S56].

### 7.2. Datapoints per circuit

IDs: direct circuit / MK1 / MK2 / MK3 [V-src S47, S49]:

| IDs | Name | R/W | Values |
|---|---|---|---|
| 55 / 68 / 81 / 94 | room temperature | R | °C (from a BM-2 in the room) |
| 57 / 70 / 83 / 96 | program | **W** | 0 Auto, 1 heating (comfort), 2 standby, 3 economy |
| 59–61 / 72–74 / … | time programs 1–3 | W | 0/1 |
| 65 / 78 / 91 / 104 | **setpoint correction** (Sollwertkorrektur) | **W** | −4 … +4 K, 0.5 K steps |
| 66 / 79 / 92 / 105 | economy factor (Sparfaktor) | W | 0–10 K, 0.5 K |
| 368 / 369 / 370 / 371 | flow setpoint | R | °C, firmware 1.90+ |
| — / 116 / 123 / 130 | mixer flow temperature | R | °C |
| — / 117 / 124 / 131 | mixer pump | R | 0/1 |

Boiler: 8 outdoor temperature, 4 boiler temperature, 3 burner output %, 13 pressure; writable 198 output demand 0–100 % and 199 boiler temperature demand 0–89 °C [V-src S47].

- **Not available:** heating-curve slope, room influence, summer/winter threshold, comfort and eco room setpoints, holiday, mixer position [V-src S47, S49; V S58]. Summer/winter threshold (0–40 °C, default 20) is a BM-2 setting [V S57].
- **No room temperature input:** room temperature is output only; room influence needs a BM-2 in that room [V-src S49, V S57].
- **Mixer limit:** ISM8i: MK1–3; BM-2 system: up to 7 mixer modules [V-src S47, V S57]. Mixers 4 and 5 have no ISM8i datapoints [I]. With a cascade module, MM1 can't be used [V S56].

### 7.3. Integrations and issues

- Python `wolf_ism8` (used by Home Assistant): cache updated after a write without read-back; drops temperature jumps > 20 K [V-src S47, S48]. openHAB, ioBroker, FHEM, Node-RED bindings exist [V S51, S50, S52, S53].
- The ISM8i stops sending every 1–3 days in some installs; no updates after hours — fixed by a BM firmware 3.0 or a restart of the ISM [V S52, S54]. Zero-byte packets seen [V S52].
- Wolf's own ISM8i manual could not be fetched; IDs rest on source code and community CSVs [GAP].

## 8. evok-node today

| Where | What |
|---|---|
| 12a §2.2 | `RoomAirConditioner`: `onOff` · `mode` `off`/`cool`/`heat`/`auto`/`fan`/`dry` · one `setpoint` · `temperature` · `fanMode` `auto`/`low`/`medium`/`high` |
| 12c memo | `RoomAirConditioner`: "one `setpoint` vs Matter's heat/cool setpoints; source: extension-driver device or a new Modbus driver; Apple Home support unverified; designed with `Thermostat`". `Thermostat`: "one per room over a heater (thermal valve, 12c-08 §3.2) and an AC unit; AC specialities as extra devices or clusters; preference policy — AC or heater" |
| 12c-08 §3.2 | `thermal-valve-from-output`: `level` is a duty cycle; `periodS` 600, `minPulseS` 30, `travelS` 180, exercise every 7 days for 300 s; `normallyOpen` default false |
| 09 P5 | either the valve has a `level` and `Thermostat` drives it, or `Thermostat` owns the duty cycle |

## 9. Proposals for 12c (not binding)

- **P1 — one `Thermostat` per room.** It holds the intent: mode, setpoints, preset. Valves and the AC are its members, not peers. Matter: Thermostat `0x0301`; `ControlSequenceOfOperation` HeatingOnly for a room without AC, CoolingAndHeating with AC; `AUTO` only with a cooling source (Loxone: no cooling source ⇒ no auto, §4.2).
- **P2 — source policy, own field.** Matter has no place for it (§1.6):

  ```ts
  heatSource: 'hydronic' | 'ac' | 'hydronicThenAc' | 'acThenHydronic' | 'auto'
  stage2:     { offsetK: 1.5, afterMin: 60 }     // KNX ~2 K, Loxone 60 min, Nest 90 min
  auto:       { acBelowOutdoorC?: number, acAboveOutdoorC?: number }   // dual-fuel breakpoint
  ```

  `ThermostatRunningState` shows the second stage as `HeatStage2` [I]. The hydronic source is unavailable in boiler summer mode — from ISM8i (§7.2) or a setting.
- **P3 — hydronic only trims down.** A valve closes when the room is above the heating setpoint; the curve is set so open valves just reach it (§5). Raising a room beyond the curve: the AC, or setpoint correction ±4 K on MK1–3 (§7.2) — a flat-level rule, not a room one. Mixers 4–5 have no such datapoint.
- **P4 — keep flow.** At least one circuit per flat stays open, or a bypass exists (§5). A flat-level rule; hardware question for the installer.
- **P5 — cooling lockout.** No AC cooling while a hydronic valve in the room is open; a dead zone ≥ 2 K between heat and cool setpoints (MDT default, Matter default 2.0 °C).
- **P6 — the AC runs on the room sensor by setpoint compensation.** No external-temperature register (§6.3). PI as Versatile Thermostat (§4.5); clamp to 16–30 °C (heat) / 18–30 °C (cool); write only on a change ≥ the unit's step and after a minimum period; ≥ 50 ms between Modbus requests (§6.1).
- **P7 — changes from the AC's remote.** Poll, compare with the last write. Options: take it over as an override with an end time (tado, ecobee), "comfort for the day" (Loxone), or lock the remote with B+14 = 0x6363. A setting per room.
- **P8 — user tweak = setpoint shift.** ±N K around the scheduled setpoint (KNX ±2…±5 K), discarded at the next switch point or after a timer (§4.6). Matter: `SetpointRaiseLower`; optional `TemperatureSetpointHold` + `HoldDuration`.
- **P9 — presets.** Matter `PRES` with Occupied / Unoccupied / Sleep / Vacation ≈ KNX comfort / standby / night / frost. Home Assistant shows them; Apple and Google: unknown (§2).
- **P10 — Samsung extras as their own device.** `SamsungAc`: `fanMode` (B+4), `swingUpDown` (B+5), `swingLeftRight` (NASA `0x407E`), `windFree` (B+30, cooling only), `altMode` sleep / quiet / fast / eco (NASA `0x4060`), `filterAlarm` + `clearFilter`, `errorCode`, `defrost`, `outdoorTemperature`. Not exposed to Matter on its own; a fan could be Fan Control on the room's endpoint (Midea does this, §3, although the Thermostat device type lists Fan Control only as a client, §1.2).
- **P11 — `RoomAirConditioner` stays the raw AC.** It is a member of the room `Thermostat`; not projected to Matter when a Thermostat uses it. RAC is rare in the field and has an Apple bug (§2, §3). A room with only an AC still projects as Thermostat.
- **P12 — drivers.** Samsung: a Modbus RTU device over MIM-B19N, 9600 8E1, slow polling budget. Wolf: a TCP server for the ISM8i that ACKs every telegram, sends "read all" on connect and has a watchdog for the silent drop (§7.3).
- **P13 — duty-cycle period per emitter.** Gira: floor 15–20 min, radiator 15 min (§4.1) vs `periodS` 600 in 12c-08. A default per emitter type in the template.

## 10. Gaps

- Apple Home and Google Home: presets in the UI; Apple's RAC state beyond the Auto → Cool bug.
- Matter spec table SystemMode × ControlSequence; RAC dead-front best-effort values; `EmergencyHeatDelta` meaning.
- Samsung: MIM-R10N on 09/12 sizes; setting SEG5 on a RAC; the sensor behind B+9; the setpoint step; custom NASA writes (alt mode, left/right swing) through the MIM-B19N; what 0x6363 locks.
- Wolf: the official ISM8i datapoint manual; zone valves on a mixer circuit; whether the Wolf Link covers mixers 4–5.
- tado and Netatmo with radiators and an AC in one room; Loxone's compensation formula.
- Floor heating without setback: a maker's figure.

## 11. Sources

- S1 — connectedhomeip `data_model/1.3/`–`1.7/` at commit `7aaf318` (2026-10-25): `clusters/Thermostat.xml`, `FanControl.xml`, `ThermostatUserInterfaceConfiguration.xml`, `Mode_Thermostat.xml`; `device_types/*.xml`; `globals/*.xml`: https://github.com/project-chip/connectedhomeip/tree/7aaf31886bc87365b701a44588c70f7c2a5c87c2/data_model
- S2 — connectedhomeip, same commit, `src/app/clusters/thermostat-server/`: https://github.com/project-chip/connectedhomeip/tree/7aaf31886bc87365b701a44588c70f7c2a5c87c2/src/app/clusters/thermostat-server
- S3 — connectedhomeip, same commit, `docs/guides/darwin.md`
- S4 — matter.js `6ff7bc0` (v0.18.0): `packages/node/src/behaviors/thermostat/ThermostatServer.ts`, `devices/room-air-conditioner.ts`, `behaviors/fan-control/FanControlServer.ts`, `CHANGELOG.md`: https://github.com/matter-js/matter.js
- S5 — matter.js, same commit, `packages/model/src/standard/resources/thermostat-cluster.resource.ts` (spec 1.6.1 prose)
- S6 — matter.js, same commit, `resources/room-air-conditioner-device.resource.ts`, `elements/heat-pump.element.ts`, `resources/on-off.resource.ts`
- S7 — Home Assistant core `0f0aeae`, `homeassistant/components/matter/` (`climate.py`, `fan.py`, `number.py`, `sensor.py`, `binary_sensor.py`, `select.py`, `switch.py`): https://github.com/home-assistant/core/tree/0f0aeae2ee29e26214bcd6b078b807c8fb5873ef/homeassistant/components/matter
- S8 — SmartThings Edge drivers `3c3946ec`, `drivers/SmartThings/matter-thermostat/`: https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/3c3946ec07a708837c1d4dc046c62390d20632c8/drivers/SmartThings/matter-thermostat
- S9 — Apple Support, Matter accessories: https://support.apple.com/en-us/102135
- S10 — connectedhomeip issue #32867: https://github.com/project-chip/connectedhomeip/issues/32867
- S11 — Apple developer forum, Room AC sends Cool instead of Auto: https://developer.apple.com/forums/thread/851099
- S12 — Apple developer forum, Matter thermostat guidance: https://developer.apple.com/forums/thread/826939
- S13 — Matter Alpha, Apple Home Adaptive Temperature with a Matter thermostat: https://www.matteralpha.com/how-to/how-to-use-apple-home-adaptive-temperature-with-your-matter-thermostat
- S14 — Aqara W200 launch: https://secure.businesswire.com/news/home/20260407882593/en/Aqara-Launches-Thermostat-Hub-W200-in-the-North-American-Market
- S15 — Apple, Matter Accessory Best Practices for Apple Home: https://developer.apple.com/apple-home/downloads/Matter-Accessory-Best-Practices-for-Apple-Home.pdf
- S16 — Google Home, supported Matter device types: https://developers.home.google.com/matter/supported-devices
- S17 — Google Home, Matter clusters: https://developers.home.google.com/matter/clusters
- S18 — Google Home APIs, `RoomAirConditionerDevice`: https://developers.home.google.com/reference/kotlin/com/google/home/matter/standard/RoomAirConditionerDevice
- S19 — Mysa, Matter pairing with Apple Home: https://help.getmysa.com/articles/8694462671-matter-pairing-apple-home
- S20 — Mysa, Matter pairing with Google Home: https://help.getmysa.com/articles/9079106768-matter-pairing-google-home
- S21 — matter-survey, device types: https://matter-survey.org/device-types
- S22 — matter-survey, Thermostat: https://matter-survey.org/device-types/769
- S23 — matter-survey, Midea_AC: https://matter-survey.org/device/midea_ac-4492-8226
- S24 — matter-survey, Nest Learning Thermostat 4th gen: https://matter-survey.org/device/nest-learning-thermostat-4th-gen-24582-13
- S25 — matter-survey, Aqara W200: https://matter-survey.org/device/aqara-thermostat-hub-w200-4447-18433
- S26 — matter-survey, Eve Thermo: https://matter-survey.org/device/eve-thermo-4874-79
- S27 — matter-survey, tado X: https://matter-survey.org/device/tado-smart-radiator-thermostat-x-4942-1
- S28 — CSA, Midea window air conditioner: https://csa-iot.org/csa_product/midea-window-air-conditioner-17/
- S29 — home-assistant-matter-hub v2.0.17 release notes: https://newreleases.io/project/github/RiDDiX/home-assistant-matter-hub/release/v2.0.17
- S30 — MacRumors, Matter 1.6: https://www.macrumors.com/2026/06/17/matter-1-6-specification/
- S31 — ZimKev/MIM-B19n_Modbus `3ac51c0`, incl. the scanned MIM-B19N/NT manual DB68-07538A-02: https://github.com/ZimKev/MIM-B19n_Modbus
- S32 — TapHome, Samsung MIM-B19N template: https://taphome.com/en/compatibility/samsung-mim-b19n-iu/
- S33 — OpenEnergyMonitor forum, MIM-B19N read/write issues: https://community.openenergymonitor.org/t/modbus-read-write-issues-with-samsung-mim-b19n-and-siemens-logo-plc/29910
- S34 — Quality Heating, Samsung Modbus interface: https://qualityheating.co.uk/products/samsung-modbus-interface-for-external-bms-systems-and-homely-thermostats
- S35 — ManualsLib, MIM-B19N (preview only): https://www.manualslib.com/manual/3309854/Samsung-Mim-B19n.html
- S36 — Samsung, WindFree Avant S2 product page: https://samsung-climatesolutions.com/gb/b2c/products/rac/windfree-avant-s2.html
- S37 — Samsung, WindFree Avant / Avant S2 product information sheet: https://samsung-climatesolutions.com/content/dam/dtnl-aem-samsung-seace/gb/en-gb/pi-sheets/rac/RAC%20PI%20-%20WindFree%20Avant%20Black%20+%20Avant%20S2.pdf
- S38 — Samsung, WindFree Elite S2 sheet: https://samsung-climatesolutions.com/content/dam/dtnl-aem-samsung-seace/gb/en-gb/pi-sheets/rac/RAC%20PI%20-%20WindFree%20Elite%20S2.pdf
- S39 — Samsung, WindFree Comfort S2: https://samsung-climatesolutions.com/gb/b2c/products/rac/windfree-comfort-s2.html
- S40 — Klimux, MIM-R10N: https://www.klimux.com/Samsung-MIM-R10N-Zusatzplatine
- S41 — MIM-R10N manual: https://www.manua.ls/samsung/mim-r10n/manual
- S42 — The Future Life, MIM-R10N: https://shop.thefuturelife.co.uk/products/mim-r10n
- S43 — Klimaworld, MIM-A00N: https://www.klimaworld.com/products/samsung-interface-pcb-mim-a00n-fur-kabelfernbedienung
- S44 — omerfaruk-aran/esphome_samsung_hvac_bus `fe08cb0` (`protocol_nasa.h/.cpp`, `samsung_ac_device.h`, wiki): https://github.com/omerfaruk-aran/esphome_samsung_hvac_bus
- S45 — Intesis INMBSSAM001R000 user manual: https://www.mouser.com/datasheet/2/1422/user_manual_inmbssam001r000-2950292.pdf
- S46 — CoolMaster PRM: https://support.coolautomation.com/hc/en-us/articles/7068465434397-CoolMaster-PRM-Programmers-Reference-Manual
- S47 — marcschmiedchen/wolf_ism8 `2276211` / PyPI 4.3: https://github.com/marcschmiedchen/wolf_ism8
- S48 — marcschmiedchen/home-assistant-wolf_ism8 `eb1f224`: https://github.com/marcschmiedchen/home-assistant-wolf_ism8
- S49 — qyqsoft/ISM8I `f6cd063` (`wolf_datenpunkte_15.csv`, `wolf_writepunkte_15.csv`): https://github.com/qyqsoft/ISM8I
- S50 — ioBroker.wolf `c1cc8f2`: https://github.com/ioBroker/ioBroker.wolf
- S51 — openHAB ISM8 binding: https://v51.openhab.org/addons/bindings/ism8/
- S52 — tips-und-mehr.de, ISM8i with FHEM: https://tips-und-mehr.de/wolf-heizanlagen-mit-ism8i-schnittstellenmodul-ueberwachen-und-in-fhem-auswerten/
- S53 — Node-RED flow, Wolf ISM8: https://flows.nodered.org/flow/5c7e55491a89d5bb74fcbbca4b2ba0df
- S54 — openHAB community, ISM8 no updates: https://community.openhab.org/t/ism8-binding-no-updates-after-a-few-hours/135664
- S55 — KNX-User-Forum, Wolf over KNX: https://knx-user-forum.de/forum/öffentlicher-bereich/knx-eib-forum/1508916-wolf-heizung-und-lüftung-über-knx-steuern?p=1912704
- S56 — Wolf KNX ISM8 manual 3064244 (ManualsLib): https://www.manualslib.de/manual/1211750/Wolf-Knx-Ism8.html
- S57 — Wolf BM-2 Betriebsanleitung 3063305: https://static1.wolfeu.website.svc.wolf.eu/public/assets/editors/de-de/professionals/wissensmanagement/campus/seminarunterlagen/11-wrs-2/betriebsanleitung-bm-2_3063305_202311_web.pdf
- S58 — FHEM forum, ISM8i datapoints: https://forum.fhem.de/index.php?topic=129489.0
- S59 — Wolf CGB-2-38/55 datasheet: https://www.meinhausshop.de/media/pdf/14_003_86--DBL-01-de.pdf
- S60 — Wolf MM mixer module (ManualsLib): https://www.manualslib.de/manual/1286458/Wolf-Mm.html
- S61 — TapHome, IntesisBox SM-RC-MBS-1 (not read): https://taphome.com/en/compatibility/intesisbox-sm-rc-mbs-1/
- S62 — Gira KNX controller 2100/2101 manual: https://partner.gira.com/data3/21003490.pdf
- S63 — MDT SCN-RTRGx.02 application description: https://www.siblik.com/fileadmin/mam/medias/docus/123/MDTSCN-RTRGW.02_MDTSCN-RTRGS.02_Applikationsbeschreibung.pdf
- S64 — Theben RAMSES 718 manual: https://theben.de/ocsmedia/optimized/full/o11454v42_RAMSES_718_Handbuch.PDF
- S65 — Siemens UP237K/UP254K application program: https://knx-td.sihub.siemens.com/en/apb/803002_UP237K_UP254K_APB_e-2014-02-28.pdf
- S66 — KNX Association, best practice heating control part 2: https://knx.org/news/best-practice-heating-control-knx-part-2
- S67 — Gira Stetigregler 566: https://partner.gira.de/data3/05661110.pdf
- S68 — MDT heating actuators, operating modes: https://www.mdt.fr/fileadmin/user_upload/user_upload/download/MDT_LSG_Heizungsaktoren_Betriebsarten_und_Zusatzfunktionen.pdf
- S69 — Loxone IRC v2: https://www.loxone.com/enen/kb/irc-v2/
- S70 — Loxone Intelligent Room Controller: https://www.loxone.com/enen/kb/intelligent-room-controller/
- S71 — Loxone AC Unit Controller: https://www.loxone.com/enen/kb/ac-control/
- S72 — Loxone Heating and Cooling Controller: https://www.loxone.com/enen/kb/climate-controller/
- S73 — Loxone Flow Temperature Calculator: https://www.loxone.com/enen/kb/intelligent-temperature-controller/
- S74 — Loxone Config 15.1: https://www.loxone.com/enen/blog/config-15-1/
- S75 — Loxone V10: https://www.loxone.com/enen/?p=52069
- S76 — Google Nest heat pump configuration guide Q2-26: https://services.google.com/fh/files/helpcenter/nest_thermostat_heat_pump_configuration_guide_q2_26.pdf
- S77 — Google Nest, Heat Pump Balance: https://support.google.com/googlenest/answer/9248719?hl=en
- S78 — ecobee4 dual-fuel installation guide: https://berkeleyelectric.coop/sites/default/files/documents/ecobee4-thermostat-dual-fuel-systems-installation%20guide%200820.pdf
- S79 — BPA, ecobee PTCS settings: https://www.bpa.gov/-/media/Aep/energy-efficiency/residential/residential-ptcs-essentials/ecobee-3-4-5.pdf
- S80 — aphyr, ecobee settings for heat pumps: https://aphyr.com/posts/370-ecobee-settings-for-heat-pumps-with-resistive-aux-heat
- S81 — Honeywell T6 Pro, installer setup: https://docs.honeywellhome.com/t6-pro-ii/en-us/Content/Installation-Instructions/5. Installer Setup (ISU).htm
- S82 — tado, AC manual control: https://support.tado.com/en/articles/9527353-can-i-adjust-my-smart-ac-control-manually-in-the-tado-app-how-long-does-this-manual-change-stay-active
- S83 — tado, heating manual control: https://help.tado.com/en/articles/3405566-can-i-adjust-the-temperature-manually-on-my-app-how-long-does-this-manual-change-stay-active
- S84 — tado, zone controller: https://support.tado.com/en/articles/4689126
- S85 — tado, Smart AC Control: https://www.tado.com/en/products/ac
- S86 — Daikin Altherma Hybrid user guide: https://www.bury.gov.uk/asset-library/daikin-altherma-hybrid-userguide-ukepcen21-976-final.pdf
- S87 — Home Assistant, generic_thermostat: https://www.home-assistant.io/integrations/generic_thermostat/
- S88 — jmcollin78/versatile_thermostat `9059bc9`: https://github.com/jmcollin78/versatile_thermostat
- S89 — swingerman/ha-dual-smart-thermostat `8f8424c`: https://github.com/swingerman/ha-dual-smart-thermostat
- S90 — KartoffelToby/better_thermostat `b86561f`: https://github.com/KartoffelToby/better_thermostat
- S91 — Vaillant multiMATIC VRC 700/6 installation manual: https://kontakt.vaillant.de/documents/download/1439590
- S92 — SwissEnergy, set the heating curve: https://pubdb.bfe.admin.ch/en/publication/download/9982
- S93 — Oventrop Unibox brochure: https://www.oventrop.com/de-DE/file/i/be8841db-053e-4f4f-a8af-4aa6f84d9d2c?Download=1
- S94 — Chalmers, self-regulating floor heating: https://research.chalmers.se/en/publication/73021
- S95 — DTI/Aalborg, floor-heating control strategies, appendix E: https://www.teknologisk.dk/_/media/72104_Appendix%20E%20-%20Control%20strategies%2C%20algorithms%20and%20simulation%20results.pdf
- S96 — Uponor Smatrix technical information v6: https://brandportal.uponor.com/m/130acd4eb93386b/original/TI-Smatrix-EN-1116265-v6.pdf
- S97 — Grundfos ALPHA, guided commissioning: https://www.grundfos.com/us/learn/ecademy/all-courses/alpha-and-upse-circulators-for-residential-heating/guided-commissioning--alpha-
- S98 — Grundfos FAQ, overflow valves: https://www.grundfos.com/gh/support/faq/how-do-i-proceed-if-i-want-to-install-a-differential-pressure-regulated-heating-pump-in-an-existing-system-with-overflow-valves
- S99 — Danfoss automatic bypass (AVDO): https://designcenter.danfoss.com/products/climate-solutions-for-heating/radiator-thermostats/other-products-for-radiator-thermostats/automatic-bypass-controls
- S100 — ecobee Hold Action: https://www.techsolutions.support.com/how-to/how-to-set-hold-action-duration-on-ecobee-thermostat-12337
