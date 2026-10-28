# 17 — Samsung MIM-B19N on an FJM multi-split

**Research, not design.** Facts for the MIM-B19N driver (12g) and the `room-ac-from-mimb19n` template (12c-10 §3.2): the interface on an FJM multi-split, the register map checked against the manual's pages, custom NASA registers, multi-split behaviour, line budget, and Tomas's `mim-b19n` library. The register map and NASA IDs of [matter/11 §6](matter/11-thermostat.md) are not repeated; this note corrects them where they were wrong.

Input from Tomas (2026-10-28):

- Every unit is an FJM multi-split. One or two outdoor units per flat, usually three indoor units per outdoor unit.
- One MIM-B19N per outdoor unit. All MIMs are on one RS-485 line, each with its own slave address. The line is on the basement PLC and is relayed to each flat's PLC, where the driver runs (07 §4.1 `modbus-remote`).
- Outdoor units: FJM AJ080TXJ4KG/EU, AJ068TXJ3KG/EU. Indoor units: AR70F18C1AWNEU, AR70F09C1AWNEU, AR70F07C1AWNEU. No MIM-R10N is known to be installed.
- His library `tomasKavan/mim-b19n` may be reused if it takes a custom transport (§8).

The manual read is DB68-07538A-02 (MIM-B19N / MIM-B19NT installation manual), a scan; tables were read on the page images (S1). The copy in the `mim-b19n` repo (`MIM-B19N_User-Manual_1.pdf`) is also a scan, with no text layer [V S23].

## 1. Compatibility and connection

| Fact | Tag |
|---|---|
| The manual's supported list: "DVM/CAC indoor unit, hydro kit (low/high temperature), ERV, ERV+, DVM CHILLER, FCU, FCU Kit, and EHS". FJM and RAC are not named | [V S1 p.11] |
| A distributor sheet: it connects to "jedem NASA kompatiblen DVM-S, CAC oder FJM System ohne zusätzliche Platine"; MIM-R10N is for RAC (AR18–24) | [V S9, S10] |
| AJ080TXJ4KG speaks NASA — listed as working with the ESPHome NASA bus project | [V-src S3] |
| ⇒ an FJM outdoor unit needs no MIM-R10N; matter/11 §6.1's chain (MIM-R10N + MIM-B19N) is for single-split RAC only | [I] |
| The MIM speaks "Samsung Control Layer: Protocol (R1/R2)", powered 12 V DC; limits: 1 outdoor unit (4 if modular), 48 indoor units | [V S1 p.8] |
| AJ…TXJ units have "Terminal blocks (R1, R2) for connection with the Upper Controller" | [V S4 p.15, S6] |
| Where the 12 V comes from on an AJ…TXJ board (on DVM: CN12 of the outdoor main board) | [GAP] — [V S1 p.5, S17] for DVM only |
| "When the Modbus interface module is used, the upper-level controllers of Samsung cannot be connected" — On/Off, Touch, DMS | [V S1 p.11] |
| AJ068TXJ3KG takes up to 3 indoor units, AJ080TXJ4KG up to 4 | [V S15] |
| The AR70F…C1AWNEU wall units are sold both as FJM indoor units and with an AR70F…AWXEU single-split outdoor unit | [V S22] |

### 1.1. Addresses and central control

