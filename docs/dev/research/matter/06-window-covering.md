# 06 — Window covering

**Research, not design.** What Matter defines for window coverings, what controllers do with it, how other systems run a cover on two relays with no feedback, and how they protect it from wind. Feeds 12c's `WindowCovering` section.

Input from Tomas (2026-10-25):

- A cover is driven by two relays, up and down. No position feedback.
- Started in either direction, the cover first tilts, then travels.
- Known per cover: travel time up, travel time down, tilt time.
- A safety buffer at both ends, so the cover surely reaches the end.
- A reset to a known position (full up, full down): time counting drifts.
- A move to a position goes there first, then tilts.
- One template for now: two relays.
- Wind, level 1: a cover that is down with slats closed tilts open. Level 2: it goes up. Above level 1 tilting is refused; above level 2 moving down is refused. Wind comes from the almanac (12d) first, from a hardware wind sensor later.
- The wind reaction is the device's own safety function, not a rule: the template has two relays and a wind/gust source it subscribes to.
- Wind levels are device settings. A `protection` setting selects which levels act: none, level 1, level 2, or both. It is permanent and set in the Inspector UI.
- The reactions to an unreachable wind source and to the wind dropping are settings.
- Level 2 thresholds are CLIMAX's wind-class speeds; level 1 is set below them. Width, height and guide per cover are set at commissioning.
- Travel times up and down are measured end to end and include the tilt phase. Tilt time is measured on its own. All three are device settings.
- Covers in use: CLIMAX, C type.

Spec data from the connectedhomeip data model, `data_model/1.0/`–`1.7/` (S1); spec prose from matter.js's generated cluster docs, which cite Matter 1.6.1 (S2); matter.js's server implementation (S3).

## 1. Matter

### 1.1. Device type and features

Window Covering `0x0202`, since 1.0. In 1.5: Identify mandatory, Groups conditional, Window Covering cluster `0x0102` mandatory, Closure Control and Closure Dimension disallowed [V-src S1].

| Feature | Code | Needs |
|---|---|---|
| Lift | `LF` | at least one of `LF`, `TL` |
| Tilt | `TL` | at least one of `LF`, `TL` |
| PositionAwareLift | `PA_LF` | `LF` |
| PositionAwareTilt | `PA_TL` | `TL` |

`AbsolutePosition` (`ABS`) was removed in 1.5, "since it is disallowed by the Window Covering Device Type" [V-src S1].

### 1.2. Positions

- **0 = fully open (up), 10000 = fully closed (down)**, for lift and for tilt (`WC_PERCENT100THS_MIN_OPEN = 0`, `WC_PERCENT100THS_MAX_CLOSED = 10000`) [V-src S3]. `UpOrOpen` sets both targets to 0.00 % [V S2].
- With `PA_LF`/`PA_TL`: `CurrentPosition…Percent100ths` (nullable, non-volatile) and `TargetPosition…Percent100ths` (nullable, not persisted) are mandatory; `CurrentPosition…Percentage` (1 % step) is optional [V-src S1].
- A null current position makes matter.js report the movement as stopped [V-src S3]. The spec's meaning of null: [GAP] — not in S2.
- `ConfigStatus.LiftEncoderControlled` / `TiltEncoderControlled`: "0 = Timer Controlled, 1 = Encoder Controlled" [V S2]. A cover positioned by travel time is position-aware in Matter's terms [I].
- `Type` 8 = `TiltBlindLiftAndTilt`; `EndProductType` 13 = `ExteriorVenetianBlind`, 12 = `InteriorVenetianBlind`, 17 = `RollerShutter`. Both are fixed [V-src S1].

### 1.3. Commands

| Command | Effect [V S2] |
|---|---|
| `UpOrOpen` | lift and tilt to fully open, "as fast as possible"; targets 0 |
| `DownOrClose` | lift and tilt to fully closed; targets 10000 |
| `StopMotion` | stops lift and tilt; targets := current |
| `GoToLiftPercentage(liftPercent100thsValue)` | sets the lift target. Without `PA_LF`: 0 acts as `UpOrOpen`, anything else as `DownOrClose` |
| `GoToTiltPercentage(tiltPercent100thsValue)` | the same for tilt |

