# 01 — Lights

**Research, not design.** Matter On/Off Light, Dimmable Light, Color Temperature Light and Extended Color Light: what the spec requires, how real devices and controllers behave, Apple Home support. Feeds 12c's light sections.

Spec data from the connectedhomeip data model, `data_model/1.4/` (S1) — 1.5 added no light changes known to us [I].

## 1. Device types

All four are endpoint-scoped simple devices, each a superset of the one above it [V-src S1].

| Device type | On/Off | Level Control | Color Control | Groups, Identify | Scenes Mgmt |
|---|---|---|---|---|---|
| On/Off Light `0x0100` | M, LT | **O** (if present: OO + LT) | — | M | provisional |
| Dimmable Light `0x0101` | M, LT | M, OO + LT | — | M | provisional |
| Color Temperature Light `0x010C` | M, LT | M, OO + LT | M: CT | M | provisional |
| Extended Color Light `0x010D` | M, LT | M, OO + LT | M: XY + CT; HS, EHUE, CL optional | M | provisional |

- Every light: `CurrentLevel` 1–254, `MinLevel` 1, `MaxLevel` 254 when Level Control is present [V-src S1]. **There is no level 0** — off is `OnOff`, not a level.
- Identify's `TriggerEffect` is mandatory [V-src S1].
- Occupancy Sensing client is optional on every light [V-src S1].
- Home Assistant ignores an optional Level Control on an On/Off Light [V-src S4].

## 2. On/Off cluster with Lighting (LT) feature

LT makes these mandatory [V-src S2]:

| Element | What it does |
|---|---|
| `OnOff` | the state |
| `GlobalSceneControl`, `OnWithRecallGlobalScene` | remember the state before an "all off" and recall it |
| `OffWithEffect` | `DelayedAllOff` (fade 0.8 s / no fade / dim 50 % then fade 12 s), `DyingLight` |
| `OnTime`, `OffWaitTime`, `OnWithTimedOff` | on for `OnTime`, then off; `OffWaitTime` blocks a new On after that. 1/10 s units [V S3]. Flag `AcceptOnlyWhenOn`. A **timer relay built into the light** |
| `StartUpOnOff` | after power loss: off, on, toggle or null = previous |

## 3. Level Control with OnOff (OO) + Lighting (LT)

| Element | Notes [V-src S2] |
|---|---|
| `CurrentLevel` | uint8, nullable, kept across power loss, **quieter reporting** (§5) |
| `RemainingTime` | time left of a transition. Mandatory with LT |
| `OnLevel` | level used by On; null = last level. Mandatory |
| `OnOffTransitionTime`, `OnTransitionTime`, `OffTransitionTime` | optional default transition times |
| `DefaultMoveRate` | optional |
| `StartUpCurrentLevel` | after power loss. Mandatory with LT |
| `Options` | `ExecuteIfOff` (accept level change while off), `CoupleColorTempToLevel` (warm dimming) |
| Commands | `MoveToLevel`, `Move` (rate, up/down), `Step`, `Stop`, and `…WithOnOff` variants — all mandatory |

Transition time is in 1/10 s [V S4: Home Assistant sends `transition * 10`]. The `…WithOnOff` variants switch the light on when the level goes above minimum, and off at minimum [I].

### 3.1. What On, Off and level commands do to the level

