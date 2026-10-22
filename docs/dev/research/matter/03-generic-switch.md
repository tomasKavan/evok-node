# 03 — Generic Switch

**Research, not design.** Matter Generic Switch and its Switch cluster: what the spec requires, the event sequences, timing, how matter.js and controllers handle it, real devices, and what our source drivers can deliver. Feeds 12c's `GenericSwitch` section and the press handling in 12b.

Spec data from the connectedhomeip data model, `data_model/1.5/` (S1, S2). Expected event sequences from the certification test script (S3). Spec prose from matter.js, generated from Matter 1.6.1 (S4, S5).

## 1. Device type

| Device type | Since | Server clusters | Revision |
|---|---|---|---|
| Generic Switch `0x000F` | 1.0 | Identify M, Switch M | 3 [V-src S1] |

- A sensor-like device: it **sends** interaction events; it controls nothing itself [V S4]. Switching a light directly is the On/Off Light Switch type (`0x0103`, On/Off client) [V S7]; with a Generic Switch the controller's automation does it [I].
- Revision 2 replaced the mandatory Fixed Label cluster with Descriptor `TagList` [V-src S1]. A node with several switches exposes **one endpoint per switch**, and each such endpoint **shall** carry a `TagList` [V S4, S11].
- Attribute updates are sent for a latching switch only; a momentary switch is described by its events [V S4].

## 2. Switch cluster `0x003B`, revision 2

### 2.1. Features

| Bit | Feature | Conformance [V-src S2] | Meaning |
|---|---|---|---|
| 0 | `LS` LatchingSwitch | O.a | stays in its position: rocker, rotary |
| 1 | `MS` MomentarySwitch | O.a | returns to idle (position 0) on release: push button |
| 2 | `MSR` MomentarySwitchRelease | `MS & !AS` | reports `ShortRelease` |
| 3 | `MSL` MomentarySwitchLongPress | `MS & (MSR \| AS)` | reports `LongPress`, `LongRelease` |
| 4 | `MSM` MomentarySwitchMultiPress | M if `AS`; else `MS & MSR` | counts presses, reports `MultiPressComplete` |
| 5 | `AS` ActionSwitch — **since 1.4** | `MS` | "simplified handling of events for multi-press-capable switches" [V S5] |

`LS` and `MS` share choice group `a` [V-src S2]: a switch is latching or momentary, never both [I — standard reading of `O.a`].

### 2.2. Attributes

| Attribute | Type | Conformance | Notes [V-src S2] |
|---|---|---|---|
| `NumberOfPositions` `0x0000` | uint8, min 2, fixed | M | 2 for a plain button |
| `CurrentPosition` `0x0001` | uint8, ≤ `NumberOfPositions` − 1 | M | 0 = idle / default position [V S5] |
| `MultiPressMax` `0x0002` | uint8, min 2, fixed | `MSM` | presses the device can count |

### 2.3. Events

| Event | Fields | Conformance [V-src S2] |
|---|---|---|
| `SwitchLatched` `0x00` | `NewPosition` | `LS` |
| `InitialPress` `0x01` | `NewPosition` | `MS` |
| `LongPress` `0x02` | `NewPosition` | `MSL` |
| `ShortRelease` `0x03` | `PreviousPosition` | `MSR` |
| `LongRelease` `0x04` | `PreviousPosition` | `MSL` |
| `MultiPressOngoing` `0x05` | `NewPosition`, `CurrentNumberOfPressesCounted` (2 … max) | `MSM & !AS` |
| `MultiPressComplete` `0x06` | `PreviousPosition`, `TotalNumberOfPressesCounted` (0 … max) | `MSM` |

Revision 2 (Matter 1.4) added `AS`, clarified ambiguous event combinations, and added `TotalNumberOfPressesCounted = 0` for a sequence that went over `MultiPressMax` [V-src S2]. Matter 1.3 has revision 1, without `AS` [V-src S2].

## 3. Event sequences

What the certification tests expect (TC-SWTCH-2.2 … 2.6) [V-src S3]. `[ShortRelease]` = only with `MSR`.

**Without multi-press (`MS`, `MSR`, `MSL`):**

| Gesture | Events |
|---|---|
| short press | `InitialPress(1)` · `ShortRelease(1)` |
| long press | `InitialPress(1)` · `LongPress(1)` · `LongRelease(1)` |
| `MS` only | `InitialPress(1)`, nothing on release |

**With `MSM`, without `AS`:**