| Fact | Tag |
|---|---|
| "Each indoor unit address must be set to a value from 00 to 47"; the MIM's own address 1–247 | [V S1 p.11] |
| MIM address = sum of DIP switches SW4/SW5 (128, 64, 32, 16) + rotary SW1 (0–F); read once at power-on; out of range ⇒ E634 | [V S1 p.12] |
| FJM auto-addressing: E199 shown, K1 pressed once, 3–5 min cool or heat run; needs 5–40 °C outdoor, indoor ≥ 16 °C | [V S4 p.32, S6] |
| FJM manual addressing: MAIN address (indoor–outdoor), RMC address "wenn Sie die zentrale Bedienung verwenden" | [V S4 p.33] |
| The MIM's IU index (0–47) is the indoor unit's address, not its pipe port | [I from S1] |
| Two MIMs on one line: IU indexes repeat between them; the slave address tells them apart | [I from S1 p.7] |
| **SEG5 "Use of central control" must be `1`** on every indoor unit, or the MIM reports a tracking error (E604); reset the MIM after changing it | [V S1 p.7, S16] |
| SEG5 in the option code: `02000-100000-200000-300000` default; entered with the wireless remote (batteries out, keys held, all 6 segments, power cycle) | [V S5 p.29–34, S14]; exact key combination for the AR70F remote [GAP] |
| Tracking after power-on can take up to 10 min; not done ⇒ 7-segment E6 / 04 | [V S1 p.11] |

## 2. Register map — checked on the page images

Correction to matter/11 §6.2 and to the library (§9): the register type columns of Table 2 say which registers apply to an indoor unit (`Indoor` column) [V S1 p.13–16].

| PDU | Name | Indoor | Values |
|---|---|---|---|
| 0 | module error | R | b0 address error, b1 R1/R2 comms error, b2 tracking error |
| 1 | outdoor error | R | 0 none, 100–999 |
| 2 | outdoor defrost | R | 0 or 0xFF off, others on |
| 3 | buzzer | W | 0 on, 1 off |
| B+0 | communication status | R | **b0 Exist, b1 Type OK, b2 Ready, b3 Communication error** — control only at bits 0–2 = 7 (Table 1 flow: "6 (Not Ready)", "7 (Ready)") |
| B+1 | unit type | R | low byte model code (AHU 90–99, ERV 100–102, ERV+ 108, HE 110, HT 120, EHS 115–117, chiller 140–149, FCU Kit 160–169, **others: IU**); high byte group (FCU 10); 0xFFFF not defined |
| B+2 | power | R/W | 0 off, 1 on |
| B+3 | mode | R/W | 0 Auto, 1 Cool, 2 Dry, 3 Fan, 4 Heat (21, 24 chiller only) |
| B+4 | indoor fan | R/W | 0 Auto, 1 Low, 2 Middle, 3 High |
| B+5 | vertical airflow | R/W | 0 off, 1 on |
| B+6 / B+7 | filter alarm / clear | R / W | 1 = alarm / clear |
| B+8 | set temperature | R/W | °C ×10; cooling 18–30, heating 16–30 (Nordic models 8–30) |
| B+9 | room temperature | R | °C ×10, −41…100 |
| B+10 | discharge temperature | R | °C ×10 |
| B+11, B+12 | cooling / heating discharge set temperature | R/W | for AHU kits; Indoor column R/W, purpose on a wall unit [GAP] |
| B+13 | indoor error | R | 0, 100–999 |
| B+14 | remote control restriction | R/W | read 0x0000 none, others restricted; **write 0x0000 none, 0x6363 restricted** |
| B+28 / B+29 | quiet / away | — | **HE/HT/EHS only**: not for an indoor unit |
| B+30 | WindFree | R/W | **0 none, 9 WindFree** |
| B+31 | 360 airflow | R/W | Spot 106, Mid 85, Wide 64, Swing 15, others individual — 360 cassettes |

All [V S1 p.13–16].

- Register numbers are 1-based, PDU addresses 0-based; B = 50 + 50·IU as a PDU address [V S1 p.13].
- "If an identical command is issued consecutively, the same command is repeatedly sent to the indoor units." A write is always sent on [V S1 p.10].
- "The holding register value for an indoor unit is not updated until a changed status value is received from that indoor unit"; with communication lost, "the last status value is retained" [V S1 p.8].
- "When reading from or writing to a register consecutively, be sure to send a command at least 10 ms after the last response" [V S1 p.10].

## 3. Custom NASA registers