| Command | Effect on `CurrentLevel` / `OnOff` |
|---|---|
| `On` | stores `CurrentLevel`, then moves to `OnLevel`, or to the stored level when `OnLevel` is null, over `OnTransitionTime` (else `OnOffTransitionTime`) [V S14] |
| `Off` | stores `CurrentLevel`, fades to `MinLevel` over `OffTransitionTime`, sets `OnOff` false; with `OnLevel` null `CurrentLevel` returns to the stored level — so while off it still holds the last level [I] |
| `On` during an `Off` fade | the level stored by that `Off` is restored [V S14] |
| `MoveToLevelWithOnOff`, `MoveWithOnOff`, `StepWithOnOff` | above `MinLevel` → `OnOff` true; reaching `MinLevel` → `OnOff` false [I] |
| `MoveToLevel`, `Move`, `Step` while off | ignored, unless `Options.ExecuteIfOff` (or the command's `OptionsOverride`) is set — then the level changes and the light stays off [I] |
| `Toggle` | `On` or `Off` |

connectedhomeip fixed its `On` target in 2026-09: before, it used the level saved by the last `Off` (or `MaxLevel`), and a level set while off was ignored [V S14].

### 3.2. Transition time per command

| Command | Timing field | Notes |
|---|---|---|
| `On`, `Off`, `Toggle` | none | use the `On/Off/OnOffTransitionTime` attributes |
| `MoveToLevel(WithOnOff)`, `Step(WithOnOff)` | `TransitionTime`, mandatory field, nullable [V-src S2] | null → `OnOffTransitionTime`, else as fast as the device can [I] |
| `Move(WithOnOff)` | `Rate` (units/s), nullable [V-src S2] | null → `DefaultMoveRate` [I] |
| Color Control `MoveTo…`, `Step…` | `TransitionTime`, mandatory, not nullable, ≤ 65534 [V-src S2] | |

Unit 1/10 s. Home Assistant sends `transition × 10`, 0 when no transition is asked [V-src S4].

## 4. Color Control

| Feature | Attributes | Commands [V-src S2] |
|---|---|---|
| CT | `ColorTemperatureMireds` (≤ 65279), `ColorTempPhysicalMin/MaxMireds`, `CoupleColorTempToLevelMinMireds`, `StartUpColorTemperatureMireds` | `MoveToColorTemperature`, `MoveColorTemperature`, `StepColorTemperature`, `StopMoveStep` |
| XY | `CurrentX`, `CurrentY` (0–65279, CIE 1931 × 65536) | `MoveToColor`, `MoveColor`, `StepColor` |
| HS | `CurrentHue`, `CurrentSaturation` (0–254) | `MoveToHue`, `MoveToSaturation`, `MoveToHueAndSaturation`, … |
| EHUE, CL | 16-bit hue, color loop | `EnhancedMoveToHue`, `ColorLoopSet` |

- `ColorMode` / `EnhancedColorMode` say which of HS, XY or CT is the current source of truth [V-src S2].
- `ColorCapabilities` bitmap lists the supported features; Home Assistant reads it to choose HS > XY > CT [V-src S4].
- Mired = 1 000 000 / K. DALI DT8 Tc uses mirek too, so CT maps without conversion [V S6].

## 5. Reporting while a light moves

connectedhomeip marks these changes reportable [V-src S5]:

- `CurrentLevel` and every Color Control value: at most once per second, at the end of the transition, and when it changes to or from null. (Reporting at the *start* of a transition was removed.)
- `RemainingTime`: when it changes to 0, from 0 to more than 10, or by more than 10 because of a command.

So a controller sees intermediate values about once a second during a fade, and the final value at its end. Nothing in the spec requires `CurrentLevel` to jump to the target at once [I]. A light that does — reporting the target immediately — is still within the rules, since "at the end" is the only mandatory report [I].

## 6. Real devices and experiences

| Device / case | What happened |
|---|---|
| Philips Hue Bridge (Matter bridge) | Dimmed lights jumped to full brightness. Bridge firmware fix, 2024 [V S7] |
| Inovelli White Series dimmer | Apple Home "turn on at 35 %" turned the light on at the previous level (80 %); a second run worked. Later firmware fixed it [V S8]. Shows how on-level handling (`OnLevel`, `…WithOnOff`, `ExecuteIfOff`) matters |
| Espressif Matter 1.0 lights | Transition bug — Home Assistant keeps a blocklist and sends transition 0 to them [V-src S4] |
| Innovation matters M2D Bridge (DALI → Matter, Wi-Fi) | Up to 8 DALI drivers, DT6 and DT8, broadcast only, one endpoint. Matter 1.4 certified 2025 [V S9]. No per-gear endpoints |
| Philips Dynalite, Atios | Professional DALI/KNX ↔ Matter bridges exist [V S10] |
| DALI ↔ Matter mapping (Espressif DALI component) | `OnOff`/`CurrentLevel` → DALI `OFF`/`RECALL`/`DAPC`; Matter's transition vs DALI fade: use the gear's stored fade, set a fade time, or step DAPC; clamp CT to gear limits and write back the applied value [V S6] |

**A DALI LED dimmer as a template source** — "Universal series DALI dimmer", 4 channels (manual 54, item 70040010), the kind of gear `tunable-white-2dali` and `tunable-rgbw-4dali` drive [V S15]:

- DALI-2, **DT6** (IEC 62386-101/102/207 Ed2) — no DT8: each channel is a plain dimmable gear. Tunable white and RGBW are separate short addresses mixed by the controller.
- Dimming range 0.1–100 % — the standard logarithmic curve's range (arc 1 = 0.1 %) [I: the manual doesn't name the curve].
- Address modes 1A–4A: one address for all channels, channels 1+3 / 2+4 paired, … or one per channel. `4A` gives four `dali.gear`s.
- CW/WW or RGBW colour points are the strip's, not the dimmer's: the dimmer knows nothing about colour.
- Push-dim mode keeps its state across power loss; in DALI mode the standard power-on level applies [I].
- Part 207 also defines an optional linear dimming curve, `SELECT DIMMING CURVE` / `QUERY DIMMING CURVE` (DT6 extended commands) [I]. Whether this dimmer supports it: [GAP]. `driver-dali` doesn't send either.

