# 07 — Garage door

**Research, not design.** What Matter defines for a garage door, what controllers do with it, how a Hörmann drive behind a UAP1-HCP is driven from Unipi I/O, and what other systems and standards require before a door moves on a remote command. Feeds 12c's `GarageDoor` section.

Input from Tomas (2026-10-25):

- Drive: Hörmann SupraMatic E/P Series 4 with a UAP1-HCP adapter board.
- UAP relays K01 (end position open) and K02 (end position closed) go to two `unipi.di`.
- Three `unipi.ro` give open, close and stop — each a short closing of a potential-free contact (NO pulse), stop included.
- K03 could go to a third DI.
- Later: security like `DoorLock` (13a, M3.6).

Spec data from connectedhomeip `data_model/1.5/` and `1.7/` (S1); spec prose from matter.js's generated cluster docs, which cite Matter 1.6.1 (S2).

## 1. Matter

### 1.1. Device type

- Up to 1.4 there is no garage door device type: "no Matter support for garage door openers as of Matter 1.4" [V S9]. Products used Window Covering instead — Konnected: "the GDO White will appear in your Matter controller app as blinds or shades!" [V S10].
- 1.5 adds **Closure `0x0230`**: Identify and Closure Control `0x0104` mandatory; Window Covering and Closure Dimension disallowed [V-src S1]. Same type as the window-covering note's §1.5 ([06](06-window-covering.md)).
- What kind of closure it is comes from a semantic tag, namespace Closure `0x44`: `GarageDoor` "A large, movable barrier that provides access to a garage"; also `Gate`, `Door`, `Barrier`, `Window`, `Covering`, `Cabinet` [V-src S1].

### 1.2. Closure Control features

| Feature | Code | Fit for a door with end switches only [I] |
|---|---|---|
| Positioning | `PS` | yes — discrete positions, not %: at least fully open and fully closed |
| MotionLatching | `LT` | no latch on the door |
| Instantaneous | `IS` | no — without `IS`, `Stop`, `MovementCompleted` are mandatory |
| Speed | `SP` | no |
| Ventilation | `VT` | drive has a vent position; needs an RO on that input |
| Pedestrian | `PD` | no |
| Calibration | `CL` | no |
| Protection | `PT` | lockouts (§5) |
| ManuallyOperable | `MO` | the drive can be disengaged by hand (§3.3) |

All codes [V-src S1, 1.5].

### 1.3. State

- `MainState`: `Stopped`, `Moving`, `WaitingForMotion` ("e.g. pre-heat, pre-check"), `Error`, `Calibrating` (`CL`), `Protected` ("Commands MAY be rejected", `PT`), `Disengaged` (`MO`), `SetupRequired` [V-src S1].
- `OverallCurrentState` (nullable): `Position` — `FullyClosed`, `FullyOpened`, `PartiallyOpened`, `OpenedForPedestrian`, `OpenedForVentilation`, `OpenedAtSignature`; `Latch`; `Speed`; **`SecureState`** (mandatory, nullable bool) [V-src S1]. Null: "the state is unknown", e.g. "lost its Position/Latch state after manual motion" [V S2].
- `SecureStateChanged` event: true "when the closure is in a secure state, e.g. unauthorized/undetectable access is not possible" [V S2].
- `OverallTargetState` (nullable): target `Position` (`MoveToFullyClosed`, `MoveToFullyOpen`, …) [V-src S1]. Null "after a reboot" [V S2].
- `CountdownTime`: seconds left, quieter reporting — "Changes … merely due to the normal passage of time … shall NOT be reported" [V S2].
- `CurrentErrorList` and the critical `OperationalError` event, `ClosureErrorEnum`: `PhysicallyBlocked`, `BlockedBySensor` ("e.g. photoelectric sensor"), `TemperatureLimited`, `MaintenanceRequired`, `InternalInterference` ("an integrated door within a bigger garage door is open") [V-src S1].
- Signature position: "Gate, Garage Door -> Pedestrian and pets, or one leaf only"; without one, it means `FullyOpened` [V S2].

### 1.4. Commands

| Command | Access | Effect |
|---|---|---|
| `Stop` | operate | stops `Moving`/`WaitingForMotion`/`Calibrating`; "A status code of SUCCESS shall always be returned" [V S2] |
| `MoveTo(position?, latch?, speed?)` | operate, **timed** | to a `TargetPositionEnum`; fields of unsupported features ignored [V-src S1, V S2] |
| `Calibrate` | manage, timed | `CL` only [V-src S1] |

