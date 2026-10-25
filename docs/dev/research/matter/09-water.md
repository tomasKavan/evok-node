# 09 — Water: valve and leak detector

**Research, not design.** What Matter defines for Water Valve and Water Leak Detector, what controllers and real products do with them, and how other systems run valves and leak inputs. Feeds 12c's `WaterValve` and `WaterLeakDetector` sections.

Input from Tomas (2026-10-25):

- Valve hardware: a solenoid valve on one relay; a thermal actuator (radiator, floor heating).
- Uses: irrigation zones, heating circuits, filling water tanks, a 3-way valve that bypasses the water descaler.
- Leak sources: a leak module wired to a DI; Matter leak sensors (`matter` origin, 12a §4a).

Spec data from the connectedhomeip data model, `data_model/1.3/`–`1.7/` (S1); spec prose from matter.js's generated docs, which cite Matter 1.6.1 (S2).

## 1. Matter

### 1.1. Water Valve `0x0042`

Since 1.3. Simple device, endpoint scope. Identify and Valve Configuration and Control `0x0081` mandatory; Flow Measurement `0x0404` optional as server ("report the measured flow through the valve") and as client ("via binding to close a control loop of flow") [V-src S1, S2]. Unchanged 1.5–1.7 [V-src S1].

Device-level rules [V S2]:

- **Start-up:** "currently not specified and is considered manufacturer specific … what is considered the 'safe state' … is defined by the manufacturer."
- **Restart:** "strongly recommended to only perform the update/restart when the valve is in its closed state, as well as ignoring any open request during this update/restart".

### 1.2. Valve Configuration and Control `0x0081`

Features: `TS` TimeSync (only with the Time Synchronization cluster) and `LVL` Level ("capable of being adjusted to a specific position, as a percentage") [V-src S1, S2].

| Element | Type | Facts [V-src S1, V S2] |
|---|---|---|
| `OpenDuration` | `elapsed-s`, nullable, min 1 | duration of the current opening; null = "remain open until closed by the user or some other automation" |
| `DefaultOpenDuration` | `elapsed-s`, nullable, min 1, writable (*operate*), non-volatile | used when `Open` has no `OpenDuration`; null = no auto-close |
| `RemainingDuration` | `elapsed-s`, nullable, quieter reporting | null when `OpenDuration` is null or the valve is closed. At 0 the valve "shall automatically transition to its closed position". Reported only on null↔value, on reaching 0, on an increase or a changed closing time — "clients SHOULD NOT rely on the reporting" |
| `AutoCloseTime` | `epoch-us`, nullable — `TS` only | UTC close time; adjusted when UTC time is set |
| `CurrentState` | enum, nullable | `Closed` 0, `Open` 1, `Transitioning` 2 ("between closed and open positions or between levels"); null = not known |
| `TargetState` | enum, nullable | null = "no target position is set, since the change in state is either done or failed" |
| `CurrentLevel`, `TargetLevel` | `percent`, nullable — `LVL` | 0 = fully closed, 100 = fully open; `CurrentLevel` "SHOULD" follow the movement. 1.7 adds quieter reporting to `CurrentLevel` (cluster revision 2) |
| `DefaultOpenLevel` | `percent` 1–100, default 100, writable — optional with `LVL` | level for an `Open` without `TargetLevel` |
| `LevelStep` | uint8 1–50, fixed — optional with `LVL` | e.g. 15 ⇒ 0, 15, 30 … 90, 100; 0 and 100 always supported |
| `ValveFault` | bitmap, optional | `GeneralFault`, `Blocked`, `Leaking`, `NotConnected`, `ShortCircuit`, `CurrentExceeded` |
| `Open(OpenDuration?, TargetLevel?)` | command, *operate* | both fields optional; `TargetLevel` min 1, `LVL` only |
| `Close()` | command, *operate* | — |
| `ValveStateChanged(ValveState, ValveLevel?)` | event, optional | for a state change "when the new state has been reached"; for a level, "after the end of movement" |
| `ValveFault(ValveFault)` | event, optional | when a fault is registered or cleared |
| status `FailureDueToFault` 0x02 | cluster status | "could not be performed due to a fault on the valve" |

- **matter.js implements none of it:** `ValveConfigurationAndControlServer` is the bare generated behaviour (14 lines) — no countdown, no auto-close [V-src S3]. The bridge (16a) owns the timer [I].
- The countdown units match the `Clock`-based timers already designed: `onFor` (12c-02 §2), `TimerRelay` (12c-05). Its reporting rule is the same as in [05 §1.1](05-timer-relay.md) [V].

### 1.3. Irrigation System `0x0040`

Since **1.5**, revision 1; unchanged up to 1.7 [V-src S1]. "Also commonly referred to as 'Sprinkler Controllers' … A physical irrigation system typically has a set of electrical terminals to which in-ground water valves are connected" [V S2, spec §5.7].

#### 1.3.1. Composition

