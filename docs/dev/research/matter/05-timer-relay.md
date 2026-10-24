# 05 — Timer relay

**Research, not design.** What Matter, controllers and the automation world offer for a general-purpose timer: Matter's countdown elements, controller support, timer-relay functions in PLCs, building automation and DIN-rail relays, behaviour across a restart, what Unipi hardware and EVOK do. Feeds 12c's `TimerRelay` section.

Input from Tomas (2026-10-24): both stay — `onFor` on lights and plug-in units (12c-01 §2, 12c-02 §2) and a general-purpose `TimerRelay`, shown as "Timer" in the UI.

Spec data from the connectedhomeip data model, `data_model/1.0/`–`1.7/` (S1); spec prose from matter.js's generated cluster docs, which cite Matter 1.6.1 (S2).

## 1. Matter

**There is no timer device type and no Timer cluster** in any `data_model/` version, 1.0 through 1.7 [V-src S1]. Countdowns exist only inside clusters that do something else:

| Element | Cluster | Units, range | Carried by (device types, 1.5) |
|---|---|---|---|
| `OnWithTimedOff`, `OnTime`, `OffWaitTime` | On/Off `0x0006`, feature LT | uint16, 1/10 s, max `0xFFFE` ≈ 109 min | every light and on/off unit with LT — [02 §2](02-plug-in-units.md) [V-src S1] |
| `Open(OpenDuration)`, `OpenDuration`, `DefaultOpenDuration`, `RemainingDuration`, `AutoCloseTime` (feature TS) | Valve Configuration and Control `0x0081` | `elapsed-s` (uint32 s), min 1; null = no auto-close | Water Valve `0x0042` [V-src S1] |
| `CountdownTime`, `OperationalState` (Stopped/Running/Paused/Error), `Start`/`Stop`/`Pause`/`Resume`, event `OperationCompletion` | Operational State `0x0060` | `elapsed-s`, max 259200 (72 h) | Dishwasher, Laundry Washer/Dryer, Microwave Oven, Irrigation System `0x0040` [V-src S1] |
| `CountdownTime` | Closure Control (1.5) | `elapsed-s`, max 259200 | closures [V-src S1] |
| `StartActionWithDuration`, `PauseActionWithDuration`, … | Actions `0x0025` | `Duration` uint32; S2's example is `Duration=3600` for 1 h | Aggregator (optional) — i.e. on a bridge [V-src S1] [V S2] |
| `Boost(Duration)` | Water Heater Management | — | Water Heater [V-src S1] |

- `StartActionWithDuration`: "after the specified Duration, the action will stop, and the action's state shall change to Inactive" [V S2]. Action states: Inactive, Active, Paused, Disabled; action types include Scene, Sequence, Automation [V-src S1].
- Irrigation System `0x0040` exists in `data_model/1.5/` (all clusters optional: Identify, Operational State, Flow Measurement) [V-src S1]. This contradicts [README §2](README.md)'s "irrigation has no device type of its own" — to re-check there.

### 1.1. How countdowns are reported

Matter does **not** report a countdown every second. `RemainingDuration` is reported only when it changes from or to null, changes to 0, increases, or the closing time changes; "clients SHOULD NOT rely on the reporting of this attribute in order to keep track of the remaining duration" [V S2 §4.6.7.4]. `CountdownTime` has the same rule, plus changes caused by state or phase, and "changes … merely due to the normal passage of time … shall NOT be reported" [V S2 §1.14.5.3]. Both carry the `quieterReporting` quality [V-src S1].

### 1.2. Ways a timer could appear on Matter

| Projection | Fits | Limits |
|---|---|---|
| none — not exposed | today's `Timer`: 16a ignores it (12a §1, 16a table) | — |
| On/Off Plug-in Unit + `OnWithTimedOff` | a timer that drives an output | ≈ 109 min max; no pause; the controller sees a plug, not a timer [I] |
| Water Valve + `OpenDuration` | a timed output with a set default duration | Apple Home refuses `0x0042` ([README §2](README.md)) [V] |
| Operational State | running/paused/stopped + countdown + completion event | only on appliance and irrigation device types; no generic host [V-src S1]. Apple Home support for those types: [GAP] |
| Actions on the bridge's Aggregator | "start for N s" across endpoints | controller support: [GAP] — not in S3/S4/S5; matter.js support not checked [GAP] |

## 2. Controllers