- Timed invoke on `MoveTo` is the same protection Door Lock's `LockDoor`/`UnlockDoor` have; Window Covering's commands have none [V-src S1].
- No open-only or close-only access level: one `operate` privilege for both directions [V-src S1].

### 1.5. Matter 1.7: Access

- Closure Control revision 2 adds feature `ACC` Access — "The closure can grant access to a secured building or restricted area" — and command `GroupedMoveTo`, mandatory only without `ACC` [V-src S1, 1.7].
- Closure device type revision 2 adds condition `AccessDevice`; with it, `ACC` is mandatory [V-src S1, 1.7]. The Root Node's groupcast-listener requirement is mandatory or optional only *without* `AccessDevice` [V-src S1, 1.7] — read: an access device does not listen to group commands [I].
- Both marked provisional [V-src S1, 1.7].

### 1.6. matter.js

`ClosureControlServer` is a generated, empty subclass of the behaviour — no command logic, unlike `WindowCoveringServer` ([06 §1](06-window-covering.md)) [V-src S3]. The Closure device type is generated (`devices/closure.ts`) [V-src S3].

## 2. Controllers

| Controller | Closure `0x0230` | Notes |
|---|---|---|
| Apple Home | [GAP] — nothing found | HomeKit's own Garage Door Opener service: `CurrentDoorState` open/closed/opening/closing/stopped, `TargetDoorState` open/closed only, `ObstructionDetected`; optional lock state [V-src S4]. Users report authentication asked before opening in location automations, not for closing; not for CarPlay or NFC triggers (2019) [V S5] |
| Google Home | [GAP] | HA's Google Assistant link: garage doors need a PIN to **open**; "Closing and locking don't require one" [V S6] |
| SmartThings | works, per Tasmota PR and HA discussion (Aug–Sep 2026) [V S7, S8] | |
| Home Assistant | Closure devices "aren't discovered at all today" (Jul 2026) [V S8] | cover `device_class` `garage`; `is_opening`/`is_closing`; `is_closed` None ⇒ `unknown`; position optional [V S11] |
| Tasmota | Garage Door plugin on Closure Control, `MainState`, `OverallCurrentState`, `Stop`, `MoveTo`; merged as PR #25089 [V S7] | |

**Window Covering as a fallback has a known failure:** through HA's Matter hub to Google, "open all blinds" also opened the garage door; the hub had no garage type and exported it as a cover (Mar 2026) [V S12].

## 3. Hörmann UAP1-HCP on a SupraMatic 4

### 3.1. Inputs

| UAP terminals | Function |
|---|---|
| 15 – 20 | open |
| 17 – 20 | close |
| 23 – 20 | partial opening |
| 10 – 20 | drive light on/off |
| ? – 20 | stop — terminal [GAP] |

- Terminals for UAP 1 [V S13]; "Die Belegung passt auch zu der aktualisierten Variante UAP1 HCP" [V S14]. The HCP variant lists six inputs: open, close, partial, vent position, light, stop [V S15].
- Only potential-free NO contacts; "Auf keinen Fall darf auf diese Steuereingänge eine Spannung angelegt werden" [V S15].
- Pulse length: not in the manual (S16 is drawings only) [GAP]. Seen in use: 1 s (FHEM, ESP) [V S17]; 0.5 s default pulse in Loxone's gate block [V S18].
- Open input ≈ 21 V, ≈ 4.8 mA when pulled down — reported second-hand [V S17].
- An open on 23–20 instead of 15–20 gives only the short partial move — one user's wiring mix-up [V S19].
- A held (not pulsed) input, and open while closing: [GAP].
- Also shown: an RSK (closed-circuit stop loop); red LED blinks 4× when it is interrupted [V S16]. Tomas's stop is a NO pulse, not the RSK.

### 3.2. Outputs

- Three changeover relays: **01 = end position open, 02 = end position closed**, 03 = option relay [V S13, S15]. Rated 30 V DC / 2.5 A, 250 V AC / 500 W, resistive [V S15].
- The drive's menu 30 sets the option relay (UAP "3. Relais") [V S20]:

  | Value | Function |
  |---|---|
  | 02 / 03 | end position open / closed |
  | 04 | partial-opening end position |
  | 05 | wipe pulse on a command |
  | 06 | fault (as on display) |
  | 07 / 08 | pre-warning, steady / flashing |
  | **09** | **relay on during travel** |
  | 10 | maintenance due |