- "Always defined via endpoint composition … Each zone is represented by a disambiguated Water Valve endpoint." At least one Water Valve endpoint; "Any instance of the Valve Configuration and Control Cluster on an endpoint is scoped to the valve on that endpoint and not the whole node." [V S2]
- The data model classes it `simple`, like Refrigerator and Laundry Washer — other appliances built from child endpoints [V-src S1]. The XML holds no composition element; the rule above is spec prose only [V-src S1].
- Clusters on the Irrigation System endpoint: Identify ("identify the entire irrigation system device"), Operational State, Flow Measurement server and client — **all optional** [V-src S1, V S2]. So the parent may carry no cluster beyond Descriptor [I].

Example layout of a 3-zone controller [I — from the rules above]:

```
EP0  Root Node
EP1  Irrigation System 0x0040    Identify?, Operational State?, Flow Measurement?
 ├─ EP2  Water Valve 0x0042      Valve Configuration and Control   TagList: Location.Zone, Number.One
 ├─ EP3  Water Valve 0x0042      …                                  TagList: Location.Zone, Number.Two
 └─ EP4  Water Valve 0x0042      …                                  TagList: Location.Zone, Number.Three
master valve, pump:  no endpoint
```

#### 1.3.2. Zone tags

- With more than one zone, each Water Valve "shall include semantic tags from the common namespaces in the TagList attribute of the Descriptor cluster" [V S2].
- `TagList` is a fixed-quality list of `SemanticTagStruct {MfgCode, NamespaceID, Tag, Label}`; `Label` is a nullable string [V-src S1]. Fixed ⇒ the tags name the terminal, not the user's lawn [I]. A user's zone name goes to a label cluster or, on a bridge, to the bridged device's name (16a) [I].
- Common namespaces that fit [V-src S1, `namespaces/`]: Common Location `0x0006` tag `Zone` `0x0004` — "Element is a part of a location divided into zones (e.g. a yard irrigation zone)"; Common Number `0x0007` (`One`, `Two`, …); Common Area `0x0010` (`FrontYard`, `BackYard`, `Garden`, …).
- Which combination controllers expect: [GAP] — the spec text in S2 gives none.

#### 1.3.3. Master valve and pump

"When a master valve is present, the physical system is responsible for opening it first when receiving a command to open a downstream watering valve … closing the master valve when the last open watering valve is closed. Since the master valve is orchestrated by the device, it is not represented as a Water Valve endpoint." [V S2]

- A pump is not mentioned [V S2]. Device Energy Management has `IrrigationWaterPump` in its `ESATypeEnum` [V-src S1]; Pump `0x0303` is its own device type, not shown by Apple (README §2) [V].
- Delays between master and zone (OpenSprinkler, ESPHome, §4.2) are not in the spec — the device's own business [I].

#### 1.3.4. Operational State on the system

When present [V S2]: "Running" while "at least one of the composed water valves is open for any reason", "Stopped" when all are closed. Pause, Resume and "Paused" are optional — "if it supports temporarily pausing a water valve that is currently open for a known duration. In this case, it SHOULD report the CountdownTime attribute to denote the remaining open duration of a currently open valve."

Operational State `0x0060` itself [V-src S1, V S2]:

| Element | Facts |
|---|---|
| `OperationalState` | `Stopped` 0, `Running` 1, `Paused` 2, `Error` 3; `OperationalStateList` = the states matching the supported commands, plus Error |
| `OperationalError` | `{ErrorStateID, ErrorStateLabel?, ErrorStateDetails?}`; `NoError`, `UnableToStartOrResume`, `UnableToCompleteOperation`, `CommandInvalidInState` |
| `PhaseList`, `CurrentPhase` | mandatory but nullable: "A value of null indicates that the device does not present phases" |
| `CountdownTime` | optional, `elapsed-s`, ≤ 259200 (72 h); 0 = done, null = no time defined. Not reported on a plain countdown (05 §1.1) |
| `Pause` ⇔ `Resume`, `Start` ⇔ `Stop` | each pair both-or-none. `Resume` returns to "the point it was at when it received the Pause command"; `Start` "if it is safe to do so" |
| events | `OperationalError` (mandatory, critical); `OperationCompletion` (optional; `TotalOperationalTime`, `PausedTime`) |

- Start/Stop on the system are not described for irrigation; S2's text names only Running/Stopped and Pause/Resume [V S2]. What `Start` would run (a program?) and whether `Stop` closes every zone: [GAP] [I: Stop = all valves closed is the natural reading].
- `CountdownTime` is "of a currently open valve" — one valve. With two zones open, which one counts: [GAP].
- Paused vs the zone: whether a paused zone reports `Closed` with `RemainingDuration` kept, or stays `Open`: [GAP].

#### 1.3.5. Flow

- System Flow Measurement server: "shall report the total flow through the irrigation system and not any individual valve" [V S2].
- System Flow Measurement client: "used via binding to measure flow from external flow sensors" [V S2]; a zone's client: "to close a control loop of flow through the valve" (§1.1) [V S2].
- Flow Measurement `MeasuredValue` unit: [GAP] here — not read.

#### 1.3.6. What the spec does not say

All [GAP] in S1/S2:

- Schedules, programs, run times, rain delay, seasonal adjust — there are no attributes or commands for them. A controller (or the device's own app) schedules zones [I].
- Whether several zones may be open at once, or the device may refuse. A refusal fits `Open` → `FailureDueToFault`, and the valve fault bit `CurrentExceeded` ("The available current has been exceeded") fits a transformer limit (§4.1) [I].
- Rain or soil input. Rain Sensor `0x0044` and Soil Sensor (1.5: Identify, Soil Measurement `0x0430` mandatory with `SoilMoistureMeasuredValue` in %, Temperature Measurement optional) are separate device types [V-src S1]; no link to the Irrigation System is defined [I].

#### 1.3.7. Support

| Controller | Irrigation System |
|---|---|
| Apple Home | not in darwin.md's list [V S6]; zones are Water Valves, which Apple refuses (§2) [V]. Apple DTS: HAP's "'Irrigation System' definitions are different enough that they can't be directly mapped" [V S6] |
| Google Home | not in either list [V S9, S10]. The Home APIs list a Google-specific "Sprinkler" (`home.matter.6006.types.0141`, Timer and Operational State traits) [V S10] |
| Home Assistant | not mapped [V-src S5]. Discovery is per endpoint, so each zone still becomes a `valve` entity [I] |
| SmartThings | mapped: profile `irrigation-system` (`valve`, optional `level`, `flowMeasurement`, `operationalState`; category `Irrigation`); one child device per Water Valve endpoint; flow and operational state taken from the Irrigation System endpoint [V-src S11]. Commands go to the endpoint of the component [V-src S11] |
| matterbridge-zigbee2mqtt | "Controllers still handle this poorly" [V S15] |

Products declaring `0x0040`: none found — [GAP]. matter-survey's page for type 64 could not be fetched. The Grimsholm valve (§3) is a single Water Valve, not an Irrigation System [V S13].

### 1.4. Water Leak Detector `0x0043` and its siblings

| Device type | Since | Clusters [V-src S1] |
|---|---|---|
| Water Leak Detector `0x0043` | 1.3 | Identify; Boolean State with **`StateChange` event mandatory**; Boolean State Configuration `0x0080` optional |
| Rain Sensor `0x0044` | 1.3 | same |
| Water Freeze Detector `0x0041` | 1.3 | same; triggering is "manufacturer specific" [V S2] |

- **Polarity:** `true` = leak detected, `false` = none; starts `false` [V S4]. Home Assistant maps `StateValue` to a moisture sensor without inverting it, while it inverts a Contact Sensor [V-src S5]. The spec's own table is not in S2 — [GAP] for the spec text itself.
- Boolean State: `StateValue` bool, not nullable ([04 §3](04-sensors.md)) [V].

Boolean State Configuration `0x0080` [V-src S1]:

| Feature | Elements |
|---|---|
| `VIS` Visual, `AUD` Audible | `AlarmsActive`, `AlarmsEnabled`, `AlarmsSupported`; `EnableDisableAlarm`; event `AlarmsStateChanged` |
| `SPRS` AlarmSuppress (needs VIS or AUD) | `AlarmsSuppressed`; `SuppressAlarm` |
| `SENSLVL` SensitivityLevel | `CurrentSensitivityLevel`, `SupportedSensitivityLevels`, `DefaultSensitivityLevel` |
| `FAULTEV` FaultEvents (1.6+) | makes event `SensorFault` mandatory |
| — (always) | `SensorFault` bitmap, bit `GeneralFault` |

### 1.5. Neighbours

- **No diverting / 3-way valve type** in 1.5 or 1.7; Water Valve is the only device type with "valve" in it [V-src S1].
- **Heating demand:** Thermostat's `PIHeatingDemand` (0–100 %, optional with `HEAT` in 1.5) is deprecated in 1.6 and obsolete in 1.7 [V-src S1]. Matter has no place for a heating valve's opening other than Water Valve `LVL` [I].

## 2. Controllers

| Controller | Water Valve | Leak Detector |
|---|---|---|
| Apple Home | **no** — "accessory is not created"; bridging does not change it; Apple DTS: "an 'uncertified' accessory can do whatever it wants" (the On/Off Plug-in Unit workaround) [V S6] | yes, iOS 18.4, "Water" category, "a critical notification with a red-tinted icon" [V S7]. KLIPPBOK shows leak state, battery, "whether the alarm is active" [V S8]. Rain, freeze: [GAP]; Apple ignores endpoints it doesn't recognise [V S6] |
| Google Home | not in either list [V S9, S10] | not in the Google Home ecosystem list ("Device types other than the ones listed here are not officially supported") [V S9]; in the Home APIs list for third-party apps, with Rain and Freeze [V S10]. Home app UI: [GAP] |
| Home Assistant | `valve` entity, class `water`; Open/Close always; position only with `LVL`; `Open()` sent without `OpenDuration`; position 0 → `Close`; `Transitioning` + target → opening/closing [V-src S5]. `DefaultOpenDuration` as a number entity; `AutoCloseTime` as a sensor (`TS` only); `RemainingDuration` unused; `ValveFault` bits as problem sensors [V-src S5]. Irrigation System not mapped [V-src S5] | binary sensor `moisture`; Rain → `moisture`, Freeze → `cold`; alarm enable switches, sensitivity number; `AlarmsActive`, `SensorFault`, `SuppressAlarm` unused [V-src S5] |
| SmartThings | profile `water-valve` (`valve` capability), `water-valve-level` with `LVL`; Irrigation System `0x0040` with each Water Valve as a child device. `CurrentState` ≠ 0 shows as open — `Transitioning` too. No duration handling [V-src S11] | `waterSensor` wet/dry + battery; Rain, Freeze profiles; `SensorFault` → `hardwareFault`; sensitivity preference [V-src S11] |

Home Assistant's own `valve` entity: states opening/open/closing/closed; features open, close, set position, stop; `reports_position`; 0 = closed, 100 = open [V S12].

## 3. Real products

| Product | Declared as | Facts |
|---|---|---|
| Grimsholm Smart Irrigation Valve (fw 1.5.0) | Water Valve | Thread, battery. 5 endpoints: EP0 root; EP1 Water Valve with **`TS` on, `LVL` off**, all duration attributes, `ValveFault`, Binding; EP2 Flow Sensor; EP3 Water Freeze Detector; EP4 Water Leak Detector without Boolean State Configuration. No Irrigation System endpoint, no Operational State, `TagList` off [V S13] |
| matter-survey.org | — | 3 products implement `0x0042`, 6 `0x0043`, 1 `0x0041`, 0 `0x0044` [V S14] |
| matterbridge-zigbee2mqtt | Water Valve (opt-in `valveList`) | open/close → ON/OFF, `CurrentLevel` 0 or 100; before, valves "appeared as on/off light switches (or not at all)"; on Irrigation System: "Controllers still handle this poorly" [V S15] |
| Aqara Valve Controller T1, Tuya-style Wi-Fi valves | — | "Matter-compatible" through a hub or sold as Apple Home compatible [V S16]; the declared type: [GAP] |
| IKEA KLIPPBOK leak sensor | Water Leak Detector | Thread sleepy end device; Boolean State Configuration `VIS`, `AUD`, `SPRS`; battery 2×AAA in Power Source [V S8]. Siren works unpaired; "occasionally flipped between connected and disconnected" in Apple Home [V S7] |
| Shelly Flood Gen4 | Water Leak Detector | Wi-Fi, Boolean State Configuration `AUD` only [V S14] |

## 4. Valves on Unipi outputs

### 4.1. Solenoid valves (irrigation)

| 24 VAC solenoid | Inrush | Holding | Source |
|---|---|---|---|
| Hunter PGV 1" | 350 mA (60 Hz) / 370 mA (50 Hz) | 190 / 210 mA | [V S17] |
| Rain Bird DV/DVF | 0.45 A | 0.25 A | [V S18] |
| Rain Bird G5 | 0.21 A | 0.10 A | [V S19] |

- OpenSprinkler: "800mA continues @ 24V AC per zone; 8A inrush"; DC latching valves are not compatible [V S20]. ESPHome: "For latching valves, use an H-Bridge switch" [V S21].
- Rain Bird ESP-TM2: 1 A at 24 VAC for all outputs; programs "run consecutively" and start times stack "to prevent hydraulic overload" [V S22]. One zone at a time follows from the transformer budget [I].
- Normally closed: not stated on the Hunter or Rain Bird pages read — [GAP]; residential diaphragm valves are NC by design [I].
- Patron relays: SPST-NO, 5 A, "Up to 100 000" electrical cycles depending on load, external RC / varistor / diode suppression needed [V S23]. Patron DOs are NPN open collector, 5–50 V **DC**, 750 mA [V S23] — a 24 VAC solenoid needs a relay [I].

### 4.2. Irrigation sequencing

| | ESPHome `sprinkler` (S21) | OpenSprinkler (S20, S24) |
|---|---|---|
| Duration | `run_duration` per valve; `multiplier` for all zones | per station; "% Watering" 0–250 %, weather-adjusted |
| Order | full cycle; `repeat` (default 0); a queue "takes precedence over valves that would otherwise run as a part of a full cycle"; `auto_advance`, `reverse` | sequential groups serialise; parallel group runs alongside |
| Between zones | `valve_open_delay`, "the *minimum* delay … between (distribution) valve switching", **or** `valve_overlap`, "time … the current valve and the next valve should run simultaneously" | station delay 0–60 min (sequential only) |
| Master valve / pump | `pump_start_pump_delay` / `pump_start_valve_delay` and stop equivalents | up to 4 masters; on-delay 0–60 s, off-delay −60…+60 s |
| Pause | `standby`: "will not start any valves" | rain delay: "immediately stop all stations, and programs will not run until the rain delay time is over"; rain sensor NO or NC |
| Runtime cap | none documented — [GAP] | 18 h before fw 2.2.1; weather-adjusted up to 7 days since |
| After a reboot | not documented — [GAP] | [GAP] |

All [V] from the sources named in the header. Hunter Freeze-Clik "shuts off system at 3ºC" [V S25].

### 4.3. Thermal actuators (heating)

| Actuator | NC / NO | Run power | Travel | Source |
|---|---|---|---|---|
| Möhlenhoff Alpha 5, 24 V | NC — "closed when the operating voltage is cut" | ~1 W; < 300 mA for up to 2 min at switch-on | ~3 min, 4 mm | [V S26] |
| Möhlenhoff AA5, 230 V | NC, NO | 1 W | ~3–4 min | [V S27] |
| Danfoss TWA-A | NC, NO, NC with end switch | 2 W | ~3 min | [V S28] |
| Siemens STA (NC) / STP (NO) | both | 2.5 W | ~3.5–4.5 min; ~3 min dead time from cold | [V S29] |
| IMI Heimeier EMO T | NC, NO | 3 W | ~3 min + ~1 min dead time | [V S30] |

- **First-Open:** an NC actuator is delivered open and locks closed-when-unpowered only after it was powered for a while — AA5: "> 6 min" [V S27]; EMOtec names the function [V S31].
- **Control:** two-point or PWM — "Designed for ON/OFF or PWM control" (EMOtec) [V S31]; Alpha 5 "two-point output or pulse-width-modulation" [V S26].

How heating controllers drive them:

| | MDT AKH, KNX (S32) | Möhlenhoff Alpha basis (S33) | Danfoss Icon (S34) | Gira 2158 (S35) |
|---|---|---|---|---|
| PWM period | default 10 min, 10 s – 30 min | — | by emitter type (slow, medium, fast); minutes: [GAP] | [GAP] |
| NC / NO | per channel; NO inverts the output | DIP switch | NC default | per output, all actuators on it the same |
| Valve protection | off by default; "a fixed cycle of 6 days for 5 min" | "once every 14 days for 10 minutes after the last triggering"; pump 14 d / 1 min | after 14 days without demand | "Protection against jamming valves"; interval: [GAP] |
| Summer | output forced to 0 %, by object or below a threshold (16 °C default) | — | — | summer/winter positions |
| Lost controller | no control value for 30–90 min ⇒ fixed duty, default 50 % | — | [GAP] | cyclic input monitoring, emergency position |
| Output | TRIAC — "cannot work with DC voltage!" | — | ~2 W per output | TRIAC, 2–4 actuators per output |

All [V] from the source named in the column. Loxone's room controller: [GAP] — not documented in S36.

- With a 10 min period an output switches 144 times a day; at 100 000 relay cycles that is about 1.9 years [I — arithmetic on S23, S32].
- Unipi DO hardware PWM runs in the kHz range (default 10 kHz; Edge ≤ 200 Hz recommended) ([research/02 §4.6](../02-hardware-model.md)) [V]. A 10-minute period is far below that — it is a software duty cycle on a plain on/off output [I].

### 4.4. Tank filling

- Finder 72.01: fill or empty mode; one level (2 electrodes) or min/max with hysteresis (3 electrodes); 0.5 s or 7 s delay; "On 'power-off', the output relay will immediately de-energise" [V S37, S38].
- Wilo (fill mode): pump on at the ON level, off at the OFF level; a high-water sensor switches off with an alarm and resets when the level drops [V S39].
- Jandy K-2000: if the level is not reached within the fill period (20 min default; 40, 60), "the controller turns the valve off for 24 hours"; 20 s debounce [V S40]. The only fill-time lockout found.
- ESPHome, Shelly, KNX tank-fill examples: [GAP].

### 4.5. 3-way diverting valve

- 2-wire actuators: powered to switch, spring or capacitor return on power loss. 3-wire actuators (one wire per direction): on power loss "The valve simply remains where it was" [V S41].
- Honeywell VC 3-way: SPST or SPDT; 7 s; power only while moving; "a power failure will leave the valve at the position it was when interrupted" [V S42]. Atlantic 3-way ball valve: ≤ 8 s, 3-wire, ≤ 3 cycles/min [V S43].
- One relay drives a 2-wire spring-return valve; a 3-wire valve needs a changeover contact or two outputs with an interlock ([06 §3.3](06-window-covering.md)) [I].
- Softened water on a garden: "in the longer term, it is not recommended" (sodium) [V S44]. Prior art of a bypass switched automatically for watering: [GAP].

### 4.6. Exercise, safety, power loss

| Topic | Found |
|---|---|
| Exercise | MDT 6 d / 5 min; Möhlenhoff 14 d / 10 min; Danfoss 14 d; Neptun ball valves every 30 days [V S32, S33, S34, S45] |
| Max open time | Jandy fill lockout; OpenSprinkler runtime cap (§4.2). A general convention: [GAP] |
| Power loss | NC actuators close [V S26]; Finder relays release [V S38]; 2-wire spring valves return, 3-wire valves stay [V S41] |
| Unipi | section watchdog: on timeout the section reboots into its saved default configuration ([research/02 §4.8](../02-hardware-model.md)) [V]; relays then take their default, normally off [I] — an NC valve closes. With the watchdog off, a dead daemon leaves the relay as it was [I] |

## 5. Leak detection

### 5.1. Leak modules

| Product | Output | Latching | Supervision | Source |
|---|---|---|---|---|
| Finder 72.11 + floor electrode | SPDT 16 A, energises on water | no — follows the sensor, 1 s delay | not stated; de-energises on power loss — the same as "no leak" | [V S37, S38] |
| Winland WB-200 | Form C, 1 A | "non-latching and resets automatically once the probe dries" | unsupervised | [V S46] |
| Winland WB-350 | open collector, 25 mA | not stated | "No alarm will sound if the cable is cut" | [V S47] |
| Wiren Board WB-MWAC | 2 relays for valves, 6 inputs | not stated | not stated; acts "regardless of the central controller" | [V S48] |
| MDT Leakage Sensor, KNX | alarm object | alarm-end behaviour configurable | — | [V S49] |

- A module with an NC alarm output (open on alarm and on power loss): not found — [GAP]. Wired to its NC contact, a dead module or a cut wire reads as a leak [I].
- Unipi DI: true at 7–35 V DC, false below 3 V; poll 100 ms onboard, 200 ms on an extension ([04 §8a.1](04-sensors.md)) [V]. A module output switches the DI's supply [I].

### 5.2. Leak alarms in building automation

- Loxone Fire & Water Alarm: water input → pre-alarm, main alarm after a delay (120 s default); `MaxA` auto-confirms (300 s default, 0 = never); acknowledge keeps it armed; remanent across reboot [V S50].
- Loxone emergency shut-off: the main valve stays closed and "will only be disabled once someone has acknowledged the alarm on the Loxone App" [V S51].
- Grohe Sense Guard: closes the supply on a burst or leak; Sense sensors trigger it [V S52].
- Matter's Boolean State has no latch: `StateValue` follows the detector. A latch lives in the controller (Loxone) [I].

## 6. evok-node today

| Where | What |
|---|---|
| 12c memo | `WaterValve`: "irrigation zones; Matter auto-close (`OpenDuration`); not supported by Apple Home". `WaterLeakDetector`: nothing yet. Irrigation is not a type: zones + rules (12b) + almanac (12d). `Thermostat` decides "what it adds over `TemperatureSensor` + `WaterValve`"; `Pump` deferred — a relay pump is an `OnOffPlugInUnit` |
| 12a §2.2, 16a | neither type listed yet |
| 12c-02 §2 | `onFor({ seconds })` on a plug-in unit: a one-shot `Clock` timer; a timed `onFor` is saved as off |
| 12c-05 | `TimerRelay`: `persistent` saves `remainingMs`, resumes after a restart; downtime not counted |
| 12c-04 §3.2 | `contact-from-di`: `invert` setting; missed pulses replayed from the DI counter (§3.1) |
| 07a §10 | `unipi.ro` bool channel; `unipi.do` bool or hardware PWM (duty on the channel, prescaler/cycle on `unipi.pwmOpt`) |

## 7. Proposals for 12c (not binding)

- **P1 — one `WaterValve`, on/off.** Fields after Matter: `state {current: closed | open | transitioning | unknown, target}` — the moving pattern of 12c §1. A solenoid goes to `open` at once; a thermal actuator stays `transitioning` for a set `travelS` (~180 s, §4.3). Settings: `normallyOpen` (inverts the output, as MDT and Möhlenhoff do), `travelS`.
- **P2 — timed open.** `open({ seconds? })`, `close()`, setting `defaultOpenS` (null = stays open), reading `remainingS`. These are `Open(OpenDuration)`, `DefaultOpenDuration`, `RemainingDuration` 1 : 1; no `TS`. Same timer as `onFor`. A `DefaultOpenDuration` write from Matter falls under 12c-04 §4's Open (M3.13).
- **P3 — safe start.** After a restart a timed valve is closed, not resumed (Matter recommends restarting only while closed; start-up is the maker's choice, §1.1). Unlike `TimerRelay`'s `persistent`. Untimed: restore or close — a setting.
- **P4 — `maxOpenS`.** A cap on every opening, timed or not, for irrigation and tank filling (Jandy, OpenSprinkler, §4.2, §4.4). Reaching it closes the valve and sets `GeneralFault` [I].
- **P5 — level for heating.** Either the valve gets `LVL` (`level` 0–100 → software duty cycle, `periodS` 600, min on/off time) and `Thermostat` drives the level; or the valve stays on/off and `Thermostat` owns the duty cycle. Matter has no other place for a valve's opening (§1.5). Relay wear (§4.3) favours a DO (24 V DC actuators) or an SSR over a relay; the template could warn when bound to `unipi.ro` [I].
- **P6 — exercise.** Setting `exerciseEveryDays` + `exerciseS` (MDT 6 d / 5 min, Möhlenhoff 14 d / 10 min). Skipped while open; for heating valves and the 3-way valve.
- **P7 — irrigation.** Zones are `WaterValve`s; one zone at a time, master valve / pump with on/off delays, `valve_open_delay` or overlap, multiplier, rain delay (§4.2) — a 12b rule or a bundle (12a §3a) whose members are the zones. 16a could compose the bundle as Irrigation System `0x0040` (§1.3): parent = the bundle, children = the zones with `Location.Zone` + `Number.N` tags, the master valve and pump as hidden members the bundle switches (§1.3.3); Operational State only Running/Stopped, derived from the zones; Pause/Resume and `CountdownTime` only if the bundle can pause a zone (§1.3.4). HA ignores the parent, SmartThings maps it (§1.3.7). Rain / freeze skip: almanac (12d), or a Rain Sensor `0x0044` on a DI.
- **P8 — Apple.** Apple Home never shows a Water Valve (§2). A per-device projection setting: `WaterValve` as Water Valve (default) or as On/Off Plug-in Unit (Apple's workaround; loses duration and state).
- **P9 — tank filling and the 3-way valve are rules, not types.** Fill: a `WaterValve`, a level input (`ContactSensor` on a float switch or a Finder 72 output), open below low / close at high, a fill-time lockout (Jandy). The 3-way valve on one relay is a `WaterValve` whose "open" is the bypass position [I]; Matter has no diverter type (§1.5).
- **P10 — faults.** A relay output reports nothing back; `ValveFault` stays 0 except P4's timeout [I]. A stale output source ⇒ not `reachable` (12a §4.2).
- **P11 — `WaterLeakDetector`.** Field `leak` (true = leak, as Matter, §1.4). Template `leak-from-di`: `invert` (true for a module's NC contact, so a cut wire or a dead module reads as a leak), `delayMs` (Finder 1 s, MDT alarm delay); missed pulses replayed as in 12c-04 §3.1. Matter: `StateValue` = `leak`, `StateChange` event on every change (mandatory, §1.4). No Boolean State Configuration on `local`. A second DI from a module's fault contact could feed `SensorFault` [I].
- **P12 — `matter` origin leak sensors.** Boolean State Configuration as optional fields: `alarmsActive`, `suppressAlarm()`, `sensitivity`, `sensorFault`; battery through `CommonFields` (KLIPPBOK, §3).
- **P13 — leak reaction is a 12b rule.** Leak ⇒ close the chosen valves and keep them closed until acknowledged (Loxone, §5.2); the detector itself does not latch (Matter, §1.4).
- **P14 — Rain Sensor and Water Freeze Detector** have the same shape as the leak detector (§1.4): one template, three home types, if 12c wants them.

## 8. Gaps

- The spec's polarity table for Water Leak Detector (only implementations seen, §1.4).
- Apple: Rain and Freeze sensors; whether `SensorFault` or alarm suppress show.
- Google Home app: leak sensor UI and notifications.
- Danfoss Icon PWM periods; Loxone valve logic; Hunter/Rain Bird NC statement.
- A leak module with a supervised (NC) output.
- Behaviour after a reboot of ESPHome and OpenSprinkler zones.

## 9. Sources

- S1 — connectedhomeip `data_model/1.3/`–`1.7/` at commit `645b267` (2026-10-24): `device_types/WaterValve.xml`, `IrrigationSystem.xml`, `WaterLeakDetector.xml`, `RainSensor.xml`, `WaterFreezeDetector.xml`; `clusters/ValveConfigurationControl.xml`, `BooleanStateConfiguration.xml`, `Thermostat.xml`: https://github.com/project-chip/connectedhomeip/tree/master/data_model/1.5
- S2 — matter.js generated docs (spec 1.6.1), commit `aec864d` (2026-10-22): `packages/types/src/clusters/valve-configuration-and-control.d.ts`, `packages/node/src/devices/water-valve.ts`, `irrigation-system.ts`, `water-freeze-detector.ts`: https://github.com/project-chip/matter.js/tree/main/packages
- S3 — matter.js `packages/node/src/behaviors/valve-configuration-and-control/ValveConfigurationAndControlServer.ts`, same commit: https://github.com/project-chip/matter.js/blob/main/packages/node/src/behaviors/valve-configuration-and-control/ValveConfigurationAndControlServer.ts
- S4 — Espressif Arduino-ESP32, Matter water leak detector endpoint: https://docs.espressif.com/projects/arduino-esp32/en/latest/matter/ep_water_leak_detector.html
- S5 — Home Assistant core, `homeassistant/components/matter/` (`valve.py`, `binary_sensor.py`, `number.py`, `sensor.py`, `switch.py`) at `1bc8cca`: https://github.com/home-assistant/core/tree/1bc8cca022997c1e29bc9cddad1e703c9023c226/homeassistant/components/matter
- S6 — Apple developer forum, "Home app rejects Matter device type 0x0042 (Water Valve) as 'not supported'" (Sep 2026): https://developer.apple.com/forums/thread/844646
- S7 — Matter Alpha, iOS 18.4 adds leak sensors: https://www.matteralpha.com/manufacturer-news/ios-18-4-expands-matter-support-with-smoke-co-and-water-leak-sensors ; KLIPPBOK review: https://www.matteralpha.com/review/ikea-klippbok-water-leak-sensor-review
- S8 — HomeKit News, KLIPPBOK review: https://homekitnews.com/2026/01/31/ikea-klippbok-leak-sensor-w-matter-over-thread-review/ ; matter-survey: https://matter-survey.org/device/klippbok-water-leak-sensor-4476-32774
- S9 — Google Home, supported Matter device types: https://developers.home.google.com/matter/supported-devices
- S10 — Google Home APIs, supported device types: https://developers.home.google.com/apis/supported-devices
- S11 — SmartThings Edge drivers (`matter-switch`, `matter-sensor`) at `3c3946ec`: https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/3c3946ec07a708837c1d4dc046c62390d20632c8/drivers/SmartThings
- S12 — Home Assistant developer docs, Valve entity: https://developers.home-assistant.io/docs/core/entity/valve/
- S13 — matter-survey, Grimsholm SIV261: https://matter-survey.org/device/siv261-4992-17
- S14 — matter-survey, device types 65–68: https://matter-survey.org/device-types/66 ; Shelly Flood Gen4: https://matter-survey.org/device/shelly-flood-gen4-5264-6178
- S15 — matterbridge-zigbee2mqtt #173 / PR #172: https://github.com/Luligu/matterbridge-zigbee2mqtt/issues/173
- S16 — Aqara Valve Controller T1 announcement: https://www.businesswire.com/news/home/20241119238611/en/Aqaras-New-Valve-Controller-T1-Modernizes-Home-Water-Management
- S17 — Hunter PGV spec: https://www.hunterirrigation.com/en-metric/print/pdf/node/920
- S18 — Rain Bird DV/DVF: https://www.rainbird.com/products/dvdvf-series
- S19 — Rain Bird solenoids sheet: https://www.rainbird.com/sites/default/files/media/documents/2026-07/d42606_-_irrigation_valve_solenoids.pdf
- S20 — OpenSprinkler firmware 2.1.0 manual: https://rayshobby.net/docs/os_fw210_manual.pdf
- S21 — ESPHome, Sprinkler controller: https://esphome.io/components/sprinkler/
- S22 — Rain Bird ESP-TM2: https://rainbird.com/media/4667
- S23 — Unipi Patron M207 datasheet v1.0: https://kb.unipi.technology/_media/files:products:patron:unipi-patron-m207-product-datasheet-v1.0-en.pdf
- S24 — OpenSprinkler firmware releases: https://github.com/OpenSprinkler/OpenSprinkler-Firmware/releases
- S25 — Hunter Freeze-Clik: https://hunterirrigation.com/en-metric/irrigation-product/freeze-cliktm/freeze-clik
- S26 — Möhlenhoff Alpha 5 (Theben): https://www.theben.de/product/9070442/datasheet
- S27 — Möhlenhoff OEM AA5 230 V: https://cdn.byggtjeneste.no/nobb/329157d0-dcde-40b7-be6d-91cecb1c81e2
- S28 — Danfoss TWA-A: https://assets.danfoss.com/documents/latest/460222/AI187386475671en-011101.pdf
- S29 — Siemens STA/STP (2014 edition, mirror): https://pzip.ru/downloads/sbt/A6V10371999.pdf?sku=STA..3
- S30 — IMI Heimeier EMO T: https://www.meinhausshop.de/media/pdf/90_100_39--DBL-02-de.pdf
- S31 — IMI EMOtec: https://imi-hydronic.com/product/emotec-first-open
- S32 — MDT AKH heating actuator manual: https://www.mdt.fr/fileadmin/user_upload/user_upload/download/MDT_TM_AKH_03_Heating_Actuator_V12.pdf
- S33 — Möhlenhoff Alpha basis direct: https://cdn.shopify.com/s/files/1/0904/4970/7337/files/130645_2124_DB_Basis_Alpha_direct_eng.pdf
- S34 — Danfoss Icon 24 V master: https://assets.danfoss.com/documents/157226/AN29434614196101-000402.pdf
- S35 — Gira heating actuator 2158 00: https://partner.gira.de/data3/21581190.pdf
- S36 — Loxone, Valve Actuator Air: https://www.loxone.com/enus/kb/valve-actuator-air/
- S37 — Finder 72 series: https://docs.rs-online.com/3798/A700000014359080.pdf
- S38 — Finder 72.11: https://docs.rs-online.com/32dd/A700000014359355.pdf
- S39 — Wilo control, fill mode: https://cms.media.wilo.com/dcianimpfinder/wilo718556/9646785/en-GB/2259793419.html
- S40 — Jandy Levolor K-2000 manual: https://images.inyopools.com/cloud/documents/K-2000I-AND-O-MANUAL.pdf
- S41 — 2-wire vs 3-wire ball valve actuators (vendor blog): https://www.electricsolenoidvalves.com/blog/2-wire-vs-3-wire-electric-ball-valve-actuators
- S42 — Resideo VC valves: https://homecomfort-techlit.resideo.com/emeadocuments/pim%20-%20renamed/vc-standard-onoff-en0h0327-pd-ge23.pdf
- S43 — Atlantic Valves BV spec sheet: https://electricsolenoidvalves.com/content/Atlantic_Valves_BVBTV_Spec_Sheet.pdf
- S44 — RHS, softened water: https://www.rhs.org.uk/advice/profile?PID=691
- S45 — Neptun ProW+ manual: https://www.c-o-k.ru/library/instructions/neptun/avtomatika-regulyatory-moduli-termostaty/24182/99378.pdf
- S46 — Winland WB-200: https://www.homecontrols.com/blogs/product-manuals-documentation/winland-waterbug-wb-200-installation-operating-instructions
- S47 — Winland WB-350: https://www.manualsdir.com/manuals/465968/winland-electronics-wb350.html
- S48 — Wiren Board WB-MWAC: https://wirenboard.com/product/WB-MWAC
- S49 — MDT Leakage Sensor: https://www.mdt.fr/fileadmin/user_upload/user_upload/download/MDT_FD_Leakage_Sensor_01.pdf
- S50 — Loxone, Fire & Water Alarm: https://www.loxone.com/enen/kb/fire-water-alarm/
- S51 — Loxone, emergency water shut-off: https://www.loxone.com/enen/kb/emergency-water-shut-off/
- S52 — Grohe Sense Guard: https://contenthub.grohe.com/en_gb/smarthome/grohe-sense-guard
