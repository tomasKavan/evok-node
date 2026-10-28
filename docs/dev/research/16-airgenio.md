# 16 — 2VV Venus heat recovery unit with AirGENIO Comfort over Modbus

**Research, not design.** Facts for a future AirGENIO driver and for the home device a heat recovery unit maps to. What Matter offers and how other systems model such a unit is in [matter/12](matter/12-fan.md); it is not repeated here.

Input from Tomas (2026-10-28):

- Each flat has a 2VV Venus heat recovery unit with AirGENIO control, on RS-485 to the flat's Unipi PLC.
- There will likely be a dedicated driver; how to model the unit in the home driver is still open.

The exact unit size (HRV14…HRV70) and the firmware version: [GAP].

## 1. The unit

| Fact | Source |
|---|---|
| Venus sizes HRV14EC, HRV15EC, HRV30EC, HRV50EC, HRV70EC; max airflow 185, 175, 315, 535, 785 m³/h; EC fans; filters F7 supply, G4 extract; 230 V 1~ | [V S3 §5] |
| Parts: four duct spigots (ODA outdoor, SUP supply, ETA extract, EHA exhaust), one heat exchanger, two fans, control box, condensate drain, two filters. No bypass flap is shown | [V S3 §3] |
| Exchanger: counterflow, aluminium ("Protiproudý rekuperátor (AL)"), efficiency up to 93 % | [V S4] (catalogue of the older Venus Standard) |
| Venus Comfort "can be equipped with internal electric preheater" | [V S5] |
| Frost-protection sensor INT2 in the exhaust after the exchanger | [V S3 §7, HW TEST] |
| "Primary purpose of VENUS is to ventilate, not to cool" — night ventilation does not replace an AC | [V S3 MENU 16] |

**Bypass.** The Modbus guide says the minimum outdoor temperature for opening the bypass (20037) "does not apply to VENUS" [V S1 §5.1]. The manual has no bypass menu [V S3]. Venus likely has no bypass; summer cooling is done by night ventilation (§4.5) [I]. FACTORY_SET 10129 `Bypass` (0 none, 1 stepless 0–10 V, 2 open/close) tells it on the real unit [V S2].

**Hardware configuration is readable.** FACTORY_SET (read-only without a factory password) holds what is fitted: `RecupType` 10130 (plate, rotary, enthalpy), `Bypass` 10129, `Preheater_1` 10119 (none, electric, water), `Postheat_1` 10123, `ModuleEnergyMeasure` 10105, and per-sensor "used" flags 10135–10162 [V S2]. A driver can read these at start and expose only what exists [I].

## 2. Interface

| Fact | Source |
|---|---|
| Modbus RTU on RS-485, terminals A (25), B (26), GND (28) on the main board (module A) | [V S1 §2] |
| Defaults: address 1, 9600 baud, parity **odd**, 1 stop bit (9600 8O1) | [V S1 §1, S2 INTRODUCTION] |
| Settable in service menu 20 (code 1616) or by 25021–25023: address 1–247; 4800, 9600, 14400, 19200, 38400; parity none/odd/even. A **software reset** is needed after any change | [V S1 §3, S2 SERVICE HARD] |
| The main board already has a terminating resistor | [V S1 §2] |
| A, B swapped can stop the whole bus, not only this unit | [V S1 §2] |
| Modbus TCP (port 502) "available only for SUPERIOR controls" | [V S1 §1] — but see §5 |
| Holding registers: FC 03, 06, 16. Input registers: FC 04 | [V S1 §4, S2] |
| "PLC Addresses – BASE1"; examples say "PLC adresses BASE +1" | [V S1 §1, §5] |

- **Addressing:** the listed numbers are likely 1-based register numbers, so the PDU address is the listed number − 1 — the same as Samsung's MIM-B19N ([matter/11 §6.2](matter/11-thermostat.md)) [I]. Check on the unit: read 15049 (setpoint) at PDU 15048 [GAP].
- The control panel seems to have its own RS-485 pair (23, 24, with 24 V) [I — S3 §6.5 diagram, text garbled]. Whether panel and Modbus share a bus: [GAP]. The panel stays connected; Modbus writes and panel changes land in the same SHARE registers (§3) [V S2 INTRODUCTION].
- Write pacing, minimum gap between requests, timeouts: not documented [GAP].
- Registers that need a software reset after a write are listed as such in S1 §5 (e.g. 25008, 25030, 25031, 20009–20024) [V S1 §5.1]. Software reset: FACTORY_DRIVER 10003 `SWReset` [V S2].