| Gesture | Events | `MultiPressComplete` total |
|---|---|---|
| single | `InitialPress` · [`ShortRelease`] · … idle … | 1 |
| double | `InitialPress` · [`ShortRelease`] · `InitialPress` · `MultiPressOngoing(2)` · [`ShortRelease`] · … | 2 |
| short, then long | as double — **no `LongPress`** inside a multi-press sequence | 2 |
| long, then short | `InitialPress` · `LongPress` · `LongRelease` — no `MultiPressComplete` for the long one — then a new single press | 1 |
| more than `MultiPressMax` | … `MultiPressComplete` | **0** |

**With `MSM` + `AS`:** one `InitialPress` per sequence, no `ShortRelease`, no `MultiPressOngoing`; then `MultiPressComplete(n)`. A long press still gives `LongPress` · `LongRelease` [V-src S3].

Consequence [I]: with `MSM`, a single press is only known to be single when the multi-press window has passed — a rule that acts on `MultiPressComplete(1)` is late by that window; a rule that acts on `InitialPress` also fires on the first press of a double.

Latching (TC-SWTCH-2.2): every position change is `SwitchLatched(NewPosition)` plus a `CurrentPosition` report [V-src S3].

## 4. Timing

The spec sets no numbers: the long-press interval is "manufacturer-determined, since it depends on the switch physics"; `InitialPress` comes "after debouncing" [V S5].

| Source | Long press | Multi-press window | Debounce |
|---|---|---|---|
| matter.js `SwitchServer` defaults | 2 s | 300 ms | off |
| DALI-2 push button (IEC 62386-301), defaults | `tShort` 500 ms (min vendor-specific … 5100 ms) | `tDouble` 0 = **double press off** (or min … 2000 ms) | — ; `tRepeat` 160 ms, `tStuck` 20 s |
| Certification test simulation | held 2 s | 500 ms press / 500 ms release | — |
| Unipi DI hardware | — | — | 5 ms factory (unit 100 µs) |

Sources: matter.js [V-src S6]; DALI-2 [V S12]; tests [V-src S3]; Unipi [V research/02 §4.9].

## 5. matter.js

`SwitchServer` is a **state machine**, not a plain event emitter [V-src S6]:

```ts
// what a bridged endpoint built on SwitchServer is fed
endpoint.set({ switch: { rawPosition: 1 } });        // pressed
endpoint.set({ switch: { rawPosition: 0 } });        // released
// state it decides with: debounceDelay?, longPressDelay = 2 s, multiPressDelay = 300 ms,
// momentaryNeutralPosition = 0, numberOfPositions = 2, multiPressMax = 2
```

- It emits the §3 sequences itself, per the endpoint's features; overflow gives total 0; a long press inside a multi-press sequence counts as a press; a long press ends the sequence [V-src S6].
- A write to `currentPosition` is also treated as an input [V-src S6]. No documented way to emit events directly while using `SwitchServer` [GAP — not checked whether a custom behaviour on the bare cluster can].

## 6. Controllers

