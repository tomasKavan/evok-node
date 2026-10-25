# 10 — Roof window

**Research, not design.** A motorised roof window with its own motorised cover — a VELUX INTEGRA window with a roller shutter, awning or blind — driven through a VELUX KLF 150 interface from Unipi relays and digital inputs. What the interface does, what state comes back, how Matter models the window, and what the window–cover interlock has to deal with. Feeds 12c's window section and a second `WindowCovering` template (12c-06).

Input from Tomas (2026-10-25):

- A VELUX roof window and its cover, both io-homecontrol, paired to a KLF 150. The KLF 150 is wired to `unipi.ro` (its inputs) and `unipi.di` (its outputs).
- The window is a Closure; the cover gets another `WindowCovering` template.
- Window and cover exclude each other: the window opens only when the cover is up; the cover goes down only when the window is closed. In the template.
- A blocked move is refused, never sequenced.
- No extra contact (sash reed) can be added. The KLF 150 is not configured yet; its set-up follows from this research.
- One home `Closure` type for windows, garage doors and gates, told apart by a kind — as Matter does (§3).
- Idea: send `close` to a window believed closed and watch for the output pulse; keep the last confirmed state in KV.

Spec data from connectedhomeip `data_model/1.5/` (S1). Closure basics — device types, Closure Control, controllers — are in [07 §1–§2](07-garage-door.md) and not repeated here.

## 1. VELUX KLF 150

### 1.1. What it is

- An io-homecontrol interface and repeater: lets "external devices that are not io-homecontrol® compatible" control VELUX products; up to 200 products in up to 5 groups [V S2, S5].
- It **replaces the KLF 200**. No WLAN or browser set-up: it is configured only with VELUX software for Windows — "individual product positions, priorities, output functionalities and scenarios". The LAN socket is for VELUX service only [V S4].
- VELUX INTEGRA controls keep working beside it: "The skylight can always be operated with the VELUX INTEGRA® controls" [V S5].

### 1.2. Inputs

| | |
|---|---|
| Terminals | 10, in pairs 1/2 … 9/10; odd = open/up, even = close/down [V S2] |
| Contact | potential-free, min 10 mA, 5 V DC [V S3]; cable ≤ 100 m [V S2] |
| Short press, < 1.5 s | the product runs to its end position [V S2, S5] |
| Long press, > 1.5 s | the product runs "until the signal stops or the end position is reached" [V S14, S15] |
| Both contacts of a pair | stop [V S2] |
| Change-over contact | up and down, no stop [V S2] |

- Loxone gives the limit as "shorter than 1s" for a full open or close, and its Skylight block's default 5 s pulse must be shortened [V S6].
- **Stop needs both relays on together** — the opposite of a direct motor on two relays (12c-06 §3.2, interlock) [V S2].

### 1.3. Outputs

| | |
|---|---|
| Terminals | 5, A–E; output A belongs to inputs 1/2, and so on [V S2] |
| Contact | potential-free, max 50 mA, 30 V AC/DC [V S2, S3] |
| Function | "The output relay is activated for 2 seconds when an action has been successfully executed" [V S2]; KLF 200's example: "if the skylight has been closed" [V S5] |

- The Danish and Swedish 2025 editions: the output relay is activated for 2 s "when a command has been carried out" ("når en kommando er udført", "när kommandot är utfört"); the Danish one gives a window confirmed closed as the example [V S14, S15]. The output reports **a command it executed**, not a state.
- Other output settings exist in the set-up software (S4, "guide B"), not described in any document found: [GAP]. A dealer lists "position feedback" without saying what it is [V S4].
- Whether the output pulses for a move started elsewhere (INTEGRA remote, rain sensor): [GAP]; the wording ties it to the pair's own command [I].
- A command the product doesn't carry out — opening blocked by the rain sensor — should give no pulse [I]. Not verified: [GAP].
- A command to the position the product is already at — `close` on a closed window: whether it pulses, and how soon: [GAP].

### 1.4. Timing