## 3. Register map — what a driver needs

One spreadsheet covers all 2VV products with AirGENIO (units, air curtains, IC/SC controllers). Colour: green = HRU/AHU only, orange = air curtains and IC/SC only, none = all [V S2 INTRODUCTION]. Only green and uncoloured rows apply here.

### 3.1. Control — SHARE (holding, R/W)

"Registers represent actual control commands … also the commands from the control panel or other control equipment" [V S2].

| Reg. | Name | Values | |
|---|---|---|---|
| 21001 | `SwitchON` | 0 off (standby), 1 on | [V S2] |
| 21002 | `AirFlowManual` | MANUAL mode: ‰ of fan power. CAV: m³/h. DCV, VAV: not available | [V S2] — S1 §5.1 says "value in %" |
| 21003 | `Temperature` | setpoint °C; range by the selected sensor: supply 15–45, extract 15–30, room 15–30 | [V S2] |
| 21004 | `TimeSwGlobalEnable` | the unit's own week/year timer, 0/1 | [V S2] |
| 21005–21008 | `TimeSwMode`, `TimeSwFlow`, `TimeSwTemp`, `TimeSwOnOFF` | timer state, read only | [V S2] |
| 21009 | `BoostMode` | 0/1 | [V S2] |
| 21010 | `NoBodyMode` | nonoccupied mode, 0/1 | [V S2] |
| 21011 | `FreecoolingMode` | night ventilation (free cooling), 0/1 | [V S2] |
| 21014 | `DirectControlMode` | hardware test mode, enables DIRECT_CONTROL 35000… | [V S2] |
| 21016 | `FilterClogedTimerReset` | 1 = reset the filter timer | [V S2] |

Airflow limits (FACTORY_SET, defaults): `MinFlowManual` 200 ‰, `MaxFlowManual` 1000 ‰, `StepFlowManual` 100 ‰ [V S2]. The panel offers 20–100 % in 10 % steps [V S3 §7]. Example: 21002 = 600 → 60 % fan power [I — from the ‰ unit].

### 3.2. Status — STATUS_AHU (input, R)

| Reg. | Content | |
|---|---|---|
| 15000 | bits: 0 on/off, 1 manual, 2 CAV, 3 VAV, 4 DCV, 5 fire, 6 boost, 7 nobody, 8 free cooling, 9 timer, 10 calibration, 11 cool-down, 12 direct control, 13 filter info | [V S2] |
| 15001 | bits: 4 recirculation, 6 pre-free-cooling, 7 temperature flow reduction, 8 passive-house restriction, …; 0–3 water heater only | [V S2] |
| 15002 | software errors: 0/1 supply/extract fan, 2/3 filter error, 4/5 filter warning, 6 preheater 1, 7 postheater 1, 10 AQS sensor, 15 condensate drain, … | [V S2] |
| 15003 | bit 1 global error; bit 3 filter info; bit 4 config file error | [V S2] |
| 15004 | sensor faults: 0 EXT1, 1 EXT2, 2 EXT3, 5 INT1, 6 INT2, 9 room | [V S2] |
| 15006 | inputs: 2 external control, 3 nobody (or fire), 4 boost | [V S2] |
| 15008 | outputs: 0 supply flap, 1 exhaust flap, 2 RUN, 5 error | [V S2] |
| 15013 / 15014 | supply / extract fan, ‰ of power (manual) | [V S2] |
| 15015 / 15016 | supply / extract airflow, m³/h (CAV units) | [V S2] |
| 15017 / 15018 / 15019 | EXT1, EXT2, EXT3 °C × 10 | [V S2] |
| 15022 / 15023 | INT1, INT2 °C × 10 | [V S2] |
| 15026 | room °C × 10 (optional CT-ROOM sensor) | [V S2] |
| 15033 | AQS value % | [V S2] |
| 15036 / 15038 | preheater 1 / postheater 1 power % | [V S2] |
| 15041 | bypass position % | [V S2] |
| 15044 / 15045 | supply / extract filter % | [V S2] |
| 15049 | temperature setpoint, "°C" — no × 10 stated | [V S2] |