- UAP supply: 24 V DC, max 100 mA, from the drive [V S16]; all accessories ≤ 350 mA on the drive [V S20].

### 3.3. Drive behaviour (SupraMatic 4, TR10A359-B)

- Impulse sequence: "Bei jeder Betätigung startet das Tor entgegen der letzten Fahrtrichtung oder eine Torfahrt stoppt" [V S20]. Separate open and close: direction selection, also offered to the BiSecur app and remotes [V S20].
- Safety reverse on force limit, photocell or closing-edge sensor; no reverse inside the reversing limit [V S20]. Force limit: Cat. 2, PL c, EN ISO 13849-1 [V S20].
- Reference run: reduced speed to the open end "um die Grundstellung festzulegen" [V S20]. ProMatic 4: after the force limit trips 3× in a row closing [V S21]. What a SupraMatic does after a power failure: [GAP] — §11 not readable in S20.
- Pre-warning (menus 32/33): the drive light flashes for 00–60 s before any travel; close only, or both directions [V S20].
- Automatic close (menus 34/35): only with a photocell taught in, as EN 12453 requires [V S20].
- Wicket door contact open during a run: stops at once and blocks [V S20].
- "Sie müssen den Handsender generell mit Sichtkontakt zum Tor bedienen, wenn nur eine Sicherheitseinrichtung vorhanden ist!" [V S20].
- Travel speed, ProMatic 4: max 20 cm/s open, 14 cm/s close [V S21]; SupraMatic: [GAP]. A 2.2 m door then takes ≥ 11 s / ≥ 16 s [I].
- Other command sources stay active: hand remotes, wall buttons (impulse, terminal 21), BiSecur app [V S20]. evok-node sees their moves only through K01/K02 (and K03) [I].

### 3.4. State from K01 / K02 / K03

| K01 | K02 | K03 = 09 | State [I] |
|---|---|---|---|
| 1 | 0 | 0 | open |
| 0 | 1 | 0 | closed |
| 0 | 0 | 1 | moving; direction = from the end just left, or the last command |
| 0 | 0 | 0 | stopped between ends (without K03: moving or stopped, undecidable) |
| 1 | 1 | – | impossible ⇒ fault (wiring, relay) |

- A move started elsewhere is seen when an end relay drops [I]. A reversal (safety reverse) shows only as the other end being reached, or K03 dropping without an end [I].
- No % position. Time since leaving an end gives an estimate; a door stopped in the middle has an unknown position [I].

### 3.5. Bus alternative

ESPHome's `hoermann_hcp` emulates the UAP1 on the HCP bus (Modbus RTU, 57600 8E1, Series 4 only) and gets door state, position, vent and half-open [V S22]. Risks: "Disrupting Modbus connectivity for any reason may render the motor temporarily inoperable"; then the motor ignores all controls, remotes included, until a power cycle; a restart of the emulator triggers it [V S22]. Contacts on the UAP avoid this [I].

## 4. Prior art — doors with end switches

| | Inputs | Outputs | Timing | Other |
|---|---|---|---|---|
| ESPHome Endstop Cover (S23) | `open_endstop`, `close_endstop` | `open_action`, `close_action`, `stop_action` | `open_duration`, `close_duration` for an estimated position; `max_duration` "protecting from dysfunctional endstops" | endstop reached ⇒ `stop_action` |
| Loxone Garage/Gate (S18) | `Tg` toggle, `Co`/`Cc` open/close (moving ⇒ stop), `Io`/`Ic` end switches, `Off` (< 200 ms stop, longer locks), `Spo`/`Spc` inhibit, `DisPc` disables local inputs, `Po` partial | `Op`, `Cl`, `Tg` as pulses ("Separate Controller") or levels ("Direct"); `Im` in motion; `Pos` 0–1; `Wl` warning light | `Opd`/`Cld` 60 s; pulse `Pd` 0.5 s; `Mld` 0.5 s between directions | `Rem` keeps state over reboot |
| HomeKit (S4) | — | — | — | target only open/closed; `stopped` is a current state |
| Konnected (S10) | optical sensor | — | pre-close warning, "default and minimum … 5 seconds" | Window Covering on Matter |

All [V] from the source in the row.