| Controller | Timer as a device | Timed off |
|---|---|---|
| Apple Home | none found [I] | in automations: "Tap or click Turn Off to choose an amount of time to turn off accessories in an automation" [V S3]; offered only when the automation turns an accessory on [V S4, user comment] |
| Google Home | `Timer` trait — cloud-to-cloud only; Matter not mentioned [V S5] | trait commands `TimerStart(timerTimeSec)`, `TimerAdjust(±s)`, `TimerPause`, `TimerResume`, `TimerCancel`; state `timerRemainingSec` (−1 = none), `timerPaused`; attribute `maxTimerLimitSec` [V S5] |
| Home Assistant | `timer` helper entity — §2.1 | — |

### 2.1. Home Assistant `timer`

The nearest software analogue to today's `Timer` (12a §2.2): a virtual entity with no output [V S6].

| Aspect | Behaviour |
|---|---|
| States | `idle`, `active`, `paused` [V S6] |
| Config | `duration` (default), `restore` (default false), `name`, `icon` [V S6] |
| `start(duration?)` | starts, or restarts. While active or paused, the event is `timer.restarted` instead of `timer.started`. With `duration`, it replaces the running duration; without, a paused timer resumes [V-src S7] |
| `change(±duration)` | adds or subtracts on a running timer; refused if the result would exceed the running duration or go below 0 [V-src S7] |
| `pause`, `cancel`, `finish` | `cancel` stops "without firing the finished event"; `finish` ends early, with the event [V S6] |
| Events | `timer.started`, `.restarted`, `.paused`, `.cancelled`, `.finished`, `.changed` [V-src S7]; trigger `timer.remaining_time_reached` with a `remaining` option [V S6] |
| Attributes | `duration`, `remaining`, `finishes_at` (UTC wall clock) [V-src S7] |
| Restart, `restore: true` | paused → paused with its remaining time; active with time left → resumes against the saved `finishes_at`; active and already past `finishes_at` → `finish` runs at startup, the event carrying the expected end time [V-src S7]. Automations on `timer.finished` "do not trigger on startup if the timer expired while Home Assistant was not running" [V S6] |

## 3. Timer-relay functions elsewhere

A timer relay is a **function** between an input (trigger) and an output. The same handful of functions recurs across domains:

| Function | Behaviour | IEC 61131-3 | LOGO! | Eltako MFZ12DX | KNX actuator (Elsner) | Loxone | Node-RED `trigger` | Shelly Gen2 |
|---|---|---|---|---|---|---|---|---|
| On-delay | out on T after in on; in off resets | `TON` | on-delay | `AV` | switch-on delay | On-delay [I] | — | `auto_on_delay` (after off) |
| Off-delay | out on with in; off T after in off | `TOF` | off-delay | `RV` | switch-off delay | Off-delay [I] | — | — |
| Pulse / interval | out on for T from an edge | `TP` (runs to completion) | interval relay / pulse output | `EW` (fleeting NO) | — | Monoflop | send, wait, send | `toggle_after`; `auto_off_delay` (after on) |
| Staircase | pulse, retriggerable, with prewarning before off | — | stairwell light switch [GAP: details] | `ESV` (impulse switch with release delay, early warning ≈ 30 s before, flickers 3×) | staircase function | [GAP] | — | — |
| Flasher / cycle | on/off with T1, T2 | — | asynchronous pulse generator | `TI` / `TP` (start with on / with pause) | — | — | resend every | — |
| Retentive on-delay | elapsed time kept while in is off; reset only by R | — (vendor `TONR`/`RTO`: [GAP]) | retentive on-delay | `AV+` / `ARV+` (elapsed time stored) | — | — | — | — |

Sources: IEC 61131-3 S8, LOGO! S9, Eltako S10, KNX S11, Loxone S12, Node-RED S13, Shelly S14, the generic catalogue S16. Each cell is [V] from its source, except where marked; LOGO!'s stairwell switch and pulse generator are [V] only as names in S9's function list.

IEC 61812-1 (time relays) defines timing functions [V S16b]. Its function designations are not public: [GAP].

### 3.1. Options that recur