| Fact | Tag |
|---|---|
| Outdoor: write MessageSet IDs to PDU 6000… with FC16; they appear in registration order from register 5 (PDU 4) | [V S1 p.17] |
| Indoor: write MessageSet IDs to PDU 7000… with FC16; they appear in registration order from register 33 — PDU B+32 of each indoor unit | [V S1 p.17–18] |
| "If there are multiple functions to add, they must be written all at once using command 16" | [V S1 p.17] |
| Table 3 lists examples only: 0x8238, 0x8204 outdoor; 0x411E, 0x42D7, 0x42D6, 0x4087, 0x406C, 0x42E9, 0x42F1, 0x4067 indoor (EHS/hydro). Zone and FR entries are R/W | [V S1 p.18] |
| The indoor list is one list for all indoor units: each unit gets the same IDs at its own B+32… | [I from S1 p.17–18] |
| Capacity: indoor B+32 … B+49 = 18 IDs before the next unit's block; outdoor PDU 4 … 49 = 46 | [I] — ZimKev registered exactly 18 indoor IDs and 32 outdoor ones [V S2] |
| IDs outside Table 3 work in practice: ZimKev's EHS used 0x4203, 0x4239, 0x428C, 0x8001, 0x8235 and more | [V S2] |
| A write to a custom register sends that NASA message to the unit (Table 3 marks some R/W) | [V S1 p.17–18] |
| Whether the registration survives a MIM power cycle | [GAP] |
| Whether PDU 6000/7000 can be read back | [GAP] — a user got "Illegal data address" on the 6000 range [V S24] |
| Whether a write of an alt-mode or swing message is accepted by an FJM wall unit through the MIM | [GAP] |

IDs that serve 12c-10 (NASA meanings from the ESPHome project, [V-src S3]):

| ID | Meaning | Use |
|---|---|---|
| `0x4060` | alternative mode: sleep 1, quiet 2, fast 3, long-reach 6, eco 7, WindFree 9 | `special`, boost |
| `0x407E` | left/right swing | `swing.leftRight` |
| `0x4002` | real mode: 0–4, 11–14 auto-cool / dry / fan / heat | what the unit really does |
| `0x4028` | thermo on/off | running or idle |
| `0x402E` | indoor defrost | |
| `0x4203` | room temperature (ESPHome ignores it; uses `0x4204`, "modified current temp") | diagnostics |
| `0x8003` | outdoor heat/cool: 1 Cool, 2 Heat, 3 CoolMain, 4 HeatMain | mode conflict (§4.1) |
| `0x8001` | outdoor mode: 0 stop, 1 safety, 2 normal, 5 de-ice, 7 prohibit, … | defrost, state |
| `0x8204` | outdoor air temperature ×10 | the `outdoor` role (12c-10 §3) |
| `0x8235` | outdoor error code | |

## 4. Multi-split behaviour

### 4.1. Mode conflict

| Fact | Tag |
|---|---|
| One outdoor unit can't heat and cool at once; only heat-recovery systems do both | [V S12 p.80] |
| Older FJM (MH026FNCA): mixed modes are "user's fault", error **E161**; "Outdoor unit will be operate by first received signal" | [V S12 p.80] |
| E161: "Mixed operation mode error of indoor unit when outdoor unit is getting ready to operate in one mode and indoor unit tries the opposite mode" | [V S13] |
| AJ…TXJ manuals have no mode-priority option; the outdoor option is cool only / heat only / both (SEG 00) | [V S6 p.28, S5 p.28] |
| The same rule and E161 on AJ…TXJ; what a losing indoor unit shows | [GAP] |
| Over the MIM a conflict would show as E161 in B+13, or as `0x4001`/`0x4002` vs `0x8003` disagreeing | [I] |

### 4.2. Defrost

| Fact | Tag |
|---|---|
| AR70F: defrost icon, "runs the Defrost function for 5 to 12 minutes"; "the fan stops and warm air does not come out"; blades to the lowest position on multi systems | [V S8 p.28, 44] |
| Fan may stay off 3–5 min at heating start, against cold draft | [V S8] |
| On the MIM: PDU 2. On NASA: `0x402E`, `0x8061` (steps, 255 none), `0x8001` = 5 | [V S1 p.13; V-src S3] |
| Defrost interval and start conditions on AJ…TXJ | [GAP] |