## 5. Safety and access

### 5.1. Standards

- **UL 325 (US), unattended operation** — a smartphone opening or closing a door counts: audible and visual alert ≥ 5 s before an unattended close; after two failed unattended closes, lock out; not on operators without photo-eyes. Secondary source, not the standard's text [V S24].
- **EN 12453 (EU)**: automatic close needs an extra safety device (photocell) — as Hörmann applies it [V S20]. Remote operation in general: [GAP] — standard not read.
- Hörmann: operate within sight when only one safety device is fitted (§3.3) [V S20].

### 5.2. Open vs close

| Source | Open | Close |
|---|---|---|
| Google (via HA) | PIN required | no PIN [V S6] |
| Apple (users, 2019) | authentication in location automations | none [V S5] |
| UL 325 | — | 5 s warning [V S24] |
| Matter | timed invoke, same privilege both ways | same [V-src S1] |
| Door Lock (for 13a) | `RequirePINforRemoteOperation` attribute exists [V-src S1] | — |

Open grants access; close removes it but can hurt someone [I].

### 5.3. Failure

- A pulse relay left on when the daemon dies: the master watchdog reboots the section into its saved defaults (research/02 §4.8) [V]; relay then off [I]. A held open/close/stop input on the UAP: [GAP] (§3.1).
- Stop and a direction pulse at the same time: [GAP]. Interlock as for covers ([06 §3.3](06-window-covering.md)) [I].

## 6. evok-node today

| Where | What |
|---|---|
| 12a §2.2 | no `GarageDoor`; `WindowCovering`, `DoorLock` (`state` locked/unlocked/jammed/unknown) |
| 12c memo | no `GarageDoor`; `DoorLock`: "PIN and assurance level → 13a (M3.6)" |
| research/matter/04 §3 | garage door, door and window are all one Contact Sensor |
| 16a | `WindowCovering` → Window Covering, `DoorLock` → Door Lock |

## 7. Proposals for 12c (not binding)

- **P1 — own type `GarageDoor`**, not a `WindowCovering` variant: discrete states, other commands, other access rules (§1.1, §2 fallback failure).
- **P2 — fields.** `state` reading `{current, target, motion}` with `current` `open`/`closed`/`partial`/`unknown`, `target` `open`/`closed`/null, `motion` `opening`/`closing`/`stopped` — the moving-device pattern in the 12c memo; `obstructed` / `fault` reading; methods `open`, `close`, `stop`. Position % only if a later template has one.
- **P3 — template `garage-from-contacts`.** Roles: `openEnd`, `closedEnd` (DI), optional `moving` (DI on K03 = 09); `openCmd`, `closeCmd`, `stopCmd` (RO). Settings: pulse length (default 0.5–1 s, §3.1), `travelMs` timeout per direction, input polarity. Workflow per §3.4.
- **P4 — timeout.** No end reached within `travelMs` + margin ⇒ `fault` (ESPHome `max_duration`); K01 = K02 = 1 ⇒ `fault`.
- **P5 — moves from elsewhere** update `state` from the relays; a command in flight is not assumed done until an end is reached [I].
- **P6 — Matter projection.** Closure `0x0230`, tag `GarageDoor`, features `PS` (+ `PT` for lockouts; `VT` if a vent RO is added); `SecureState` = closed; `MainState` from `motion`; `PhysicallyBlocked` from `obstructed`. Window Covering fallback only behind a setting, given §2. Apple support: unknown (§2).
- **P7 — access (to 13a).** Open needs the higher assurance level, close the lower one (§5.2); rules may close freely, opening by a rule needs explicit consent. Remote close warns first — the drive's own pre-warning (menus 32/33) covers every source, a light/buzzer role does not [I].
- **P8 — lockouts.** A `locked` setting/role blocks evok-node's commands (Loxone `Off`/`DisPc`); the drive's own inputs stay active (§3.3).

## 8. Sources

