# 15 — Rainwater tank: sensors, measurement, descaler bypass

**Research, not design.** Facts for the rainwater driver (12i) and its home device (12c-11): the ultrasonic level sensor, the 4–20 mA pressure sensor, smoothing, the descaler bypass. Tank-fill prior art is in [matter/09 §4.4](matter/09-water.md) and is not repeated here.

Input from Tomas (2026-10-25 – 10-28), drawing 3.3.2.5 "Akumulační soustava – Schéma" v2 (2026-05-05):

- Three box tanks: lower accumulation 6 m³, upper accumulation 4 m³, retention 4 m³. Level → volume is linear. Water height in every tank ≤ 2000 mm.
- Lower tank: ultrasonic WL.009.02, floats FS.009.02 (high, 9/10) and FS.009.01 (low, 1/10), garden pump (Zahradní vodárna) inside.
- Upper tank: pressure sensor WL.009.01, 4–20 mA, on the outlet pipe, not in the tank. The drawing's text names it FS.009.03 — a mistake; FS.009.03 is the retention float.
- Retention tank: ultrasonic WL.009.03, float FS.009.03; sludge pump with its own floats, powered only, no feedback.
- WL.009.02 and WL.009.03 are DS1603DA-3R V2.0 on an RS-485 port of their own — nothing else on that line.
- Garden pump: runs on its own pressure switch, has its own dry-run protection, powered through an RO's NO contact.
- Valves EV.009.05 (fill upper), EV.009.06 (drain upper), EV.103.01 (mains): NC solenoids, one RO each. EV.009.01–04 are irrigation zones, not part of the tank.
- The descaler bypass valve is on another PLC, a raw output reached over that PLC's WS API.

## 1. DS1603DA-3R V2.0 ultrasonic level sensor

Source: the DYP datasheet "DS1603DA-V2.0 Series Sensor Module" (S1).

### 1.1. Specification

| Item | Value | |
|---|---|---|
| Supply | 10–36 V DC, < 30 mA average at 12 V | [V S1 p2] |
| Blind zone | ≤ 40 mm | [V S1 p2] |
| Range | 40–2000 mm | [V S1 p2] |
| Resolution | 1 mm | [V S1 p2] |
| Accuracy | ±(5 + S × 1 %) mm, S = current level | [V S1 p2] |
| Working period | 2 s default, settable | [V S1 p2] |
| Operating temperature | −15 to +60 °C | [V S1 p1] |
| Test conditions | 2 mm steel container, Ø 160 mm, water, room temperature | [V S1 p2] |

- At 1500 mm the accuracy is about ±20 mm, about ±1.3 % of a 1500 mm tank [I — arithmetic on S1].
- The older DS1603DA V1.0 states a 50 mm blind zone and a 50–2000 mm range [V S3]. The V2.0 numbers apply only to V2.0.
- Container materials named by a reseller: steel, glass, iron, ceramics, non-foamed plastics [V S3]. Tank wall thickness limits: [GAP].

### 1.2. Mounting

- Mounted under the container bottom, outside; measures the liquid height through the wall [V S1 p1].
- The probe needs a couplant and no air gap to the bottom; silicone grease is suggested for the UART sibling DS1603L [V S2].
- The reading is the liquid height above the bottom, not a distance to the surface [I — from the mounting].

### 1.3. Interface

- RS-485, 4 wires: red VCC, black GND, yellow B (DATA−), white A (DATA+) [V S1 p4].
- Two protocols on one port: Modbus RTU and DYP's own; the sensor answers in the protocol of the frame it received [V S1 p4].
- Default 9600 baud, no parity, 8 data bits, 1 stop bit [V S1 p5].
- Modbus needs FC 0x03 and FC 0x06 only [V S1 p5]. Default slave address 0x01 [V S1 p5].

### 1.4. Modbus registers