### 4.3. Functions of the AR70F on a multi system

| Fact | Tag |
|---|---|
| Not supported on multi systems: **Eco**, Freeze Wash, Dry Comfort (falls back to Dry) | [V S8 p.17, 23, 30, 34] |
| WindFree works only in Cool, Dry or Fan, not Heat; turning it on cancels airflow direction, MAX and Eco | [V S8 p.22] |
| Setpoint: "Adjust by 1 ℃ from 16 ℃ to 30 ℃" in Auto/Cool/Heat; Dry 18–30; Fan none. Not changeable in Fan or MAX | [V S8 p.20, 44] |
| Whether the MIM keeps a 0.5 °C setpoint (B+8 is ×10) | [GAP] |
| Up/down and left/right blades; 5 airflow steps in cool, 4 in fan | [V S8, S22] |
| NASA fan command `0x4006`: 0 Auto, 1 Low, 2 Mid, 3 High, 4 Turbo — the MIM's B+4 has no Turbo | [V-src S3, V S1] |
| Quiet as a mode of the AR70F: not found in the user manual read | [GAP] |

### 4.4. "AI" modes

| Fact | Tag |
|---|---|
| "You can use AI Auto mode after Wi-Fi is connected"; it learns patterns and picks Cool/Dry/Heat/WindFree; without Wi-Fi the unit switches between Cool, Dry and Heat | [V S8 p.20, 24–25] |
| AI Energy "can be turned on or off from the SmartThings app only" | [V S8 p.25] |
| No NASA value for AI modes found; `0x4060` has none | [GAP] [V-src S3] |
| ⇒ AI modes are SmartThings features, out of the MIM's reach | [I] |

### 4.5. Remote, SmartThings, lock

| Fact | Tag |
|---|---|
| "Because the user might be able to operate indoor units with a remote control, the BMS must read their status periodically" | [V S1 p.8] |
| B+14 = 0x6363 restricts the remote; whether it blocks IR, wired or SmartThings | [V S1 p.15], [GAP] |
| NASA has per-function lock levels `0x0409`–`0x0416` (all, power, mode, fan, swing, setpoint, limits, key input); values not documented | [V-src S3], [GAP] |
| A Wi-Fi kit is its own NASA node (address class 0x62). The MIM manual bans only Samsung upper controllers, not Wi-Fi | [V-src S3, V S1 p.11] |
| US FJM bulletin: fan-off in thermo-off is unavailable with a wired controller or Wi-Fi kit and needs SEG5 = 0 — so not with the MIM | [V S14], [I] |

## 5. Feature detection

| Fact | Tag |
|---|---|
| B+1 reports a wall unit as "IU" — no model, no features | [V S1 p.13] |
| NASA has model and option messages (`0x0600`–`0x0603`, `0x061A`, `0x061F`, `0x4229`), undocumented and string/structure-typed | [V-src S3], [GAP] |
| Structure messages can't fit a 16-bit custom register | [I] |
| ⇒ what a unit supports is configured per indoor unit (model), not read | [I] |

## 6. Line budget

At 9600 baud, 8E1 = 11 bits per byte ≈ 1.15 ms per byte [I — arithmetic].

| Transaction | Bytes on the wire | Time |
|---|---|---|
| FC3, 1 register (B+0) | 8 + 7 | ≈ 17 ms |
| FC3, 32 registers (B+0…B+31) | 8 + 69 | ≈ 89 ms |
| FC3, 18 custom registers | 8 + 41 | ≈ 56 ms |
| FC6 write | 8 + 8 | ≈ 18 ms |
| + gap after each response | | ≥ 10 ms (manual); 50 ms was stable in practice [V S24] |