- S1 — connectedhomeip `data_model/1.5/`, `1.7/` at commit `645b267` (2026-10-24): `clusters/ClosureControl.xml`, `DoorLock.xml`, `WindowCovering.xml`; `device_types/Closure.xml`; `namespaces/Namespace-Closure.xml`: https://github.com/project-chip/connectedhomeip/tree/master/data_model
- S2 — matter.js `packages/types/src/clusters/closure-control.d.ts` (spec 1.6.1 prose), commit `aec864d` (2026-10-22): https://github.com/project-chip/matter.js/blob/main/packages/types/src/clusters/closure-control.d.ts
- S3 — matter.js `packages/node/src/behaviors/closure-control/ClosureControlServer.ts`, same commit: https://github.com/project-chip/matter.js/tree/main/packages/node/src/behaviors/closure-control
- S4 — HAP-NodeJS `src/lib/definitions/` (`GarageDoorOpener`, `CurrentDoorState`, `TargetDoorState`), commit `f1d8ee7`: https://github.com/homebridge/HAP-NodeJS/tree/master/src/lib/definitions
- S5 — MacRumors forum, "Opening a HomeKit garage door without authentication to Run scene" (Dec 2019): https://forums.macrumors.com/threads/opening-a-homekit-garage-door-without-authentication-to-run-scene.2214845/
- S6 — Nabu Casa, Google Assistant secure devices: https://support.nabucasa.com/hc/en-us/articles/25619376817053
- S7 — Tasmota PR #25080, "Add Garage Door device type via Closure (Matter 1.5.0+)": https://github.com/arendst/Tasmota/pull/25080
- S8 — Home Assistant discussion #2151, "Support Matter Closure Devices": https://github.com/orgs/home-assistant/discussions/2151
- S9 — Matter Alpha, "Can Matter finally fix smart garage door systems?" (Nov 2024): https://www.matteralpha.com/explainer/matter-integrated-garage-door-openers
- S10 — Konnected, "Getting started with Matter on the GDO White": https://support.konnected.io/matter-gdo-white
- S11 — Home Assistant developer docs, Cover entity: https://contributors.home-assistant.io/core/entities/cover/
- S12 — KNX-User-Forum, "Garagentor nicht als Cover behandeln" (Mar 2026): https://knx-user-forum.de/forum/projektforen/home-assistant/2083537-garagentor-nicht-als-cover-behandeln
- S13 — tor7, "Wie wird die Universaladapterplatine UAP 1 am SupraMatic Serie 3 angeschlossen?": https://www.tor7.de/frag-tor7/wie-wird-die-universaladapterplatine-uap-1-am-supramatic-serie-3-angeschlossen
- S14 — LoxWiki, Garagentorantriebe, Hörmann: https://loxwiki.atlassian.net/wiki/spaces/LOX/pages/1516634754/Garagentorantriebe
- S15 — tor7, product page UAP 1-HCP: https://www.tor7.de/hoermann-universaladapterplatine-uap-1-hcp
- S16 — Hörmann, UAP 1-HCP manual TR30A118-A / 02.2020 (drawings, LED table): https://www.tor7.de/media/pdf/92/53/6d/hoermann-universaladapterplatine-uap-1-hcp-anleitung.pdf
- S17 — Frank Schütz, "Hörmann Torantrieb mit ESPEasy in FHEM einbinden": https://www.frank-schuetz.de/index.php/fhem/13-hoermann-torantrieb-mit-espeasy-in-fhem-einbinden
- S18 — Loxone, Garage/Gate: https://www.loxone.com/enen/kb/garagegate/
- S19 — KNX-User-Forum, "Hörmann Supramatic UAP1 konventionelle Taster", p. 3 (Oct 2013): https://knx-user-forum.de/forum/öffentlicher-bereich/knx-eib-forum/21178-hörmann-supramatic-uap1-konventionelle-taster?p=462772
- S20 — Hörmann, SupraMatic Series 4 manual TR10A359-B / 07.2019 (DE), §1.3, §2.9, §4.2, §6.1.12–6.1.15, §8: https://www.tor7.de/media/pdf/f0/09/e1/hoermann-supramatic-e-4-anleitung.pdf
- S21 — Hörmann, ProMatic 4 manual TR10A378-A / 10.2019 (EN), §10.6, §17: https://easyfitgaragedoor.co.uk/wp-content/uploads/2021/05/Hormann-ProMatic-4-Operator-Fitting-Instructions.pdf
- S22 — ESPHome, Hörmann Cover: https://esphome.io/components/cover/hoermann_hcp/
- S23 — ESPHome, Endstop Cover: https://esphome.io/components/cover/endstop/
- S24 — G. Matias (Genie), "Unattended Operation", Door + Access Systems, Summer 2020: https://www.dasma.com/wp-content/uploads/pdfs/features/UnattendedOperation_Summer2020.pdf