- Response time: not specified [V S2]. A KNX user measured about 2 s from command to motor start, and 45 s from the first movement to standstill for a shutter [V S7].
- The same user: two products commanded at once — "the second command fails, since the windows cannot move in parallel" (KLF 200) [V S7].
- The KLF's own configuration and input registration take up to minutes [V S5].

### 1.5. Set-up the design needs

What the KLF 150 has to be set to, for P2 (§5) [I]:

| | Window | Cover |
|---|---|---|
| Input pair | 1/2, one product only | 3/4, one product only |
| Output | A, default 2 s pulse | B, default 2 s pulse |
| Input behaviour | default: < 1.5 s to end, longer runs while held, both = stop | the same |
| Groups, scenes, set positions | none — evok-node does positions by time | none |

To test at commissioning, with a stopwatch on the DI: `close` on a closed window, `close` on an open one, `open` with the rain sensor wet — pulse or not, and its delay after the relay.

To check in the software when setting it up: the output options ("output functionalities") — whether one reports a state or a move from elsewhere; and "priorities" (S4) — whether an input can be set to override or be overridden by the rain sensor or INTEGRA controls [GAP].

## 2. The window and the cover

### 2.1. Window (VELUX GGU INTEGRA)

- Opens at most 200 mm (135 mm, 38 mm on small sizes), "within 35 seconds" [V S8].
- "Entrapment control detects objects in the path of the window" [V S8].
- **Rain sensor:** "The window closes automatically in the event of rain or is prevented from opening" [V S8]. It is wired to the motor: closing is "controlled directly by the rain sensor" and the app gets no immediate information [V S10].
- Rain override exists only in VELUX's own app, only from closed: up to 50 %, closing again after 15 minutes; not on older windows [V S10, S11].
- Reported fault: in rain the window closes, reopens about 10 % and retries, the app showing "Something is blocking" [V S12].

### 2.2. Cover

- The window is designed to open with the roller shutter or awning down: the cables are routed "so that the window can be opened when the roller shutter/awning blind is rolled down" [V S9].
- No native interlock between window and cover; users sequence them in their own logic [V S7].
- Roller shutter SML: after a power loss, STOP then DOWN within 30 s starts a new end-position adjustment [V S13]. Travel time: [GAP] — measured at commissioning (S7: 45 s).

### 2.3. What evok-node can know

| Event | Seen by evok-node |
|---|---|
| a move commanded through the KLF | yes — it closed the relay; the output pulses on success (§1.3) |
| a move from an INTEGRA remote or VELUX app | no [I]; output pulse: [GAP] |
| rain closing the window | no [V S10] |
| entrapment stop | no [I] |

Time-based position tracking (as 12c-06) is right only while every move goes through the KLF [I]. A window that rain closed is in the safe state for the interlock; a window opened by remote while the cover is down is not, and evok-node can't prevent it (§2.2) [I].

## 3. Matter

- **No window device type.** Matter 1.5 and 1.7 have Window Covering, Closure and Closure Panel (and their controllers) — nothing named window [V-src S1, `device_types/device_type_ids.json`]. A window is a Closure told apart by its tags.
- **Window:** Closure `0x0230` ([07 §1.1](07-garage-door.md)). Semantic tags: namespace Closure `0x44` tag `Window` `0x01` — "An opening in a wall, door, or roof fitted with glass…"; namespace Closure Window `0x47` tag `Roof` `0x00` — "A window installed in a roof to provide natural light, ventilation, and sometimes access to the roof" [V-src S1].
- Closure Control `PS` gives discrete targets (`MoveToFullyOpen`, `MoveToFullyClosed`, `MoveToVentilationPosition` with `VT`) ([07 §1.2–§1.4](07-garage-door.md)). A % position needs a Closure Panel child with Closure Dimension: `CurrentState`/`TargetState` `{ Position: percent100ths, Latch, Speed }`, `SetTarget`, `Step`; `Unit` mm or degree with `UnitRange`; `LimitRange`; `TranslationDirection` [V-src S1].
- Panel tags, namespace Closure Panel `0x45`: `Lift`, `Tilt`, `Sliding`, `Rotate` [V-src S1].
- **Cover:** namespace Closure Covering `0x46` (`Blind`, `Awning`, `Shutter`, `Venetian`, `Curtain`) exists, but a Window Covering device disallows the Closure clusters ([06 §1.5](06-window-covering.md)) and Apple supports Window Covering, not (yet, as found) Closure ([README §2](README.md)). So the cover stays a Window Covering [I].
- A window exported as a Window Covering would be opened by "open all blinds" — the garage-door failure in [07 §2](07-garage-door.md) [I].
- Matter has no link between two endpoints that exclude each other; only the bridge knows (as [07 §1.8](07-garage-door.md) for a lock) [I]. A refused move: `MainState` `Protected` ("Commands MAY be rejected", feature `PT`) for the window; `BUSY` for the cover (12c-06 §4).