- t3.5 at 9600 baud is ≈ 4 ms, below the manual's 10 ms: 07's line pacing alone is not enough for a MIM [I — arithmetic on 07 §2].
- One full read of an indoor unit (status + 18 custom) ≈ 0.15 s + gaps; ~18 indoor units on the house line ≈ 3–4 s per round, with all flats sharing the line through `modbus-remote` [I].
- Every remote transaction adds a WS round trip on top (07 §4.1) [V].
- Bursts made a MIM ignore writes or answer zeros; 50 ms gaps and staggered polling were stable [V S24].
- Whether one FC3 may span unit blocks (e.g. PDU 50–174) without an exception for undefined offsets: [GAP].

## 7. Outdoor units

| | AJ068TXJ3KG/EU | AJ080TXJ4KG/EU |
|---|---|---|
| Indoor units, max | 3 | 4 |
| Heating at +7 / −5 / −10 / −15 °C (kW) | 8.0 / 6.02 / 5.14 / 4.25 | 9.3 / 7.00 / 5.97 / 4.94 |
| COP / SCOP | 4.42 / 4.32 | 4.37 / 4.10 |
| Heating range outdoor | −15 … 24 °C | −15 … 24 °C |

All [V S15, S20, S21]. "SEER, SCOP and energy rating depends on the combination of Indoor Unit" [V S15]. At −15 °C capacity "may decrease by as much as 60–70 %" [V S8 p.20].

## 8. Tomas's `mim-b19n` library

Commit `9528b7d` ("Initial commit"), version 0.1.0, MIT [V-src S23].

### 8.1. Shape

```ts
// src/transport/ModbusTransport.ts — one slave per transport
interface IModbusTransport {
  connect(): Promise<void>; disconnect(): Promise<void>; readonly isConnected: boolean;
  readHoldingRegisters(address: number, count: number): Promise<number[]>;   // FC3
  readInputRegisters(address: number, count: number): Promise<number[]>;     // FC4
  writeSingleRegister(address: number, value: number): Promise<void>;        // FC6
  writeMultipleRegisters(address: number, values: number[]): Promise<void>;  // FC16
}
new MimClient(config, transport?)   // transport absent ⇒ SerialTransport (modbus-serial)
```

[V-src S23 `src/transport/ModbusTransport.ts`, `src/client/MimClient.ts`]

- A custom transport is already supported. The slave address is the transport's, not the request's: one transport per MIM [V-src S23].
- `SerialTransport` waits `interFrameDelayMs` (default 10) before every request; with a custom transport, pacing is the transport's [V-src S23 `SerialTransport.ts`].
- `index.ts` exports `SerialTransport`, which imports `modbus-serial` at load [V-src S23]. evok-node already uses `modbus-serial` (07 §2), so this adds no new dependency [I].
- Errors are thrown; evok-node's `ModbusTransport` answers `CallOutcome` (07 §4) [V-src S23, V]. An adapter maps one to the other [I].
- `getStatus()` reads B+0…B+31 in one FC3; `control()` writes each given field with FC6, in order [V-src S23 `IndoorUnit.ts`].
- `getAllIndoorStatuses()` reads all 48 blocks, full — ≈ 5 s per MIM at 9600 baud [V-src S23, I §6].
- Tests: Jest with a `MockTransport`; evok-node uses Vitest (basics/03) [V-src S23].

### 8.2. Differences from the manual