- Lift and tilt targets are set by separate commands. No command sets both, and none says in which order lift and tilt move [I — none in S2's command texts].
- matter.js: "A movement coming in while another movement is still running is assumed to be handled by the device" [V-src S3].
- matter.js answers a command in maintenance mode `BUSY`, one while not operational `FAILURE` [V-src S3].

### 1.4. Status, mode, safety

- `OperationalStatus`: 2-bit fields `Global`, `Lift`, `Tilt` — 0 stopped, 1 opening, 2 closing [V S2]. matter.js derives each from target vs current, and `Global` from `Lift` while lift moves, else from `Tilt` [V-src S3].
- `Mode` (writable, manage privilege): `MotorDirectionReversed`, `CalibrationMode`, `MaintenanceMode` ("Freeze all motions for maintenance"), `LedFeedback`. An unsupported bit is refused with `CONSTRAINT_ERROR` [V S2]. matter.js: maintenance wins over calibration; with calibration enabled, it runs before the next movement [V-src S3].
- `SafetyStatus` (optional), selected bits [V-src S1]:

  | Bit | Text |
  |---|---|
  | `RemoteLockout` | "Movement commands are ignored (locked out). e.g. not granted authorization, outside some time/date range." |
  | `PositionFailure` | "Device has failed to reach the desired position. e.g. with position aware device, time expired before TargetPosition is reached." |
  | `ThermalProtection` | "Motor(s) and/or electric circuit thermal protection activated." |
  | `StopInput` | "Local safety sensor (not a direct obstacle) is preventing movements" |
  | `Protection` | "Protection is activated." |

- No wind bit. No wind-speed cluster or device type exists in 1.5 or 1.7 [V-src S1].
- `NumberOfActuationsLift`/`Tilt`: optional, non-volatile counters [V-src S1].

### 1.5. Closures (1.5)

- Matter 1.5 adds Closure `0x0230` (Closure Control mandatory) and Closure Panel `0x0231` (Closure Dimension). Both disallow the Window Covering cluster; Window Covering disallows theirs — an endpoint is one or the other [V-src S1].
- Closure Control has features `Calibration`, `Protection`, `ManuallyOperable`, …; `MainState` includes `Calibrating`, `Protected` ("Some protective measures are activated to prevent damage to the closure. Commands MAY be rejected."), `SetupRequired` ("Movement commands are ignored since the closure is not operational and requires further setup and/or calibration"); a `Calibrate` command [V-src S1].
- Closure Dimension has `Translation` and `Rotation` features and a modulation type `SlatsOrientation` [V-src S1].
- Controller support for `0x0230`/`0x0231`: [GAP].

### 1.6. Reporting

Current positions are reportable with no quieter-reporting quality, unlike countdowns ([05 §1.1](05-timer-relay.md)) [V-src S1, 1.5]. How often a moving cover should report: [GAP].

## 2. Controllers

| Controller | Behaviour |
|---|---|
| Apple Home | Window Covering supported ([README §2](README.md)). Tilt is reached through the gear icon in the slider view; no voice commands for tilt [V S5]. A tilt-only covering shows "This accessory is not responding", and the tilt slider sends only 0 % or 100 % (Oct 2023, FB13305460) [V S4]. Granular tilt on a lift-and-tilt endpoint: [GAP]. Whether `SafetyStatus` is shown: [GAP] |
| Google Home | [GAP] — not checked |
| Home Assistant | position "0 means closed and 100 is fully open"; tilt "0 means closed/no tilt and 100 means open/maximum tilt" — **inverse to Matter** [V S6]. Features include `OPEN_TILT`, `CLOSE_TILT`, `SET_TILT_POSITION`, `STOP_TILT` [V S6] |

## 3. Time-based covers on two relays

### 3.1. Parameters across products

| Parameter | MDT JAL, KNX (S8) | Loxone (S9) | Shelly Gen2 (S7) | ESPHome (S10) |
|---|---|---|---|---|
| Travel up / down | same or different; 1–10000 s, default 45 s | `Opd` 75 s, `Cld` 70 s | `maxtime_open`/`maxtime_close` 60 s (timeouts; ends found by power metering) | `open_duration`, `close_duration` |
| Tilt time | 10–10000 ms, default 1200 | `Rd` 0.8 s, "until the slats are horizontal"; backlash `Bldo` 0.15 s added | `slat.open_time`/`close_time` 1.5 s, 0.5–30 s | — (S11: `tilt_duration`) |
| Overrun at an end | none / 2 / 5 / 10 / 15 / 20 % of travel time; "ensures that the end stops are definitely reached"; no effect on the computed position | a full open always runs the full `Opd` — "corresponds to a reference run"; `Rdd`: every close runs the full time | — | `has_built_in_endstop`: no stop action when the timed move finishes |
| Direction-change pause | 1–1000 ms, default 500; "Too short selected reverse pauses can damage the motor!" | `Mld` 0.5 s | — | `direction_change_wait_time` |
| Start delay | switch-on delay 0–255 ms | — | — | `acceleration_wait_time`; S11: motor start is "nondeterministic", ~200 ms |
| Smallest move | slat step 50–1000 ms, default 200 | `minTd` 0.4 s | `slat.step` 20 % (inputs only) | — |
| Reference | after parametrisation, full down and up; regularly, "e.g. one's a week"; any end position counts; afterwards: back to the former position, or nothing | full open | `Calibrate`: open, close, open, close + open; `current_pos` null "if the position is unknown" | — |
| Slats after a move | "automatically activated … after a shutter travel", 0–100 %, default 50; a stop during travel skips it | `So`: close, then slats to `Rd` | `retain_pos` (default false); `precise_ctl`: near closed, slat moves pass through fully closed | — |
| Max run time | — | — | `maxtime_*` | `max_duration` |

All [V] from the source named in the column.

### 3.2. Drift

- Shelly: "If the cover is moved many times between fully open / fully closed without ever reaching them, the error is accumulated and position control accuracy deteriorates." `GoToPosition` with an unknown position fails: "-109 Precondition failed: Current position unknown!" [V S7].
- Loxone: the position is kept remanent; after a power loss during a move it may be wrong, so "a complete open movement must be executed first" [V S9].
- Error sources here [I]: write latency on each relay change (§5), the motor's start delay, up and down speeds that differ, load and temperature. Each partial move adds error; an end reached with overrun removes it.

### 3.3. Motor and relay protection

- **Interlock.** Never both relays: S11 "will not connect relay 1&2 … at the same time" [V]. research/04 §4.8: "A third-party author reports burning out relay outputs by driving a cover's up/down relays together" [V].
- **Motors stop themselves at their ends.** Somfy J4: "Bottom end-limit already set in factory", "Limit switch unit Mechanic"; separate Up and Down wires [V S12]. Overrun therefore runs into the motor's limit switch, which cuts the motor [I].
- Duty cycle and thermal limits of blind motors: [GAP] — not in S12.
- Wiring one relay for power and one as a direction changeover makes both-on impossible in hardware [I]. Tomas's covers use an up and a down relay.

## 4. Wind

### 4.1. Thresholds

Griesser, external venetian blinds, tested to EN 13659; sensor fitted next to the product [V S13]:

| Class | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| Sensor setting, m/s | < 9.0 | 9.0 | 10.7 | 12.8 | 16.7 | 21.0 | 25.6 |
| km/h | < 28 | 32.5 | 38.5 | 46 | 60 | 76 | 92 |

- The class depends on product and width — e.g. Grinotex III: class 6 at 1500 mm, 2 at 5000 mm [V S13].
- Curtain 100–300 mm from the facade: one class lower; 300–500 mm: two [V S13].

### 4.2. Limits of protection

"The external venetian blinds cannot be protected with wind sensors against sudden gusts of wind." Updrafts and fall winds at facades: "Wind sensors cannot detect these as a rule." "Wind speeds can be considerably higher at building corners." "Make sure that the external venetian blinds remain retracted if a storm is imminent." [V S13]

### 4.3. Switching behaviour

| | Elsner KNX W (S14) | MDT JAL (S8) | Loxone (S9) |
|---|---|---|---|
| Thresholds | 3; 0–35 m/s, step 0.1 | one alarm input each: wind, rain, frost; priority order chosen | one input `Wa` |
| Hysteresis | % of threshold, default 20 | — | — |
| Delay on / off | 0→1 and 1→0 each none or 1 s – 2 h | — | no release delay |
| While active | — | "A control is then not possible as long as the alarm is active"; action up / down / height / none | goes to `Wap` (default fully open) and locks; automation paused, not cancelled |
| End of alarm | — | up / down / former position / no action | automation restarts on the next sun-shading edge |
| Silent source | value changing < ±0.5 m/s for 48 h ⇒ outputs 35 m/s, all wind alarms trip; no value for 60 s after power-up | monitoring period 0–120 min; no signal in time ⇒ "the alarm is triggered automatically" | — |

All [V] from the source named in the column.

### 4.4. Wind data

- **Forecast — Open-Meteo:** `wind_speed_10m` is instantaneous; `wind_gusts_10m` is the "maximum of the preceding hour". 15-minutely data "Only available in Central Europe and North America. Other regions use interpolated hourly data." Models update every 1–12 h. Default unit km/h [V S15]. A 10 m area value says nothing of the facade (§4.2) [I].
- **Local anemometer:** a cup anemometer closes a reed contact per turn — SparkFun: "1.492 mph = 1 switch closure/second" (2.4 km/h) [V S16]. A Unipi DI counter takes up to 10 kHz (research/02 §4.9) [V]; speed is counts over time [I]. Analog 0–10 V anemometers would go to an AI [I].
- research/04 §2.3: "A wind sensor on a DI killed the whole API" in EVOK — events per pulse flooded the WebSocket [V].

### 4.5. CLIMAX C-80

From CLIMAX's operating and maintenance manual, 07/2016 (S17); quotes translated from Czech. A newer edition: [GAP].

- Wind classes per ČSN EN 13659+A1; "valid for the product lowered and closed", wind "perpendicular to the plane of the blind with minimal dynamic effect", tested with windows and doors closed [V S17].
- "In strong wind, e.g. during a storm, the blind may be damaged and must be raised to the upper end position." No speed is given for when [V S17].
- The motor stops by itself at an end; it has a thermal cut-out — "if the motor overheats, wait 10–20 minutes" [V S17].
- Frozen to the rails or sill: the blind must not be operated until the ice is removed [V S17].

Class scale [V S17]:

| Class | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| km/h | < 30 | 30 | 35 | 45 | 60 | 75 | 90 |

C-80 and C-80 CC, class by width [V S17]:

| Guide | Height | ≤ 2000 | –3000 | –4000 | –4500 | –4800 | –5000 mm |
|---|---|---|---|---|---|---|---|
| rail | ≤ 400 cm | 4 | 3 | 2 | 1 | 0 | 0 |
| cable | ≤ 250 cm | 2 | 1 | 0 | 0 | 0 | 0 |
| cable | ≤ 400 cm | 1 | 0 | 0 | 0 | 0 | 0 |

C-80 VENTAL on rails is one class higher than C-80 up to 4800 mm; on cables the same [V S17]. CLIMAX's class speeds equal or are slightly below Griesser's sensor settings for the same class (§4.1) [V S13, S17].

### 4.6. Mean wind or gust

- WMO: mean wind speed is "an average over 10 min"; peak gust is "the maximum observed wind speed over a specified time interval", taken from 3 s moving averages, sampled every 0.25 s (4 Hz); lower sampling "may underestimate the extreme" [V S18 §5.1.1, §5.1.2, §5.8.2, §5.8.3].
- A blind is damaged by the peak load, not the average [I]. A gust is over in seconds, and a cover needs about a minute to retract (MDT default 45 s, Loxone 70–75 s, §3.1), so a gust can't be dodged — Griesser says so (§4.2). What a gust above the threshold does tell you is that the conditions are gusty, and the next gust may be stronger [I].
- So the usual shape is fast in, slow out [I]: a level rises on the first gust over its threshold, and drops only after the gusts have stayed below threshold − hysteresis for a hold time (Elsner's 1→0 delay, §4.3).
- The forecast's `wind_gusts_10m` is already a peak hold — the highest gust of the preceding hour (§4.4). On it, a long hold time adds little [I].
- On a local anemometer, a gust is computed: the highest 3 s average in the window. A DI counter read every 100–250 ms gives this (research/02 §4.9; `fast` poll: 100 ms onboard, 08 §8; 200 ms on an extension, 09 §4) [I].
- A stale source is a separate timeout: how long without a fresh value before the device takes its "source lost" reaction. The forecast updates hourly at best (§4.4); MDT's monitoring window is 0–120 min (§4.3) [V S8, S15].

## 5. Unipi hardware and evok-node today

- No cover function in Unipi firmware. DirectSwitch couples a DI only to the same-numbered DO/RO (research/02 §4.7) [V].
- Master watchdog: on timeout the section reboots into its saved default configuration (research/02 §4.8) [V]; a relay then takes its saved default, normally off [I]. With the watchdog off, a daemon that dies mid-move leaves a relay on until the motor's limit switch [I].
- Write timing on an extension line: ~19 ms per RTU transaction at 19200; four xS11 on one line ≈ 77 ms round-robin (research/08 §2, §4) [V]. A relay change queued behind a scan is late by up to that [I]. Onboard write latency: [GAP] here.

| Where | What |
|---|---|
| 12a §2.2 | `WindowCovering`: `position` reading `{current, target, motion}` (%) · `goTo {percent}` · `stop`. No tilt |
| 12b §2.1 | `one-button-window-cover`: `goTo` the end in the current direction, `stop` on `longRelease` |
| 16a | `WindowCovering` → Window Covering `0x0202` |
| 12a §3 | `ctx.state`, saved at most every 5 s — what a template persists across a restart |
| 12c memo | "% direction (Matter: 0 = open); tilt for venetian blinds; position from travel time on two relays" |

## 6. Proposals for 12c (not binding)

- **P1 — fields.** Two moving values, `lift` and `tilt`, each `{current, target, motion}`; `current` null = unknown (Matter nullable, Shelly null). Direction: Matter's 0 = open needs no conversion in 16a; Home Assistant's is the inverse (§2). One convention, stated once in 12c §1.
- **P2 — one `goTo({ lift?, tilt? })`.** One call carries both, so "position, then tilt" is one request. Matter's separate `GoToLift…`/`GoToTilt…` (§1.3) would merge in 16a: a tilt target arriving during a lift move is applied after the lift [I]. Plus `up`, `down`, `stop`.
- **P3 — timing settings** (Tomas: device settings). `upMs`, `downMs` — measured end to end, tilt included; `tiltMs` — measured alone; lift time in a direction = `upMs − tiltMs` or `downMs − tiltMs`. Plus overrun (% of travel as MDT, or ms), `reversePauseMs` (500 in MDT and Loxone), `startDelayMs`, `minPulseMs`.
- **P4 — sequence for `goTo({ lift, tilt })`**, on Tomas's mechanism:

  ```
  dir = sign(lift.target − lift.current)
  if dir ≠ lastDir: wait reversePauseMs
  run dir for  tiltMs × (tilt distance to dir's end)  +  liftMs(dir) × |Δlift|
  stop; wait reversePauseMs
  run −dir for tiltMs × |tilt.target − tilt at dir's end|
  ```

  Tilt only: one pulse in the needed direction. A lift-only `goTo` restores the tilt from before (Shelly `retain_pos`) or goes to a set default (MDT 50 %).
- **P5 — ends and reference.** A target of 0 or 100 runs the computed remaining time plus overrun; reaching the end sets `current` exactly — every full move is a reference (MDT, Loxone). Beyond that: a `reference({ end })` method; a forced reference after N partial moves or accumulated travel (none of S7–S10 counts moves; MDT recommends weekly); or a rule on an almanac schedule. After a restart mid-move: `current` null until the next end. A middle `goTo` from null either fails (Shelly) or references first and then goes there (MDT).
- **P6 — wind, in the device.** A `wind` role, 0–1, on a source with a gust reading (and a mean reading where there is one): the almanac's forecast now, an anemometer later (§4.4). No Matter counterpart (§1.4), so a home-only type or a source kind. Settings:

  | Setting | Meaning | Seen in |
  |---|---|---|
  | `protection` | `none` \| `level1` \| `level2` \| `both` — which levels act (Tomas); permanent, Inspector UI | MDT: block function ordered among alarms (§4.3) |
  | `level1`, `level2` | gust thresholds | Elsner: 3 thresholds |
  | `hysteresis` | a level drops below threshold − hysteresis | Elsner: 20 % |
  | `releaseAfterMs` | gusts below the level that long before it drops | Elsner 1→0 delay |
  | `sourceLostAfterMs` | no fresh value that long ⇒ source lost | MDT monitoring period |
  | `onSourceLost` | `none` \| `level1` \| `level2` | MDT, Elsner: alarm |
  | `onRelease` | `none` \| `restore` \| `up` \| `down` | MDT: up / down / former position / none |

  - Level 1: down with slats closed ⇒ tilt open; tilt refused. Level 2: up; down refused (Tomas).
  - **Level 1 vs CLIMAX:** the declared class holds for a blind "lowered and closed" (§4.5). Open slats are outside the tested state — to check with CLIMAX [I].
  - `level2` = the class speed for the cover's width and guide (§4.5), set at commissioning; `level1` below it (Tomas). A gust at `level2` reaches the blind before it is up — retraction takes about a minute (§4.6) [I].
  - The device shows the active level and why it refuses — on Matter, `SafetyStatus.Protection` [I].
- **P7 — Matter projection.** `LF`, `TL`, `PA_LF`, `PA_TL`; encoder bits 0 (timer, §1.2); `Type` 8; `EndProductType` a setting (13 for an external venetian blind); `SafetyStatus.Protection` during a wind alarm; a refused command answered as matter.js answers maintenance (`BUSY`) [I]; `Mode.CalibrationMode` → reference. Window Covering, not Closure (§1.5).
- **P8 — reporting while moving.** `target` at once (12a §4a); `current` computed and emitted at an interval (ESPHome: 1 s) and at the stop.
- **P9 — the template owns its relays.** Interlock and reverse pause live in the template, never in a rule. A relay switched by someone else ⇒ the movement stops and `current` becomes null [I].

## 7. Sources

- S1 — connectedhomeip `data_model/1.0/`–`1.7/` at commit `645b267` (2026-10-24): `clusters/WindowCovering.xml`, `ClosureControl.xml`, `ClosureDimension.xml`; `device_types/WindowCovering.xml`, `Closure.xml`, `ClosurePanel.xml`: https://github.com/project-chip/connectedhomeip/tree/master/data_model/1.5
- S2 — matter.js generated cluster docs (spec 1.6.1), `packages/types/src/clusters/window-covering.d.ts`, commit `aec864d` (2026-10-22): https://github.com/project-chip/matter.js/tree/main/packages/types/src/clusters
- S3 — matter.js `packages/node/src/behaviors/window-covering/WindowCoveringServer.ts`, same commit: https://github.com/project-chip/matter.js/blob/main/packages/node/src/behaviors/window-covering/WindowCoveringServer.ts
- S4 — Apple developer forum, "Matter tilt only Window Coverings and the Home App" (Oct 2023): https://developer.apple.com/forums/thread/740415
- S5 — Hunter Douglas, "Integrate PowerView Gen 3 with Apple Home Using Matter": https://help.hunterdouglas.com/hc/en-us/articles/39338693415444-Integrate-PowerView-Gen-3-with-Apple-Home-Using-Matter
- S6 — Home Assistant developer docs, Cover entity: https://developers.home-assistant.io/docs/core/entity/cover
- S7 — Shelly Gen2 API, Cover component: https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/Cover
- S8 — MDT technical manual, Shutter Actuator 02 (JAL), §4.3–4.4, §4.7, §4.10: https://www.mdt.fr/fileadmin/user_upload/user_upload/download/MDT_TM_Shutter_Actuator_02.pdf
- S9 — Loxone, Automatikjalousie: https://www.loxone.com/dede/kb/automatikjalousie/
- S10 — ESPHome, Feedback Cover: https://esphome.io/components/cover/feedback/
- S11 — bruxy70, Venetian-Blinds-Control: https://github.com/bruxy70/Venetian-Blinds-Control
- S12 — Somfy J4 1TN product sheet: https://service.somfy.com/downloads/bui_v4/j4-1tn.pdf
- S13 — Griesser, wind fact sheet, external venetian blinds (ES): https://www.griesser.com/ch/wp-content/uploads/2026/03/Wind-fact-sheet-ES_External-venetian-blinds_en.pdf
- S14 — Elsner, KNX W wind sensor manual: https://info.elsner-elektronik.de/hubfs/70123_KNX_W_Manual_EN.pdf
- S15 — Open-Meteo, Weather Forecast API docs: https://open-meteo.com/en/docs
- S16 — SparkFun, Weather Meter Hookup Guide: https://learn.sparkfun.com/tutorials/weather-meter-hookup-guide/all
- S17 — SERVIS CLIMAX a.s., "Venkovní žaluzie — návod na obsluhu a údržbu", 07/2016 (hosted by a dealer): https://www.palacb.cz/wp-content/uploads/2016/12/Venkovn%C3%AD_%C5%BEaluzie_N%C3%A1vod_na_obsluhu_a_%C3%BAdr%C5%BEbu_CZ.pdf
- S18 — WMO, Guide to Instruments and Methods of Observation (CIMO Guide, 2018 prelim.), Vol. I ch. 5, Measurement of surface wind: https://old.wmo.int/extranet/pages/prog/www/IMOP/publications/CIMO-Guide/Prelim_2018_ed/8_I_5_en_MR_tc.pdf