Sensor placement [V S3 §6.4, HW TEST]:

| Sensor | Where | Colour |
|---|---|---|
| EXT1 | outdoor air duct, before the unit (ODA), ≥ 80 cm from the spigot | blue |
| EXT3 | supply air into the building, after the exchanger | — |
| INT1 | extract air from the building, before the exchanger (ETA), ≥ 80 cm | orange |
| INT2 | exhaust after the exchanger — frost protection | — |

EXT2: HW TEST lists no EXT2; error 17 calls it "supply after the exchanger", while HW TEST calls EXT3 that [V S3]. Which is which: [GAP].

Electric data INFO 16003–16007 (mA, V, W, kWh) exist only with the energy module (10105) [V S2] [I].

### 3.3. Service — SERVICE (holding, factory reset → defaults)

| Reg. | Name | Range, default | |
|---|---|---|---|
| 20003 / 20004 | CO₂ high / low, 2000 ppm sensor | 350–2000; 2000 / 350 | [V S2] |
| 20005 / 20006 | universal 0–10 V AQS high / low % | 0–100; 100 / 0 | [V S2] |
| 20007 | `FlowOfset` — supply/extract imbalance % | −100…50; 0 | [V S2] |
| 20009 / 20010 | nobody: time after a PIR trigger 1–60 min (30); flow 20–50 % (20) | | [V S2] |
| 20011 | `BoostFromOff` — boost also from standby (external button only) | 0/1; 0 | [V S2] |
| 20012 / 20013 | `BoostTimer` 1–60 min (**3**); `BoostFlow` 0–100 % (100) | | [V S2] — S5: "0–60 min (30 min default)" |
| 20014–20024 | night ventilation: enable; flow 50–100 % (100); extract temperature 12–25 °C (20); start month/day/hour/min 6/1/20:00, stop 9/1/6:00 | | [V S2] |
| 20034 / 20035 | supply duct max 25–45 °C (30) / min 15–20 °C (15) | | [V S2] |
| 20045 | reduce flow when the duct minimum is not reached | 0/1; 1 | [V S2] |

### 3.4. Service — SERVICE HARD (holding, kept by a factory reset)

| Reg. | Name | Values | |
|---|---|---|---|
| 25000 | `VentilationMode` | 0 manual, 1 DCV, 2 CAV, 3 VAV, 4 VAVC4, 5 PCO. COMFORT units: manual and DCV only | [V S2, S1 §5.1] |
| 25003 | AQS sensor | 0 none, 1 CO₂ 2000, 2 CO₂ 1100, 3 RH, 4 VOC, 5 external 0–10 V | [V S2] |
| 25008 | input DI-4 | 0 fire, 1 nonoccupied (PIR); default 1 | [V S2] |
| 25009 | temperature sensor for control | 0 supply, 1 extract, 2 room. Enum also names 3 thermostat, 4 room BMS, but max is 2 | [V S2] |
| 25019 / 25020 | filter working hours (0–3000) / filter max hours (200–3000, 1440) | | [V S2] — S1: 25019 "filter time activate 0/1"; S3: max 1000–5000 h |
| 25027 | DCV "breathing" | 0/1 | [V S2] |
| 25030 / 25031 | fire: 0 fans off, 1 both, 2 supply only (default), 3 exhaust only; fire flow % | | [V S2] |

### 3.5. Others

- **Clock** TIME (input 17000–17006) and TIME_DRIVER (holding 17000–17007, `SetFlag` 17007 applies) [V S2]. The unit uses its clock for timers and the night-ventilation season [V S3].
- **Week timer** TIME_SWITCH_WEEK 27000…: per day several slots of 6 registers — on, off, airflow, temperature, mode (0 manual, 1 auto, 2 pseudo-off), heat (AC only) [V S2]. A year timer in 28000… [V S2].
- **Error log** ERROR_LOG_AHU 30000…, a snapshot of time and status words per entry; ERROR_LOG_DRIVER 29900–29902 selects buffer, bank, clears [V S2].
- **Outdoor temperature from BMS:** 20044 enables, 23002 holds the value × 10 [V S2]. 23000–23003 are marked air-curtain only [V S2]. Whether a Venus regulates on a written room temperature: [GAP].
- **Direct control** 35000–35009 drives outputs and fans directly, for a hardware test [V S2]. Not for operation [I].

## 4. Behaviour