## 4. evok-node today

| Where | What |
|---|---|
| 12c-06 | `WindowCovering`, template `cover-from-relays`: never both relays on — KLF needs both for stop (§1.2) |
| 12c-06 §1.2 | wind protection built into the cover |
| 12a §3, §4.1 | a template's roles take other drivers' devices (`config.local`), not home devices |
| 12a §3a | a bundle creates several devices from one anchor; afterwards each member is on its own |
| research/matter/07 P1 | proposes its own `GarageDoor` type for a Closure |

## 5. Proposals for 12c (not binding)

- **P1 — one `Closure` type** (Tomas) for window, garage door and gate, with a kind that becomes Matter's tags: a roof window ⇒ `Window` + `Roof`, a garage door ⇒ `GarageDoor`. Projected as Closure `0x0230`. Replaces the own `GarageDoor` type of [07 P1](07-garage-door.md). Position: `{current, target, motion}` in 0.01 % as 12c-06, so the Home UI handles both alike; Matter gets a Closure Panel for the %.
- **P2 — KLF drive, one pattern for window and cover.** Per product: `open` and `close` relays (`unipi.ro`), optional `feedback` (`unipi.di` on the KLF output).

  | Action | Relays |
  |---|---|
  | to an end | pulse the direction's relay, `pulseMs` < 1.5 s (default 500 ms, Loxone: < 1 s) |
  | to a middle position | hold the relay `startDelayMs` + travel share, then release (> 1.5 s needed) |
  | stop | both relays on for `pulseMs` |

  Settings: `openMs`, `closeMs` (measured), `startDelayMs` (≈ 2000, S7), `pulseMs`. A middle target closer than 1.5 s − `startDelayMs` of travel can't be reached by holding [I].
- **P3 — state.** Position by time, as 12c-06. A feedback pulse after an end command confirms the end; none within the travel time ⇒ the command was not carried out (rain, entrapment) and the position is unknown [I]. A move not through the KLF is invisible (§2.3); no contact can be added (Tomas), so "closed" stays an estimate — the interlock trusts it.
- **P3a — confirm "closed" by asking** (Tomas). Before a move that needs the window closed — the cover going down — send `close` to the window and wait for the pulse:

  | Pulse | Means [I] |
  |---|---|
  | within ≈ `startDelayMs` + 2 s | it was closed already |
  | later, within `closeMs` + margin | it was open — now closed; it moved |
  | none | not carried out (entrapment, fault) — position unknown, the cover move refused |

  - It is a real `close`: a window opened by the INTEGRA remote closes. Closing is the safe direction, and the cover can't go down over an open window anyway [I].
  - It costs one round trip before every confirmed cover move, and the KLF can't run both products at once (§1.4): the cover waits for the pulse [I].
  - Works only if a command to the current position pulses (§1.3, [GAP]) — the commissioning test decides.
  - The confirmed state and its time are kept with the template's state in KV (12a §3, `ctx.state`), so it survives a restart. It says what was true at that time — a move from elsewhere since is still invisible [I].