Matter does not define a dimming curve: what `CurrentLevel` 127 looks like is the device's [I]. DALI's 1–254 is logarithmic (IEC 62386). Passing 1–254 straight through keeps DALI's curve [I].

## 7. Apple Home

| Topic | Finding |
|---|---|
| Device types | On/Off, Dimmable, Color Temperature and Extended Color Light all supported [V S11] |
| Dimmer switches | Apple supports only Generic Switch as a control device; no binding of a dimmer to a light's level [V S12] |
| Long-press dimming | The Home app has no Move/Stop control; it sets levels [I] |
| Adaptive Lighting over Matter | iOS 26+, accessory on Matter 1.4+, physical CT range at least 200–370 mired (≈ 2700–5000 K), recommended 178–500. Test plans cited are Extended Color Light, CT and RGB validation [V S13]. Whether a pure Color Temperature Light qualifies: [GAP] |
| Which color commands Apple sends (HS vs XY) | [GAP] |
| Transition times Apple sends | [GAP] |

## 8. Sources

- S1 — connectedhomeip `data_model/1.4/device_types/` (OnOffLight, DimmableLight, ColorTemperatureLight, ExtendedColorLight .xml): https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/data_model/1.4/device_types/DimmableLight.xml
- S2 — connectedhomeip `data_model/1.4/clusters/` OnOff.xml, LevelControl.xml, ColorControl.xml: https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/data_model/1.4/clusters/LevelControl.xml
- S3 — Z-Way manual, Matter clusters reference (OnOff): https://z-wave.me/manual/z-way/Matter_Clusters_Reference.html
- S4 — Home Assistant `components/matter/light.py`: https://git.sudo.is/home-assistant/core/src/branch/dev/homeassistant/components/matter/light.py
- S5 — connectedhomeip commit "Update Quiet reporting conditions for LVL and CC remaining time attribute (#35224)": https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+/3b83878fc839320a97460a722138068bd18c9225%5E%21
- S6 — Espressif, "DALI component for lighting systems" (2026-08): https://developer.espressif.com/blog/2026/08/dali-component-lighting-systems/
- S7 — Hueblog, Matter problems firmware fix (2024-07-13): https://hueblog.com/2024/07/13/matter-problems-firmware-update-is-already-being-rolled-out/
- S8 — Inovelli community, "White Series won't turn on at given brightness": https://community.inovelli.com/t/white-series-wont-turn-on-at-given-brightness/19106
- S9 — Matter Alpha, Innovation matters M2D Bridge: https://www.matteralpha.com/innovation-matters/innovation-matters-m2d-bridge-p221
- S10 — matter-smarthome.de, Philips Dynalite and Atios: https://matter-smarthome.de/en/products/professional-installations-with-matter-from-philips-dynalite/
- S11 — connectedhomeip `docs/guides/darwin.md`: https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/docs/guides/darwin.md
- S12 — Nordic DevZone, dimmer switch via Level cluster in Apple Home: https://devzone.nordicsemi.com/f/nordic-q-a/121589/seeking-workaround-for-dimmer-switch-control-via-level-cluster-in-apple-home/536098
- S13 — Apple, Adaptive Lighting over Matter Accessory Requirements: https://developer.apple.com/apple-home/downloads/Adaptive-Lighting-over-Matter-Accessory-Requirements.pdf
- S14 — connectedhomeip PR #74405, "[LevelControl] Use CurrentLevel as the On target when OnLevel is null" (merged 2026-09-25): https://github.com/project-chip/connectedhomeip/pull/74405
- S15 — manufacturer manual "Universal series DALI dimmer" (manual_54_en.pdf, item 70040010), supplied by Tomas.