| Reg | Access | Content | |
|---|---|---|---|
| 0x00 | R | Process value, mm — "the processed value after the sensor has detected liquid level value multiple times" | [V S1 p5] |
| 0x01 | R | Real-time value, mm — each single detection | [V S1 p5] |
| 0x02, 0x03 | — | Reserved | [V S1 p5] |
| 0x04 | RW | Slave address, 0x01–0xF7, "save when powered off" | [V S1 p5] |
| 0x05 | RW | Medium: 0x01 water (default), 0x02 oil; other values invalid | [V S1 p5] |
| 0x06 | RW | Working period N s, 0x01–0x3C (1–60), default 0x02 | [V S1 p5] |

- Example: `01 03 00 00 00 02 C4 0B` → `01 03 04 00 DC 00 DD FB 90` — process 220 mm, real-time 221 mm [V S1 p6].
- A new address applies at once: the example's next read goes to the new address [V S1 p6].
- **No baud-rate register.** The table lists none, so the baud is 9600 for good [I — from S1 p5].
- Whether the medium and period survive a power-off: [GAP] — the datasheet says it only for the address.
- How the sensor filters into the process value (window, method): [GAP].

### 1.5. Behaviour at the edges

- LED: on steadily = powered, no liquid detected; flashing once a second = liquid detected [V S1 p13].
- The value reported with no liquid, or below the blind zone: [GAP]. ESPHome's DS1603L example drops `nan` values (`filter_out: nan`), so that sibling can report no value [V S2]; whether the DS1603DA-3R has an equivalent: [GAP].
- DYP-protocol broadcast address 0xFF answers from any sensor; on a bus with several sensors it collides [V S1 p13]. Modbus broadcast: not described [GAP].

## 2. 4–20 mA pressure sensor on a Unipi AI

- Patron/Neuron section 1 AI: U/I, two modes. Sections 2/3: U/I/R, six modes [V research/06 §2.6]. Which modes a given AI has comes from the hardware definition (07a §10.1).
- Unipi xS5x AI values are `float32` in engineering units [V research/02 §4.5]; in a current mode that is mA [I].
- 07a §10.1 names the current mode `current20`. Edge's sheet states 4–20 mA [V research/06 §2.7]. Whether the Patron's current mode measures 0–20 or 4–20 mA, so whether a value below 4 mA is visible: [GAP] — to check on the unit.
- Patron AI resolution: [GAP]. Unipi 1.1 states 18 bits [V research/06 §2.8].
- NAMUR NE 43 [V S4]:

| Current | Meaning |
|---|---|
| 3.8–20.5 mA | valid measuring range (nominal 4–20 mA) |
| 3.6 – < 3.8 mA, > 20.5 – 21.0 mA | warning range |
| < 3.6 mA | failure low — cable break, dead sensor |
| > 21.0 mA | failure high — short circuit, dead sensor |

- Linear scaling: `mm = (mA − 4) / 16 × rangeMm` [I]. The sensor's own range (kPa or m of water): [GAP] — from its label.

## 3. Pressure sensor on the outlet pipe

- At rest the sensor reads the static head: the water height in the upper tank plus the height difference between the tank bottom and the sensor [I — hydrostatics].
- While water flows through the pipe (EV.009.06 open) the pressure at the sensor drops by the dynamic pressure and the pipe losses up to it, so the level reads low [I]. A flow past a hydrostatic probe is known to falsify the level, by up to ~0.3 m in a reported stilling-well case [V S5].
- Whether the sensor is fully isolated from the flow when EV.009.06 is closed depends on where it sits relative to the valve: [GAP] — from the drawing it sits between the tank and EV.009.06 [I].
- How long the reading takes to settle after the valve closes: [GAP] — to measure.

## 4. Smoothing a level reading

- The DS1603DA-3R filters on its own: register 0x00 is its processed value (§1.4).
- ESPHome recommends filters for the DS1603L because it is slow (one reading "every few seconds") [V S2].
- Common filters (ESPHome) [V S6]:

| Filter | Does |
|---|---|
| `median` | median of the last `window_size` values |
| `sliding_window_moving_average` | mean of the last `window_size` values |
| `exponential_moving_average` | weighted average, `alpha` 0.1 by default |
| `delta` | passes a value only when it differs enough from the last one passed |
| `throttle` | at most one value per interval |

- Causes of a jumping level in a rainwater tank — inflow turbulence, a pump drawing water, waves: [GAP] — no measurement found. A median removes single outliers; an average follows a slow drift [I].

## 5. Descaler bypass

- Softened water on a garden: "in the longer term, it is not recommended" (sodium) [V matter/09 §4.5, S44 there].
- A 3-way diverting valve moves in about 7–8 s (Honeywell VC 7 s, Atlantic ≤ 8 s) [V matter/09 §4.5].
- A 2-wire spring-return valve returns on power loss; a 3-wire valve stays where it was [V matter/09 §4.5]. Which kind the bypass valve is: [GAP].
- Prior art of a bypass switched automatically before filling a tank: [GAP].
- What the lead time must cover: the valve's travel, plus the softened water still in the pipe between the bypass and the tank inlet [I]. Pipe length and volume: [GAP].

## 6. Proposals for 12i (not binding)

- **P1 — DS1603DA kind.** Read 0x00 (process value) as the level; 0x01 as a diagnostic field; period (0x06) as a channel; medium fixed to water. No handshake (09 §7: `none`). Poll at the working period, 2 s.
- **P2 — addresses.** Both sensors ship as 0x01. Re-address one once, alone on the bus, with FC 0x06 on 0x04 — through 07's Raw Relay Driver.
- **P3 — no liquid.** A value below the blind zone (40 mm) reads as 0 %; the low float decides whether the tank is empty, until §1.5's [GAP] is closed on hardware.
- **P4 — 4–20 mA faults.** Outside 3.6–21.0 mA ⇒ the upper level is stale and a sensor alarm is raised (NE 43, §2).
- **P5 — upper level only at rest.** Use the pressure reading only after EV.009.06 has been closed for a settle time; meanwhile keep the last value, marked as held.
- **P6 — smoothing.** A median over a window plus a deadband, on every level, on top of the sensor's own processing.
- **P7 — bypass.** Bypass on → wait a lead time → mains open; mains closed → wait a lag time → bypass off. Both times settable. No bypass, no mains refill.

## 7. Gaps

- DS1603DA-3R: value with no liquid; whether medium and period survive power-off; its internal filter; wall thickness limits.
- WL.009.01: its range and the AI mode used; settle time after EV.009.06 closes.
- Bypass valve: 2- or 3-wire; lead time needed.
- Patron AI resolution.

## 8. Sources

- S1 — DYP (Shenzhen Dianyingpu Technology), "DS1603DA-V2.0 Series Sensor Module" datasheet, 15 pp., supplied by Tomas 2026-10-28: [`appendix/ds1603da-v2.0-datasheet.pdf`](appendix/ds1603da-v2.0-datasheet.pdf). Page numbers are the document's own.
- S2 — ESPHome, DS1603L Ultrasonic Distance Sensor: https://esphome.io/components/sensor/ds1603l/
- S3 — robu.in, Ultrasonic Sensor DS1603DA V1.0 (RS485): https://aws.robu.in/?p=2228839
- S4 — MicroControl, Industrial standard signals (NAMUR NE 43): https://www.microcontrol.net/en/service/measurement-technology/industrial-standard-signals/
- S5 — control.com forum, "Flow dynamic is affecting stillwell, and level reading, for hydrostatic level transmitter": https://control.com/forums/threads/flow-dynamic-is-affecting-stillwell-and-level-reading-for-hydrostatic-level-transmitter.40594/
- S6 — ESPHome, Sensor component, filters: https://esphome.io/components/sensor/