- **P4 — cover template.** `WindowCovering` with a new template, `cover-from-klf`: P2's drive, no tilt (VELUX covers have none — [GAP] for blinds), wind protection as 12c-06 §1.2.
- **P5 — interlock in one template.** Two devices, one recipe: a bundle (12a §3a) whose two members share the interlock — today members don't see each other after creation, so 12a would need a shared part — or one template that assembles both. Rules:

  | Request | Allowed when | Else |
  |---|---|---|
  | window open (any > 0) | cover `lift.current` = 0 | refuse (Tomas) |
  | cover down (lift > 0) | window `current` = 0 (closed) | refuse (Tomas) |
  | window close, cover up | always | |

  - Unknown positions refuse [I] — fail safe.
  - Sequenced moves wait for the first to finish: the KLF can't run two products in parallel (§1.4).
  - Wind level 2 on the cover (12c-06 §1.2) raises it; it never needs the window. A cover held up by wind blocks nothing on the window.
  - Rain closing the window is never in the way; an INTEGRA remote can still break the interlock (§2.3).
- **P6 — Matter.** Window: Closure with `PS` and `PT`; refused moves ⇒ `MainState` `Protected` while blocked. Cover: Window Covering as 12c-06 §4. No Window Covering fallback for the window (§3).

## 6. Sources

- S1 — connectedhomeip `data_model/1.5/`, commit `645b267`: `namespaces/Namespace-Closure.xml`, `Namespace-Closure-Window.xml`, `Namespace-Closure-Covering.xml`, `Namespace-ClosurePanel.xml`, `clusters/ClosureDimension.xml`: https://github.com/project-chip/connectedhomeip/tree/master/data_model/1.5
- S2 — VELUX, KLF 150 directions for use, VAS 455497-2025-05: https://contenthub.velux.com/api/public/content/product-guide_455497?v=7a7f550b
- S3 — VELUX, electric interface KLF 150, technical information: https://contenthub.velux.com/api/public/content/57516-33de6-f94be_downloadOriginal?v=77b22908
- S4 — dach-shop24, VELUX Interface KLF 150 (dealer description): https://www.dach-shop24.de/velux-interface/p-141270.html
- S5 — VELUX INTEGRA KLF 200, set-up and user manual, VAS 454041-2021-03: https://contenthub.velux.com/api/public/content/product-guide_454041?v=0973a7a9
- S6 — Loxone, VELUX documentation: https://www.loxone.com/enen/kb/velux/
- S7 — knx-user-forum, "Velux KLF200 mit MDT JAL 0810.02 verbinden — HowTo": https://knx-user-forum.de/forum/öffentlicher-bereich/knx-eib-forum/1768190-velux-klf200-mit-mdt-jal-0810-02-verbinden-howto
- S8 — VELUX, electric roof window GGU, product sheet: https://contenthub.velux.com/api/public/content/c7511-12feb-89493_downloadOriginal?v=ddc927b4
- S9 — VELUX GGL INTEGRA directions for use, p. 28: https://www.manualslib.com/manual/657319/Velux-Ggl-Integra.html?page=28
- S10 — VELUX UK support, rain sensor: https://www.velux.co.uk/support/wiki/active-rain-sensor
- S11 — VELUX UK support, opening when it rains: https://www.velux.co.uk/support/wiki/active-open-raining
- S12 — BuildHub forum, "Velux Integra window closing by rain, but also opening very soon…": https://forum.buildhub.org.uk/topic/28561-velux-integra-window-closing-by-rain-but-also-opening-very-soon-and-closing-and-opening-etc-etc-how-to-solve-this/
- S13 — VELUX SML roller shutter, installation instructions (hosted by a dealer): https://www.solanowonen.nl/downloads/velux/sml.pdf
- S14 — VELUX, KLF 150 directions for use, Danish, VAS 455500-2025-05: https://contenthub.velux.com/api/public/content/product-guide_455500
- S15 — VELUX, KLF 150 directions for use, Swedish, VAS 455505-2025-05: https://contenthub.velux.com/api/public/content/product-guide_455505