| Library | Manual (S1) | Effect |
|---|---|---|
| B+0: `typeOk` = bit 0, `ready` = bit 1, `commError` = bit 2 (`IndoorUnit.ts`, `indoorRegisters.ts`) | b0 Exist, b1 Type OK, b2 Ready, b3 Comm error | `ready` reads "Type OK"; a unit looks ready too early; a comm error is missed [V-src S23, V S1 p.13] |
| B+14 write `0x0363` | `0x6363` | the remote lock is not set [V-src S23, V S1 p.15] |
| WindFree write `2`, read `=== 2` | `9` | WindFree neither set nor seen [V-src S23, V S1 p.16] |
| 360 airflow `Spot = 10`, `Individual = 255` (`enums.ts`) | Spot 106; others = individual | wrong value (360 cassettes only) [V-src S23, V S1 p.16] |
| Quiet, away offered for every unit | HE/HT/EHS only | no effect on wall units [V S1 p.16] |
| `registerExtended` per `IndoorUnit`, cached per unit | one 7000 list for all units | registering on one unit changes what every other unit's B+32… mean; the other caches are stale [I from S1 p.17] |
| no write of a custom register | custom registers can be R/W | no way to send `0x4060`, `0x407E` [V-src S23] |
| README: "Do NOT send duplicate consecutive commands — the module ignores them" (`IndoorUnit.ts` comment) | the module re-sends them | comment wrong, behaviour harmless [V-src S23, V S1 p.10] |

## 9. Proposals for 12g (not binding)

- **P1 — reuse the library, behind an adapter.** One `IModbusTransport` per MIM, made from 12g's `ModbusTransport` with the MIM's `unitId`; `CallOutcome` failures thrown as errors the client sees; `connect`/`disconnect` no-ops (07 owns the line). Fix §8.2 in the library first.
- **P2 — pacing in the driver.** 10 ms (setting, default 50 ms) after every response to the same MIM, on top of 07's t3.5. One request in flight per MIM.
- **P3 — indoor units from config, not a 48-slot scan.** `mims: [{ unit: 3, indoorUnits: [{ iu: 0, model: 'AR70F09C1AWNEU' }, …] }]`. The model picks a feature table (modes, fan, swing, specials) — §5. At start, one FC3 of B+0 per configured unit; ready only at bits 0–2 = 7.
- **P4 — custom registers set by the driver.** One fixed indoor list (`0x4060`, `0x407E`, `0x4002`, `0x4028`, `0x402E`, …) and outdoor list (`0x8003`, `0x8001`, `0x8204`, `0x8235`) written with FC16 after every module restart — detected by tracking, a comms error, or values reading 0. Validated on one unit before use (§3 gaps).
- **P5 — write on change only.** A write is always sent on and a register updates only when the unit reports (§2): compare with the last read, never re-send a value. A write then a read-back confirms it.
- **P6 — local change.** A polled value that differs from the last write and was not written by the driver ⇒ `localChange` (12c-10).
- **P7 — outdoor state as its own raw device.** Defrost, heat/cool (`0x8003`), outdoor temperature, error. Indoor units on the same outdoor unit share it; a room asking to cool while it heats would get a mode conflict — 12c-10's `available.ac.reason` has no value for it yet.
- **P8 — what 12c-10 must drop or change.** `special: 'eco'` (not on multi), `quiet` (unit support unknown), boost = `0x4060` = 3 only if a write is accepted; fan Turbo only through NASA; setpoint in 1 °C steps.

## 10. Gaps

- The 12 V connector on AJ…TXJ boards; the AR70F remote's key sequence for SEG5.
- E161 and the mode-conflict rule on AJ…TXJ; what the losing indoor unit does.
- Custom registers: survival across a MIM power cycle, reading back 6000/7000, writes of `0x4060` and `0x407E` on FJM wall units.
- B+11/B+12 on a wall unit; a 0.5 °C setpoint through B+8; FC3 across unit blocks.
- What 0x6363 locks; whether SmartThings Wi-Fi conflicts with the MIM.
- Defrost interval on AJ…TXJ.

## 11. Sources