| Option | Seen as |
|---|---|
| Retrigger while running | ignore (`TP` runs to completion [V S8]); restart from full ("can be retriggered" [V S11]; Node-RED "extend delay if new message arrives" [V S13]); add time ("the time to be added up by pressing the light push-button several times" [V S17]) |
| Early off | KNX "Off telegram during staircase light time causes": nothing / direct switch off [V S11]; Loxone `Off` input, dominating [V S12]; Node-RED reset, no output [V S13] |
| Prewarning before off | KNX: warning time 4–255 s, flashing off 0.2 s / on 0.8 s by default [V S11]; Eltako `ESV`: ≈ 30 s before, 3 flickers [V S10] |
| Pause / change | HA `pause`, `change` [V S6]; Google `TimerPause`, `TimerAdjust` [V S5]. Not found on relays or PLC blocks [I] |
| Duration per call | Node-RED `msg.delay` [V S13]; HA `start(duration)` [V S6]; Matter `OnTime`, `OpenDuration` (§1) |
| Range | Eltako 0.1 s – 40 h [V S10]; KNX time base 0.1 s / 1 s / 1 min / 1 h × factor 4–255 [V S11]; Matter `CountdownTime` ≤ 72 h, `OnTime` ≤ 109 min (§1) |
| Remaining time as output | Shelly `timer_started_at` (Unix UTC) + `timer_duration` [V S14]; HA `finishes_at` [V-src S7]; Matter `RemainingDuration`, `CountdownTime` (§1.1) |

## 4. Across a restart

| System | A running timer after restart / power loss |
|---|---|
| Home Assistant | lost unless `restore: true`; then resumed or finished against the wall-clock `finishes_at` (§2.1) [V-src S7] |
| LOGO! | per block: `Rem` off ⇒ state lost; on ⇒ kept through a power failure [V S9] |
| Loxone Monoflop | `Rem` parameter: "retains its previous state after a Miniserver reboot"; saved on planned reboot, backup, and hourly [V S12]. An unplanned power loss can lose up to an hour of state [I] |
| Eltako | `AV+`, `ARV+` store elapsed time after an interruption; other functions: not stated [V S10] |
| KNX actuator (Elsner) | relay position after bus failure / after reset: no change / opened / closed. A running staircase timer: not stated [V S11] |
| Shelly | `initial_state` off / on / `restore_last` / `match_input`; timers across a reboot: not stated [V S14] |
| evok-node `Timer` today | "after a restart every timer is stopped" (12a §2.2) [V] |

The `Clock` (04 §4.1) is monotonic and per process, "never comparable across that boundary". A restart-surviving deadline therefore needs a wall-clock anchor, as HA's `finishes_at` and Shelly's `timer_started_at` are [I]. 04 §4.1 and basics/02 §4.2 keep wall-clock time out of durations — a tension for 12c [I].

## 5. Unipi hardware and EVOK

- **No firmware timer.** DirectSwitch couples a DI to the same-numbered DO/RO with Copy, Inverse copy, Switch (toggle) and Block — no delay or pulse mode ([research/02 §4.7](../02-hardware-model.md)) [V].
- **EVOK's timed output is software.** `DigitalOutput.set(value, timeout)` writes the coil, then schedules a write of the inverse value after `timeout` s on the event loop. It is also on RPC as `output_set_for_time` ([research/01](../01-evok-api-surface.md)). Any later `set`/`set_state` cancels it. Not persistent [V-src S15].
- EVOK bug: `pending_id` starts at `0` but is cleared to `None`, and `pending` reports `pending_id != 0`. So after the first timed set finishes or is cancelled, `pending` stays `true` [V-src S15].
- The master watchdog (research/02 §4.8) is a timeout on communication, not a timer function [V].

## 6. evok-node today

| Where | What |
|---|---|
| 12a §2.2 | `Timer`: `running`, `remaining` (s), `elapsed` `{seq, at}`, `start({seconds})`, `cancel`; virtual, template `timer` with no roles; not persistent |
| 12b §1 | rules never wait; a `Timer` is how they do: rule A starts it, rule B acts on `elapsed` |
| 12a §2.1 | a hall `Timer` used only by rules: `exposed: false`, `controllable: false` |
| 12c-01 §2, 12c-02 §2 | `onFor({seconds, onlyWhenOn})`, `onForRemaining` emitting once a second; mapped to `OnWithTimedOff`; saved as off |
| 16a table | `Timer` ignored |

## 7. Proposals for 12c (not binding)