| Controller | What it does with a Generic Switch |
|---|---|
| Apple Home | Momentary only, not latching [V S7]. Offers "Double Press" only when the device declares multi-press; otherwise Single and Long [V S8 — bridge maintainer's report]. Orders buttons of a multi-button device by metadata; without it the order is random after each pairing [V S9]. Which events it uses for which trigger, `AS` support, `MultiPressMax` > 2: [GAP] |
| Google Home | Button triggers since early 2026: single, double, multi, long press, long-press release [V S10] |
| Home Assistant | `event` entity. `LS` → `switch_latched`. `MSM` → `multi_press_1 … multi_press_N` (N = `MultiPressMax`, capped at 8) — `initial_press` and `multi_press_ongoing` are then **ignored**. `MS` without `MSM` → `initial_press` (+ `short_release`). `MSL` adds `long_press`, `long_release`. Events not in the declared list are dropped, so total 0 is dropped [V-src S13] |

**Declared features must match sent events.** The Aqara M100 bridge sends multi-press for the wired H2 switch but declares only `MS`+`MSR`; controllers then show only `InitialPress` [V S14 — users' log analysis].

## 7. Multi-button devices

- One endpoint per button; `TagList` on each (§1).
- Namespaces [V S11]: **Switches** `0x43` — `On`, `Off`, `Toggle`, `Up`, `Down`, `Next`, `Previous`, `Enter/OK/Select`, `Custom` (with `Custom`, the label **shall** describe the function). **Common Position** `0x08` — `Left`, `Right`, `Top`, `Bottom`, `Middle`, `Row`, `Column`. **Common Number** `0x07` — `Zero` … `Ten`.
- Endpoints **should** be allocated top-to-bottom, left-to-right; grids over 3 in any direction use `Row`/`Column` with labels `"1"`, `"2"`, … [V S11].

Example [I] — a 2-gang rocker made of 4 buttons:

```
ep 1: Common Position Top    + Common Position Left  + Switches Up
ep 2: Common Position Bottom + Common Position Left  + Switches Down
ep 3: Common Position Top    + Common Position Right + Switches Up
ep 4: Common Position Bottom + Common Position Right + Switches Down
```

## 8. Real devices

| Device | Reported behaviour |
|---|---|
| IKEA BILRESA dual button, scroll wheel (Thread) | Scroll wheel: each detent is one press; ~8 per 180°. Controllers cap at `MultiPressMax` and drop the rest; HA dropped the whole overflow sequence [V S15, S16] |
| Aqara H1 (wireless) via hub M100 | `MSM` + `MSL`, `MultiPressMax` 2, full sequences [V S14] |
| Aqara H2 (wired) via M100 or Thread | declares `MS`+`MSR` only — double/long lost (§6) [V S14] |
| Aqara H2 US in Apple Home | single press only; multi-press stays in Aqara's app [V S17] |
| LIFX 4-button switch | multi-press in Apple Home [V S17 — user statement] |

## 9. What our sources deliver

| Source | Facts |
|---|---|
| `unipi.di` (07a §10) | `{value, counter}` per poll + `readAt`/`stale`; `debounce` channel; optional `directSwitch` [V 07a §10.1]. Poll rates: onboard `fast` 100 ms (TCP loopback), extensions `fast` 200 ms (RS-485) [V 08 §8, 09 §4]. Counter counts rising edges only, lossless, 10 kHz max, may sit in a slower block [V research/02 §4.9, research/08 §5] |
| DALI-2 push buttons (Part 301) | device decides the gesture: released, pressed, short, double, long start / repeat / stop, stuck, free [V S12]. **Out of scope in 12 v1** — no 24-bit frames [V 12 §1, §13] |
| `matter` origin (12a) | a real Matter switch's features, `MultiPressMax` and events arrive as sent (§3); battery Thread devices (BILRESA) |

What follows for `switch-from-di` [I]:

- Edge timing is the poll period, not the press: at 200 ms, a long-press threshold is accurate to ±200 ms; a press shorter than one poll is visible only as a counter step.
- A multi-press window shorter than about two poll periods can't separate two presses.
- Counter delta > 1 between two polls = presses whose timing is lost; they can only be counted, not classified.
- A rocker wired to a DI is a latching switch: one `SwitchLatched` per flip, no long/multi press.

## 10. 12a §2.2 today vs Matter

| 12a today [V 12a §2.2] | Matter | Gap |
|---|---|---|
| `press`, `release`, `longPress`, `longRelease`, `multiPress`, `multiPressComplete` | + `SwitchLatched`; `ShortRelease` is "short" only | no latching; names differ |
| short press = `press` → `release` | with `MSM`: also `MultiPressComplete(1)` after the window | single press not defined with multi-press on |
| `count`: presses so far | total 0 = overflow | no overflow value |
| `position` uint8 | `NumberOfPositions` ≥ 2 | no position count (rotary) |
| `multiPressMax` reading | `FeatureMap` says which events exist | no feature/capability field — 16a can't build `FeatureMap`; a `matter` device's features are not visible |

## 11. Proposals for 12c (not binding)

- **P1 — Matter event names 1:1.** `lastEvent.type`: `initialPress`, `shortRelease`, `longPress`, `longRelease`, `multiPressOngoing`, `multiPressComplete`, `switchLatched`. Sequence rules = §3, incl. total 0 on overflow. 16a and a `matter` origin then translate nothing.
- **P2 — a `features` reading.** Says which events the device produces; 16a builds `FeatureMap` from it, a `matter` device reports its own. Template: from settings.

  ```ts
  features: reading(Codecs.struct({
    kind:       Codecs.string({ enumValues: ['momentary', 'latching'] }),
    release:    Codecs.bool(),     // MSR
    longPress:  Codecs.bool(),     // MSL
    multiPress: Codecs.bool(),     // MSM; multiPressMax only when true
    action:     Codecs.bool(),     // AS
  })),
  numberOfPositions: reading(Codecs.uint8({ min: 2 })),
  ```

- **P3 — one decision point for gestures.** The template decides (its settings, §9 limits); 16a emits the events from `lastEvent` and does not run matter.js's own state machine with its own timings. Alternative: feed `rawPosition` and copy the settings into matter.js — two clocks, plus poll delay. Needs the [GAP] in §5 closed.
- **P4 — templates.**

  | Template | Source | Settings |
  |---|---|---|
  | `switch-from-di` | `unipi.di`, push button | `longPressMs`, `multiPress` on/off, `multiPressWindowMs`, `multiPressMax`, `invert` |
  | `latching-from-di` | `unipi.di`, rocker | `invert`; `kind: latching`, positions 2 |

  Multi-press **off** by default [I]: single presses then come without the window delay.
- **P5 — 12b `toggle-on-press`.** "A short press" needs an event: `shortRelease` (fast, fires on each press of a double) vs `multiPressComplete(1)` (exact, late by the window). For a latching source: toggle on every `switchLatched`.
- **P6 — latching in Apple Home.** Apple refuses latching (§6). Option: 16a projects a latching home switch as momentary — each flip = `InitialPress` · `ShortRelease`. A choice for 16a.
- **P7 — tags.** 12a's `position`/`index` → Common Position / Common Number (§7); add a function tag → Switches namespace.

## 12. Open — [GAP]

- Apple Home: events consumed per trigger, `AS`, `MultiPressMax` > 2. Testable on the rig with a matter.js bridged switch.
- matter.js: emitting Switch events without `SwitchServer`'s state machine (§5).
- Whether the undocumented `Interrupt Mask` register (research/02) gives DI edges faster than polling.

## 13. Sources

- S1 — connectedhomeip `data_model/1.5/device_types/GenericSwitch.xml`: https://github.com/project-chip/connectedhomeip/blob/master/data_model/1.5/device_types/GenericSwitch.xml
- S2 — connectedhomeip `data_model/1.5/clusters/Switch.xml` (and `1.3/`, `1.4/` for revisions): https://github.com/project-chip/connectedhomeip/blob/master/data_model/1.5/clusters/Switch.xml
- S3 — connectedhomeip `src/python_testing/TC_SWTCH.py`: https://github.com/project-chip/connectedhomeip/blob/master/src/python_testing/TC_SWTCH.py
- S4 — matter.js `packages/node/src/devices/generic-switch.ts` (spec 1.6.1 §6.6): https://github.com/project-chip/matter.js/blob/main/packages/node/src/devices/generic-switch.ts
- S5 — matter.js `packages/types/src/clusters/switch.d.ts` (spec §1.13): https://github.com/project-chip/matter.js/tree/main/packages/types/src/clusters
- S6 — matter.js `packages/node/src/behaviors/switch/SwitchServer.ts`: https://github.com/project-chip/matter.js/blob/main/packages/node/src/behaviors/switch/SwitchServer.ts
- S7 — connectedhomeip `docs/guides/darwin.md`: https://project-chip.github.io/connectedhomeip-doc/guides/darwin.html
- S8 — home-assistant-matter-hub #289, "Switch/Button not triggered in HomeKit": https://github.com/RiDDiX/home-assistant-matter-hub/issues/289
- S9 — Apple developer forum 772367, button order in Apple Home: https://developer.apple.com/forums/thread/772367
- S10 — Automated Home, Google Home adds button triggers: https://automatedhome.com/google-finally-adds-smart-button-triggers-to-home-routines-after-years-of-waiting/
- S11 — CSA, Matter 1.4 Standard Namespaces; Nordic DevZone 108057 quoting Device Library 1.2 §6.6.4.2: https://csa-iot.org/wp-content/uploads/2024/11/23-31936-003_matter-1-4-standard-namespaces.pdf · https://devzone.nordicsemi.com/f/nordic-q-a/108057/multi-generic-switch-in-matter
- S12 — Beckhoff Tc3_DALI, DALI-2 push button (Part 301) events and timers: https://infosys.beckhoff.com/content/1033/tcplclib_tc3_dali/10743522187.html
- S13 — Home Assistant `components/matter/event.py`: https://github.com/home-assistant/core/blob/dev/homeassistant/components/matter/event.py
- S14 — Aqara forum, M100: multi-press not forwarded for H2 EU: https://forum.aqara.com/t/m100-matter-bridge-multi-press-events-not-forwarded-for-wired-switches-h2-eu/245049
- S15 — home-assistant/core #159035, BILRESA scroll wheel: https://github.com/home-assistant/core/issues/159035
- S16 — home-assistant/core #159452, presses over `MultiPressMax` discarded: https://github.com/home-assistant/core/issues/159452
- S17 — Aqara forum, H2 switch multi-press in Apple Home: https://forum.aqara.com/t/h2-switch-in-apple-home-app-multi-press/2549