- S1 — Samsung MIM-B19N/MIM-B19NT installation manual DB68-07538A-02 (scan), in ZimKev/MIM-B19n_Modbus `3ac51c0`: https://github.com/ZimKev/MIM-B19n_Modbus
- S2 — ZimKev/MIM-B19n_Modbus `3ac51c0`, `README.md`, `modbus.yaml`
- S3 — omerfaruk-aran/esphome_samsung_hvac_bus `fe08cb0` (`docs_src/wiki/nasa/samsung_nasa_protocol.md`, `Compatibility.md`, `components/samsung_ac/protocol_nasa.h/.cpp`): https://github.com/omerfaruk-aran/esphome_samsung_hvac_bus
- S4 — Samsung FJM outdoor installation manual (German), AJ040–080TXJ: https://www.klimaanlagen-heizungen.de/media/pdf/d9/79/c1/Samsung_Installationsanleitung_Free_Joint_Aussengeraete_AJ_040_050_052_068_080.pdf
- S5 — AJ080TXJ4KG installation manual (ManualsLib): https://www.manualslib.com/manual/3887880/Samsung-Aj080txj4kg.html
- S6 — AJ***TXJ*KG installation manual: https://wellair.dk/wp-content/uploads/2024/04/fjm-udedele-installationsmanual.pdf
- S7 — FJM installation manual INS-SG-FJM-0820-EN: https://klimavex.eu/disk/atsubory/66/locked82227/INS-SG-FJM-0820-EN.pdf
- S8 — AR60F**C1*** / AR70F**C1*** user manual: https://www.appliancesdirect.co.uk/files/pdf/AR70F09C1A%20manual.pdf
- S9 — distributor MIM-B19N spec sheet: https://regro.a.bigcontent.io/v1/static/8046128_1_P_PROD_SPEC_TeSamCoolMD22701335
- S10 — klimafreak, Samsung Modbus gateway: https://klimafreak.at/products/samsung-modbus-gateway
- S11 — keroclima, MIM-B19N: https://www.keroclima.pt/Samsung-Comando-MIM-B19N/en
- S12 — Samsung MH026FNCA service manual p.80 (ManualsLib): https://www.manualslib.com/manual/583310/Samsung-Mh026fnca.html?page=80
- S13 — E161 (third party): https://mypros.plus/error-codes/samsung/air-conditioner/e161
- S14 — Samsung TB2020-0017, FJM fan off in thermal-off: https://s3.amazonaws.com/samsung-files/Tech_Files/Tech_Bulletins/RAC+CAC+FJM/TB2020-0017+FJM+Fan+OFF+in+Thermal-Off_rev03172021.pdf
- S15 — Samsung outdoor unit data sheet (klimux): https://www.klimux.com/mediafiles/datenblaetter/Samsung/Technisches%20Datenblatt%20Samsung%20Aussengeraete.pdf
- S16 — MIM-B19N guide (manualzz): https://manualzz.com/doc/49946121/samsung-mim-b19n-guide-d-installation
- S17 — MIM-B19N quick start (EHS): https://planetdevices.com/wp-content/uploads/2024/05/Samsung_MIM-B19N_Quick_Start_Guide_V01.pdf
- S18 — Samsung UK, MIM-B19N support: https://www.samsung.com/uk/support/model/MIM-B19N/
- S19 — FJM duct user manual DB68-04994A-04: https://samsung-files.s3.us-east-1.amazonaws.com/Tech_Files/FJM/AJ+JNLDCH_FJM_Slim+Duct/User_Manual/FJM_Duct_USER+MANUAL_DB68-04994A-04_181210_ENGLISH.pdf
- S20 — Samsung, AJ068TXJ3KG/EU: https://samsung-climatesolutions.com/gb/b2b/products/fjm/outdoor.aj068txj3kgeu.html
- S21 — Samsung, AJ080TXJ4KG/EU: https://samsung-climatesolutions.com/gb//b2b/products/fjm/outdoor.aj080txj4kgeu.html
- S22 — Samsung, WindFree Avant S2 (FJM): https://samsung-climatesolutions.com/gb/b2b/products/fjm/windfree-avant-s2.html
- S23 — tomasKavan/mim-b19n `9528b7d` (private): `src/`, `README.md`, `AGENTS.md`
- S24 — OpenEnergyMonitor forum, MIM-B19N read/write issues: https://community.openenergymonitor.org/t/modbus-read-write-issues-with-samsung-mim-b19n-and-siemens-logo-plc/29910