- **P1 — scope.** Two readings of "TimerRelay": (a) today's virtual `Timer` — start, cancel, `elapsed` — with outputs wired by rules (12b); (b) a timer with optional output roles (`unipi.ro`, `unipi.do`, any on/off device) that it switches itself, like a DIN-rail relay. (b) contains (a) when the role is 0–n. Every relay and PLC block in §3 drives an output; HA and Google's timers don't.
- **P2 — function set.** Pulse (on for T) is the minimum, and the only one today's `Timer` has. Candidates beyond it, by how often they recur (§3): off-delay, on-delay, staircase (pulse + retrigger + prewarning), flasher. With an input role, on- and off-delay need no rule at all.
- **P3 — retrigger as a setting:** `ignore` | `restart` | `add` (§3.1). Today's `start` restarts.
- **P4 — `pause` / `change`.** Only the virtual timers have them (HA, Google). They are cheap on a virtual timer; on a relay they have no precedent.
- **P5 — persistence as a setting** (HA `restore`, LOGO! and Loxone `Rem`). If adopted: store the deadline in wall-clock time, and decide what a deadline already past at startup does — HA finishes and emits (§2.1). This conflicts with 04 §4.1 (§4).
- **P6 — Matter.** Default: not exposed, as today. A timer with an output role could be projected as an On/Off Plug-in Unit, with `OnWithTimedOff` running the timer's pulse (≤ 109 min). Water Valve is ruled out by Apple; Operational State has no generic host (§1.2).
- **P7 — reporting `remaining`.** Matter reports a countdown only at start, stop and change (§1.1); `onForRemaining` emits every second. An absolute `endsAt` reading would let a UI count down by itself (HA `finishes_at`, Shelly `timer_started_at`). This collides with the `Clock` rule, like P5.
- **P8 — prewarning** for a staircase light on a relay: a short off before the end (KNX, Eltako). It would be a setting, and it only makes sense with an output role.

## 8. Sources

- S1 — connectedhomeip `data_model/1.0/`–`1.7/`, `clusters/` (OnOff, ValveConfigurationControl, OperationalState, ClosureControl, ActionsCluster, WaterHeaterManagement .xml) and `device_types/` (IrrigationSystem, Aggregator, WaterValve .xml): https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/data_model/1.5/clusters/ValveConfigurationControl.xml
- S2 — matter.js generated cluster docs (spec 1.6.1): `packages/types/src/clusters/valve-configuration-and-control.d.ts`, `operational-state.d.ts`, `actions.d.ts`: https://github.com/project-chip/matter.js/blob/main/packages/types/src/clusters/valve-configuration-and-control.d.ts
- S3 — Apple Support, "Create scenes and automations with the Home app": https://support.apple.com/en-ug/102313
- S4 — TidBITS, "Apple Enhances HomeKit with Sensor-Based Automations and Timed Turn-Offs" (2022-06-29): https://tidbits.com/2022/06/29/apple-enhances-homekit-with-sensor-based-automations-and-timed-turn-offs/
- S5 — Google Home Developers, Timer trait (cloud-to-cloud): https://developers.home.google.com/cloud-to-cloud/traits/timer
- S6 — Home Assistant, Timer integration: https://www.home-assistant.io/integrations/timer/
- S7 — Home Assistant core, `components/timer/entity.py` (dev, read 2026-10-24): https://github.com/home-assistant/core/blob/dev/homeassistant/components/timer/entity.py
- S8 — IEC 61131-3 timer blocks TP/TON/TOF (Elektror IDE docs): https://docs.daq.elektror.com/projects/ide/structured-text/standard-function-blocks/timers
- S9 — Siemens LOGO! manual (05/2000), §4.4 special functions, retentivity: https://support.industry.siemens.com/cs/attachments/19624874/logo_0500_en.pdf
- S10 — Eltako MFZ12DX multifunction time relay, operating instructions: https://www.eltako.com/fileadmin/downloads/en/_bedienung/MFZ12DX_23001005-1_gb.pdf
- S11 — Elsner KNX R1-B4 compact 16A manual, §5.3.3–5.3.4 time functions, staircase light: https://info.elsner-elektronik.de/hubfs/Produktdaten/70574_KNX_R1-B4_compact16A_Manual_EN.pdf
- S12 — Loxone, Monoflop: https://www.loxone.com/enen/kb/monoflop/
- S13 — FlowFuse, Node-RED trigger node: https://flowfuse.com/node-red/core-nodes/trigger
- S14 — Shelly Gen2 API, Switch component: https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/Switch
- S15 — EVOK `evok/modbus_slave.py` `DigitalOutput.set`, `set_state`; `evok/rpc_handler.py` `output_set_for_time`; commit `b2e241c` (2026-08-25): https://github.com/UniPiTechnology/evok/blob/main/evok/modbus_slave.py
- S16 — DigiKey TechForum, "Time Delay Relay Functions": https://forum.digikey.com/t/time-delay-relay-functions/577 · S16b — VIOX, IEC 61812-1 guide (scope only): https://viox.com/ur/iec-61812-1-time-delay-relay-compliance-guide
- S17 — MDT KNX switch actuator AKS-UP.03, extended staircase lighting: https://www.mdt.fr/fileadmin/user_upload/user_upload/download/MDT_FD_Switch_Actuator_AKS_UP_03.pdf