### 4.1. Manual and DCV

- **Manual:** "The unit ventilates at the chosen power, independent of the AQS." Temperature and fan power can be set [V S3 MENU 01, §7].
- **DCV:** only with an air quality sensor wired to the unit (0–10 V: CO₂, RH, VOC). Fan power follows the sensor between the low and high limits; only the temperature can be set [V S3 MENU 01, MENU 08, §7].
- **DCV breathing:** at minimum concentration the unit stops, then every 15 min runs 2 min at minimum flow to sample; above the max limit it ventilates again [V S3 MENU 08].
- Switching manual ↔ DCV is a service setting (25000), not a SHARE command [V S2]. Whether a write to 25000 takes effect without a reset: [GAP].
- Each flat already has room IAQ sensors (CO₂) on the PLC ([matter/11](matter/11-thermostat.md) input). The PLC could run demand control itself and write 21002 in manual mode, so no AQS is wired to the unit [I].

### 4.2. Boost

- Started by the panel button, the input 13/14, or 21009 [V S3 MENU 15, S2].
- Runs `BoostTimer` minutes at `BoostFlow` [V S2].
- With `BoostFromOff`, an external button starts it from standby. After it ends the unit does **not** go back to standby; it keeps running at the value it had before standby [V S3 MENU 15].
- Whether 21009 resets itself to 0 when the timer ends: [GAP].

### 4.3. Nobody (nonoccupied)

- Input 15/16 is either PIR or fire (25008), not both [V S3 MENU 02, MENU 13].
- After a PIR trigger the mode stays active for `NoBodyTimeOut`; `NobodyFlow` is 20–50 % [V S3 MENU 14, S2]. Which state uses that flow — after presence or after its absence: [GAP].
- "OCCUPANCY is only used in MANUAL mode" [V S1 §5.1].
- 21010 sets nonoccupied mode from Modbus [V S2].

### 4.4. Fire

Highest priority; "deactivates all other modes, including frost protection". Reaction set by 25030/25031 [V S3 MENU 13].

### 4.5. Night ventilation (free cooling)

- If enabled and all conditions hold, the **exhaust fan stops** and the supply fan runs at the night flow: overpressure ventilation without heat recovery. The building must let the air out (e.g. windows on micro-ventilation) [V S3 MENU 16].
- Conditions: date and time from 20017–20024, extract temperature (INT1) above the set value (12–25 °C) [V S2, S3]. Defaults read as a season 1 June – 1 September with a nightly window 20:00–6:00 [I].
- Evaluated also in standby: at the set time the unit starts and checks whether night ventilation can run ("pre-free-cooling", 15001 bit 6) [V S3 MENU 16, S2].
- 21011 switches it at runtime [V S2].

### 4.6. Supply temperature

- Control sensor: supply duct (fast, same supply temperature everywhere), extract duct or room (slow, single-zone) [V S3 MENU 09].
- Supply duct limits 15–20 °C min, 25–45 °C max; if the minimum is not reached the unit reduces its flow (error 74) to avoid condensation on the ducts — recommended to keep on [V S3 MENU 10, §9].
- Recommended: control on the extract duct or room sensor; supply min 15 °C, max ≥ 30 °C, flow reduction on [V S3 recommended settings].
- With only a preheater, the setpoint has little effect on supply temperature [I]. Post-heater presence on our units: [GAP] — 10123.

### 4.7. Filters

- Time-based: after the set hours the panel shows icon 9; reset after a change (21016) [V S3 §8.2, MENU 06].
- Errors 6/7 "supply/extract filter clogged" — the unit keeps running [V S3 §9].
- What 15044/15045 % mean (time used, or condition): [GAP].

### 4.8. Errors that stop the unit

From the manual's table [V S3 §9]:

| Display | Unit | Status bit [I — by name] |
|---|---|---|
| 1, 3 — electric heater 1 / preheater overheated | ventilates | 15002 bit 7, 6 |
| 4, 5 — supply / extract fan error | **stops** | 15002 bit 0, 1 |
| 6, 7 — filter clogged | ventilates | 15002 bit 2–5 |
| 12 — CO₂ sensor | ventilates | 15002 bit 10 |
| 16–25 — temperature sensor faults | ventilates | 15004 |
| 74 — duct minimum not reached | limited | 15001 bit 7 |
| condensate | runs | 15002 bit 15 |

### 4.9. Panel lock

Menu 23: none, on/off only, on/off + temperature + flow, temperature + flow, or full lock behind a PIN [V S3 MENU 23]. A Modbus register for it: [GAP].

## 5. Discrepancies between the sources

| Item | S1 (guide) | S2 (spreadsheet) | S3 / S5 |
|---|---|---|---|
| 21002 unit | % | ‰ of fan power | panel: % in 10 % steps |
| 25019 | "filter time activate" 0/1 | filter working hours 0–3000 | — |
| Filter max hours | 200–3000 | 200–3000, default 1440 | 1000–5000 h |
| Boost default | — | 3 min | S5: 30 min |
| 15000 bit 0 enum | — | listed "ON OFF" for 0/1 | — |
| Modbus TCP on COMFORT | SUPERIOR only | `EhternetModule` 10110 default fitted; NETWORK 26000… | S3: RJ45 "Ethernet, Modbus TCP, BACnet", menus 21 Network and 38 BACnet, app pairs by IP and PIN |

Enum lists in S2 are not always in value order (e.g. "ADB_ON ADB_OFF", "RUN_INDICATION NO_RUN") [V S2]. Every enum must be checked on the unit before a driver relies on it [I].

## 6. Proposals for a driver (not binding)

- **P1 — driver or definition.** Two patterns exist: a third-party Modbus definition with maker-prefixed kinds (07a §10.5, `dyp.ds1603da`) or a dedicated driver (`driver-mimb19n`, M3.3c). AirGENIO has bit fields, ‰ scaling, service registers that need a reset, and its own timer and clock — closer to a driver [I].
- **P2 — read the fitted hardware at start** (10105, 10119, 10123, 10129, 10130, sensor flags) and expose only what exists.
- **P3 — one owner of the schedule.** Either the unit's timer (21004) or evok-node rules, not both. If rules: set 21004 = 0 and keep the unit's clock in sync (17000…).
- **P4 — demand control in the PLC** from the rooms' IAQ CO₂, writing 21002 in manual mode (§4.1). The unit's own DCV stays unused.
- **P5 — slow polling.** Status 15000–15049 in one or two FC 04 reads; SHARE 21001–21016 in one FC 03 read. Rate and gaps to be measured [I].

## 7. Gaps

- Unit size, firmware (16029), fitted options (FACTORY_SET).
- PDU = listed − 1; enum order; 15049 scaling; 21002 % vs ‰.
- Panel and Modbus on one bus or two; write pacing.
- 25000 without a reset; 21009 self-reset; nobody-mode semantics; 15044/15045 meaning.
- EXT2 vs EXT3 placement; post-heater; bypass (10129).
- A Modbus register for the panel lock; whether a written room temperature is used.
- Modbus TCP on our COMFORT units (§5): if it works, the unit could also be reached over Ethernet.

## 8. Sources

- S1 — 2VV, "AirGENIO Modbus RTU/TCP guide — for units with COMFORT or SUPERIOR control", v1, 2022-03-11, 52 pp., supplied by Tomas 2026-10-28: [`appendix/2vv-airgenio-modbus-guide-v1.pdf`](appendix/2vv-airgenio-modbus-guide-v1.pdf).
- S2 — 2VV, Modbus register spreadsheet `MODBUS_V1_FW150_151.xlsx` (firmware 150/151), supplied by Tomas 2026-10-28: [`appendix/2vv-airgenio-modbus-registers-fw150-151.xlsx`](appendix/2vv-airgenio-modbus-registers-fw150-151.xlsx). Sheet names are cited.
- S3 — 2VV, "VENUS AirGENIO Comfort — instalace, provoz a obsluha" (CZ), 24 pp., supplied by Tomas 2026-10-28: [`appendix/2vv-venus-airgenio-comfort-manual-cz.pdf`](appendix/2vv-venus-airgenio-comfort-manual-cz.pdf). Chapter and menu numbers are the document's own.
- S4 — 2VV, heat recovery units catalogue (CZ), 2020, on tzb-info: https://mojefirma.tzb-info.cz/download/_/company.32359/20201210142455.2vv_heat_recovery_units-cz.pdf
- S5 — 2VV, VENUS catalogue excerpt, ArchiExpo: https://pdf.archiexpo.com/pdf/2vv/venus/59710-286875.html
