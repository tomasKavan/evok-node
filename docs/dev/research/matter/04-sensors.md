# 04 — Sensors

**Research, not design.** Matter Contact, Light, Occupancy, Temperature, Humidity and Air Quality Sensor: what the spec requires, value encodings, how real devices and controllers behave, Apple Home support, and which Unipi hardware and evok-node drivers can feed each type (§8a). Feeds 12c's sensor sections.

Spec data from the connectedhomeip data model, `data_model/1.5/` (S1, S2); spec prose from matter.js's generated cluster docs, which cite Matter 1.6.1 section numbers (S3). Up to `data_model/1.7/` these six device types change only by dropping Zigbee elements [V-src S1]. Their clusters do change after 1.5 [V-src S2, `1.6/`, `1.7/`]:

| Since | Change |
|---|---|
| 1.6 | `P` (reportable) quality removed from every cluster here; `Min`/`MaxMeasuredValue`, `Tolerance` become fixed (`F`) |
| 1.6 | Boolean State: feature `CHGEVENT` makes `StateChange` mandatory. Boolean State Configuration: feature `FAULTEV`. Occupancy Sensing: feature `OCCEVENT` makes `OccupancyChanged` mandatory |
| 1.7 | Occupancy Sensing: provisional feature `PRED` (predicted occupancy). Concentration: provisional Smoke Concentration `0x0434` |

## 1. Device types

All six are endpoint-scoped simple devices. Identify is mandatory on each [V-src S1].

| Device type | Since | Mandatory | Optional |
|---|---|---|---|
| Contact Sensor `0x0015` | 1.0 | Boolean State `0x0045` | Boolean State Configuration `0x0080` (1.3) |
| Light Sensor `0x0106` | 1.0 | Illuminance Measurement `0x0400` | — |
| Occupancy Sensor `0x0107` | 1.0 | Occupancy Sensing `0x0406` | Boolean State Configuration (1.4) — sensitivity |
| Temperature Sensor `0x0302` | 1.0 | Temperature Measurement `0x0402` | Thermostat User Interface Configuration `0x0204` (1.5) |
| Humidity Sensor `0x0307` | 1.0 | Relative Humidity Measurement `0x0405` | — |
| Air Quality Sensor `0x002C` | 1.2 | Air Quality `0x005B` | Temperature, Relative Humidity, ten concentration clusters (§5) |

"Since" of an optional cluster is the first `data_model/` version that lists it [V-src S1].

## 2. Measurement encodings

Every `MeasuredValue` below is reportable and nullable; `MinMeasuredValue`/`MaxMeasuredValue` are mandatory but nullable (null = not defined) [V-src S2].

| Cluster | `MeasuredValue` | Range | Special values [V-src S3] |
|---|---|---|---|
| Temperature | int16, 0.01 °C | Min ≥ −27315 (−273.15 °C), Max ≥ Min + 1 [V-src S2] | null = unknown |
| Relative Humidity | uint16, 0.01 % | 0–10000 [V-src S2] | null = unknown |
| Illuminance | uint16, `10000 × log10(lx) + 1` | 1 lx – 3.576 Mlx ↔ 1–0xFFFE | `0` = too low to measure; null = invalid |
| Concentration (§5) | single float, unit in `MeasurementUnit` | Min/Max as declared | null = unknown or out of range |

`Tolerance` is optional on Temperature, Humidity and Illuminance, uint16 ≤ 2048, in the same units [V-src S2]. Illuminance also has optional `LightSensorType` (photodiode, CMOS, null) [V-src S2].

Examples [I — arithmetic]:

```
21.5 °C   → 2150          −5.25 °C → −525
45.3 %    → 4530
1 lx      → 1             500 lx   → round(10000·log10(500) + 1) = 26991
10 000 lx → 40001         0.4 lx   → 0
```

One step of the log encoding is a factor 10^(1/10000), about 0.023 % of the value [I]. Home Assistant Matter Hub, a matter.js bridge, encodes `< 1 lx` as 0 and clamps the rest to 1–0xFFFE [V-src S4].

## 3. Contact Sensor — Boolean State

- `StateValue`: bool, reportable, **not nullable** [V-src S2]. For Contact Sensor: `false` = open or no contact, `true` = closed or contact [V-src S3]. Espressif's endpoint API uses the same (`true` = closed) [V S16].
- There is no "unknown" value. An endpoint can only say "don't know" by not answering [I].
- `StateChange` event: optional [V-src S2].
- Boolean State Configuration, when present: sensitivity levels (2–10), visual/audible alarms with suppress, and `SensorFault` (bit `GeneralFault`) with an optional event [V-src S2]. It is built for alarm-like sensors (leak, freeze); for a contact sensor only `SensorFault` looks useful [I].
- No subtype: door, window and garage door are all the same Contact Sensor [V-src S1]. HA Matter Hub maps HA's `door`, `window`, `garage_door`, `opening` all to it [V S5].

## 4. Occupancy Sensor — Occupancy Sensing

Cluster revision 5 (Matter 1.4) added sensing modalities, `HoldTime` and the `OccupancyChanged` event [V-src S2].

| Element | Facts [V-src S2, S3] |
|---|---|
| `Occupancy` | bitmap, bit 0 = occupied, other bits 0 — a boolean in practice. Reportable, **not nullable** |
| Features | at least one of `OTHER`, `PIR`, `US` (ultrasonic), `PHY` (physical contact), `AIR` (active IR, time-of-flight), `RAD` (radar), `RFS` (RF sensing), `VIS` (vision) |
| `OccupancySensorType`, `OccupancySensorTypeBitmap` | mandatory but deprecated; frozen at revision 4 (PIR, ultrasonic, PIR+ultrasonic, physical contact). Kept for older controllers; the features carry the modality |
| `HoldTime` | optional, seconds, writable with *manage* privilege, kept across power loss. `Occupancy` stays 1 until `HoldTime` after the last detection; a new detection inside it extends one occupied period. `0` shall not be used; low values should be avoided (report traffic) |
| `HoldTimeLimits` | `{HoldTimeMin ≥ 1, HoldTimeMax, HoldTimeDefault}`, mandatory with `HoldTime` |
| `PIR…`/`Ultrasonic…`/`PhysicalContact…Delay`, `…Threshold` | legacy per-modality delays; `…OccupiedToUnoccupiedDelay` equals `HoldTime` |
| `OccupancyChanged` event | optional |
| Sensitivity | through a Boolean State Configuration on the same endpoint (device revision 4) |

So in Matter the **off-delay lives in the sensor**, and a controller may change it [V-src S2].

How controllers read the modality:

- Home Assistant maps every Occupancy Sensing endpoint to `occupancy`, ignoring `OccupancySensorType`; a PIR sensor (IKEA MYGGSPRAY, type 0) is not shown as `motion`. Issue open since 2026-03 [V S7].
- HA Matter Hub publishes HA `motion` as feature `PIR`, and HA `occupancy`/`presence` as feature `PHY` with type `PhysicalContact` [V-src S4, S5].

## 5. Air Quality Sensor

### 5.1. Air Quality cluster

- `AirQuality`: enum `Unknown`, `Good`, `Fair`, `Moderate`, `Poor`, `VeryPoor`, `ExtremelyPoor`. Mandatory, **not nullable**; `Unknown` is the "no value" [V-src S2].
- `Fair`, `Moderate`, `VeryPoor`, `ExtremelyPoor` are features: a device declares which levels it uses. `Unknown`, `Good`, `Poor` are always there [V-src S2].
- The cluster is a classification only — "distinct levels with human-readable labels" [V-src S3]. The spec data gives no thresholds, so which ppm or µg/m³ is "Poor" is the device's [I].
- So a bridge with only a concentration must compute a level itself. HA Matter Hub does it for CO₂: ≤ 800 ppm `Good`, ≤ 1000 `Fair`, ≤ 1400 `Moderate`, ≤ 2000 `Poor`, ≤ 5000 `VeryPoor`, above `ExtremelyPoor` (comment: German UBA / ASHRAE) [V-src S4].

### 5.2. Concentration clusters

One cluster definition, used through aliases — one cluster id per substance [V-src S2]:

| Substance | Cluster | | Substance | Cluster |
|---|---|---|---|---|
| CO | `0x040C` | | PM2.5 | `0x042A` |
| CO₂ | `0x040D` | | Formaldehyde (HCHO) | `0x042B` |
| NO₂ | `0x0413` | | PM1 | `0x042C` |
| O₃ | `0x0415` | | PM10 | `0x042D` |
| Radon | `0x042F` | | TVOC | `0x042E` |

| Element | Facts [V-src S2] |
|---|---|
| Features | at least one of `MEA` (numeric) and `LEV` (level). `MED`, `CRI` need `LEV`; `PEA` (peak), `AVG` (average) need `MEA` |
| `MeasuredValue`, `Min…`, `Max…` | single float, nullable. Mandatory with `MEA` |
| `MeasurementUnit` | fixed: ppm, ppb, ppt, mg/m³, µg/m³, ng/m³, particles/m³, Bq/m³. Mandatory with `MEA` |
| `MeasurementMedium` | fixed: air, water, soil. Always mandatory |
| `LevelValue` | `Unknown`, `Low`, `Medium`, `High`, `Critical`. Mandatory with `LEV` |
| `Peak…`/`Average…MeasuredValue` + `…Window` | window in seconds, ≤ 604800 (7 days) |
| `Uncertainty` | optional, with `MEA` |

HA Matter Hub enables only `MEA` on every concentration cluster: `MEA` and `LEV` together failed in matter.js ("Behaviors have errors") [V-src S4]. It also publishes **one Air Quality Sensor endpoint per pollutant** — `AirQuality` plus one concentration cluster — rather than one endpoint with many [V-src S4].

## 6. Several sensors in one product

A Matter device type belongs to an endpoint; a multi-sensor is several endpoints of one node, or of one bridged device [V-src S1]. How they are split matters for Apple Home:

| Shape | Result |
|---|---|
| Temperature Measurement as a cluster on an Air Quality Sensor endpoint | not shown in Apple Home; shown when it is its own Temperature Sensor endpoint. Apple DTS: "please file a bug" (2025-10) [V S6] |
| Relative Humidity cluster stacked on a Temperature Sensor endpoint | Apple Home shows no humidity [V-src S4] |
| Bridged node with one sub-endpoint per reading, each with its own device type | Apple, Google and Alexa show each reading with its own icon and unit; SmartThings does not read sub-endpoints [V-src S4, V S5] |
| Pressure Sensor endpoint | not shown in Apple Home [V S5] |

Aqara FP300 (presence, light, temperature, humidity) shows each as its own page in Apple Home, with one battery level for the device [V S10].

## 7. Real devices and experiences

| Device / case | What happened |
|---|---|
| IKEA MYGGBETT, MYGGSPRAY, TIMMERFLOTTE, ALPSTUGA | Matter range: door/window, motion, temperature/humidity, CO₂ + PM2.5 + temperature (+ humidity per a reviewer) [V S11, S12] |
| IKEA MYGGSPRAY | PIR occupancy: `OccupancySensorType` 0, bitmap PIR [V S7] |
| IKEA ALPSTUGA | users: temperature does not reach Apple Home [V S12, user reviews] |
| SONOFF AirGuard (CO₂; PM2.5/PM10), Matter over Wi-Fi | reader comment: air quality in Apple Home, temperature not passed [V S13] |
| Aqara Motion and Light Sensor P2 | reported as occupancy, not motion; illuminance only reported on motion or when read; no hold-time or sensitivity settings [V S8] |
| Aqara FP300 (mmWave + PIR) | `HoldTime` used, minimum 10 s; sensitivity through Boolean State Configuration; reporting rates and sensor enable/disable not settable over Matter; detection range Zigbee-only [V S9] |
| Tasmota, MH-Z19B CO₂ as Air Quality Sensor (2024-12) | Apple Home showed air quality "Unknown"; fixed in firmware, after which air quality showed. CO₂ value in Apple Home not confirmed [V S14] |
| esp-matter, CO₂ cluster added to an Air Quality Sensor | not shown in Apple Home; in Home Assistant the value froze until a data-type fix ("Wrong TLV type") [V S15] |

## 8. Apple Home

| Topic | Finding |
|---|---|
| Device types | all six supported [V S17, S4] |
| How Matter reaches Home.app | Matter is bridged into HomeKit's HAP model; a shape HAP has no place for may not show. Apple's advice: use HAP as the reference, "experiment … and ship what works" [V S6] |
| Air quality readings | shown for CO, CO₂, PM2.5, PM10, TVOC, NO₂, O₃; HCHO, radon and PM1 show only the air-quality level [V S5]. HAP's Air Quality service carries O₃, NO₂, SO₂, PM2.5, PM10 and VOC density; CO and CO₂ are separate services; HCHO is not in HAP [V S6] |
| Units | Apple Home needs µg/m³ for PM2.5, PM10 and TVOC [V-src S4, code comments]. HA Matter Hub uses ppm for CO₂ [V-src S4] |
| Air-quality levels | Matter has 6 levels + `Unknown`; HAP's characteristic has 5 (excellent, good, fair, inferior, poor) + unknown [I]. How Apple maps them: [GAP] |
| Occupancy | HA Matter Hub rates it "partial", no reason given [V-src S4]. A review lists Matter occupancy sensors (P2, FP300) under occupancy, with no motion tile even for the FP300's PIR [V S10]. Whether feature `PIR` makes Apple show a motion sensor: [GAP] |
| Settings | `HoldTime` and sensitivity not seen in Apple Home; FP300 settings are in Aqara's app [I from S10] |
| Contact Sensor `false`/`true` shown as open/closed | [I] — no source states it |

## 8a. What our sources deliver

Unipi hardware and the other evok-node drivers that can feed these six types. Driver facts are from the design docs; hardware facts from Unipi documents.

### 8a.1. Source kinds

| Source | Kind (driver) | Facts |
|---|---|---|
| Digital input | `unipi.di` (08, 09) | `{value, counter}` per poll; poll `fast` 100 ms onboard, 200 ms on RS-485 extensions [V 08 §8, 09 §4]. True at 7–35 V DC, false below 3 V, 3–7 V undefined; a separate supply per input group is recommended to keep isolation [V S22]. Debounce 5 ms factory; counter counts rising edges, so a pulse shorter than one poll still shows as a counter step [V research/02 §4.9] |
| Analog input, resistance | `unipi.ai` `resistance3w`/`resistance2w` (08, 09) | value in Ω, no temperature conversion in any driver [V 07a §10.1]. Patron/Neuron sections 2–3: 0–1960 Ω 3-wire, 0–100 kΩ 2-wire; xS52/xS54: 75–2000 Ω, 1–20 kΩ; Edge: 90–2000 Ω on AI4/AI5 only; S-size units measure resistance only through the section-1 AO [V research/02 §4.5, research/06]. Conversion takes 400 ms (Patron/Neuron), 200 ms (xS5x), 100 ms (Edge) [V research/02 §4.5] |
| Analog input, 0–10 V / 0–20 mA | `unipi.ai` `voltage10`/`current20` | for third-party transmitters; the V or mA → °C/%/lx/ppm scaling is the transmitter's datasheet [I]. Unipi sells no lux, CO₂ or presence sensor [V S23] |
| 1-Wire chips | `unipi.temp`, `unipi.humidity` (10) | through `owserver`; scan default 60 s, lengthened automatically when the bus can't keep up [V 10 §7]. DS2438 humidity: one of five `owserver` attributes (`HIH4000/humidity`, `HIH5030/humidity`, …), all disabled until adoption picks one [V 10 §4]. Up to 15 sensors per bus [V research/02 §5] |
| xG18 extension | 8 × `unipi.temp` with `valid`, `intervalS` (09) | DS18B20 only, int16; one validity bit and one measuring interval (s) per channel [V xG18 map v1.1, 07a §10.3] |
| IAQ sensor | `unipi.temp`, `unipi.humidity`, `unipi.lux`, `unipi.co2`, `unipi.vocIndex`, `unipi.vocAccuracy`, `unipi.vocCo2Eq`, `unipi.pressure`, … (09) | §8a.2 |
| DALI | — (12) | DALI-2 occupancy and light sensors are control devices (24-bit frames): out of scope in 12 v1 [V 12 §1, §13] |
| `matter` origin | — (12a §4a) | any Matter sensor of §7, already in Matter's shape |

Unipi's own 1-Wire and analog sensors [V S19, S20, S21]:

| Product | Chip / element | Measures | Accuracy, range |
|---|---|---|---|
| 1-Wire probes (1.5–10 m), pipe-surface, sump, outdoor | DS18B20 | temperature | ±0.5 °C (−10…85 °C); −55…+125 °C by model |
| 1W-T-IB2 wall sensor (1W-T-IB, discontinued) | DS18B20 | temperature | ±0.5 °C; −40…+85 °C |
| 1W-TH-IB2 wall sensor (1W-TH-IB, discontinued) | DS2438 + Honeywell RH (IB: HIH5030) | temperature, humidity | ±2 °C (IB: ±1 °C); RH ±3 %, 11–89 % |
| PTS 310A, PTS 320, PTS 350B | Pt1000 | temperature (ambient, sump/duct, pipe surface) | −50…+150 °C by model |

Pt1000 fits both resistance ranges: −50 °C ≈ 803 Ω, 0 °C = 1000 Ω, 150 °C ≈ 1573 Ω [I — IEC 60751 coefficients].

### 8a.2. IAQ sensor

Variants RW-TH, RLW-TH, RW-THC, RLW-THC; `L` = LoRaWAN. All have Modbus RTU (RS-485), Modbus TCP, MQTT, HTTP and a digital output [V S18 §1].

| Quantity | Variants | Range | Accuracy [V S18 §2] |
|---|---|---|---|
| Temperature | all | −40…+85 °C | ±0.5 °C; user offset in settings |
| Relative humidity | all | 0–90 %, non-condensing | ±2 % (20–80 %) |
| Ambient light | all | 0–7500 lx | indicative; "indirect", depends on placement [V S18 §4] |
| VOC index | **all** | 0–500 | indicative |
| CO₂ | THC only | 300–5000 ppm | ±30 ppm ± 3 % |
| Pressure | all | 300–1100 hPa | ±5 hPa |
| Dew point, absolute humidity | all | — | computed |

- **VOC index** is relative, not a concentration: ~25 = clean, 250 = polluted; it adapts to the room over the last 4 days. `VOC accuracy` 0–3: 0 = invalid (after power-up), 3 = stable. `VOC CO₂ equivalent` (ppm) "does not represent the CO₂ concentration" [V S18 §4, §4.2].
- **CO₂** needs several minutes after power-up. Automatic calibration every 7 days needs fresh air at least 1 h a day; it overwrites a manual calibration [V S18 §4.1].
- **Averaging**: a moving average, set per interface; for Modbus configurable, 0 = off [V S18 §4.3].
- **Unset value**: HTTP sends `null` [V S18 §6.4]; Modbus `float32` has no null and the map doesn't say — [GAP], already owed in `modbus-reg-map-notes/accessory-iaq.md`.
- **Variant over Modbus**: the input map has no model register [V CSV]; a TH unit can't be told from a THC one by register content alone [I].
- Modbus TCP: one open connection at a time [V S18 §6.6].
- LED colour follows CO₂ (VOC on TH): green below ≈ 450 ppm, red above ≈ 2000 ppm [V S18 §5].

### 8a.3. Fit per Matter type

| Matter type | Sources | Notes [I unless tagged] |
|---|---|---|
| Contact Sensor | `unipi.di` + reed / magnetic contact, external supply | Matter `true` = closed (§3). A DI is `true` when the contact conducts; a contact that conducts with the door shut matches Matter directly, one that conducts with it open needs inverting |
| Occupancy Sensor | `unipi.di` + PIR or presence detector with relay / open-collector output | the detector usually has its own hold time; Matter's `HoldTime` (§4) is then a second delay on top. No Unipi occupancy sensor exists [V S23]; DALI-2 sensors out of scope [V 12] |
| Light Sensor | IAQ `unipi.lux`; `unipi.ai` + 0–10 V lux transmitter | IAQ lux is indicative (§8a.2) |
| Temperature Sensor | 1-Wire DS18B20 / DS2438, xG18, IAQ, `unipi.ai` + Pt1000 | Pt1000 needs an Ω → °C conversion that no driver does [V 07a §10.1] |
| Humidity Sensor | IAQ, 1-Wire DS2438 + HIH, `unipi.ai` + transmitter | 1W-TH-IB2: 11–89 % only [V S19] |
| Air Quality Sensor | IAQ (THC: CO₂ + VOC index; TH: VOC index only) | CO₂ → CO₂ concentration cluster in ppm. VOC index has no Matter home: TVOC is a concentration with a unit (§5.2), the index is unitless. So the `AirQuality` level must be derived from CO₂ and/or the VOC index. `VOC CO₂ equivalent` is not a CO₂ value. Pressure → Matter Pressure Sensor, not shown by Apple (§6). Dew point and absolute humidity: no Matter cluster |

### 8a.4. Conflict with our own docs

- 07a §10.3 says `vocIndex`/`vocAccuracy`/`vocCo2Eq` are bound only on the THC variant. The IAQ manual lists VOC on all four variants; only CO₂ differs [V S18 §1]. This also answers part of `accessory-iaq.md`'s "which quantities exist on which variant".

## 9. Gaps

- Apple's mapping of the 7 Matter air-quality values to HAP's 6.
- Whether Apple Home shows a PIR-feature Occupancy Sensor as motion.
- Whether Apple Home shows the CO₂ value of an Air Quality Sensor today — S5 says yes, older reports (S14, S15) say no.
- What the IAQ sensor's Modbus registers hold for an unset value (CO₂ on a TH unit, VOC right after power-up).

## 10. Sources

- S1 — connectedhomeip `data_model/1.5/device_types/` (ContactSensor, LightSensor, OccupancySensor, TemperatureSensor, HumiditySensor, AirQualitySensor .xml), commit `660c022`: https://github.com/project-chip/connectedhomeip/tree/660c0227dd4a206f05ba1696830bfd1e267d4cee/data_model/1.5/device_types
- S2 — connectedhomeip `data_model/1.5/clusters/` (BooleanState, BooleanStateConfiguration, IlluminanceMeasurement, OccupancySensing, TemperatureMeasurement, WaterContentMeasurement, AirQuality, ConcentrationMeasurement .xml): https://github.com/project-chip/connectedhomeip/tree/660c0227dd4a206f05ba1696830bfd1e267d4cee/data_model/1.5/clusters
- S3 — matter.js generated cluster definitions with spec text (`boolean-state`, `illuminance-measurement`, `occupancy-sensing`, `temperature-measurement`, `relative-humidity-measurement`, `air-quality`, `concentration-measurement`), commit `d2804e5`: https://github.com/matter-js/matter.js/tree/d2804e5c9846e2d9503f4bc988c558b9a2d11958/packages/types/src/clusters
- S4 — Home Assistant Matter Hub (matter.js bridge), commit `664575a`: `packages/backend/src/matter/behaviors/` (illuminance, occupancy, concentration servers), `…/endpoints/legacy/sensor/devices/co2-sensor.ts`, `…/services/bridges/bridge-registry.ts`, `packages/common/src/entity-mapping.ts` (controller matrix): https://github.com/RiDDiX/home-assistant-matter-hub/tree/664575af68bd467508b2be2c0043a78e4d1565a7
- S5 — HA Matter Hub docs, Supported Device Types: https://riddix.github.io/home-assistant-matter-hub/supported-device-types
- S6 — Apple developer forum, "Questions about displaying sensor data (Temperature/HCHO/TVOC) for Matter device in HomeKit", DTS answer 2025-10: https://developer.apple.com/forums/thread/801905
- S7 — home-assistant/core #164839, "Matter OccupancySensing cluster ignores OccupancySensorType" (2026-03): https://github.com/home-assistant/core/issues/164839
- S8 — Matter Alpha, Aqara P2 motion & light sensor review: https://www.matteralpha.com/review/aqara-p2-motion-light-sensor
- S9 — Matter Alpha, Aqara FP300 review: https://www.matteralpha.com/review/aqara-fp300-review-the-4-in-1-matter-sensor-that-runs-on-batteries
- S10 — HomeKit News, Aqara FP300 review (2025-12): https://homekitnews.com/2025/12/15/aqara-presence-multi-sensor-fp300-review/
- S11 — Notebookcheck, IKEA Matter sensors in the US: https://www.notebookcheck.net/IKEA-Matter-compatible-smart-home-sensors-now-available-in-the-US.1181412.0.html
- S12 — IKEA, ALPSTUGA product page and reviews: https://www.ikea.com/us/en/p/alpstuga-air-quality-sensor-smart-70609396/
- S13 — AppleHome Authority, SONOFF Matter air quality sensors (comment 2026-03-17): https://www.applehomeauthority.com/sonoff-release-two-matter-air-quality-sensors/
- S14 — Tasmota discussion #22701 and issue #22704, MH-Z19B Air Quality Sensor in Apple Home: https://github.com/arendst/Tasmota/discussions/22701 · https://github.com/arendst/Tasmota/issues/22704
- S15 — esp-matter #873, "Air quality measurement issue": https://github.com/espressif/esp-matter/issues/873
- S16 — Espressif Arduino Matter, Contact Sensor endpoint: https://docs.espressif.com/projects/arduino-esp32/en/latest/matter/ep_contact_sensor.html
- S17 — connectedhomeip `docs/guides/darwin.md`, supported device types: https://pigweed.googlesource.com/third_party/github/project-chip/connectedhomeip/+show/HEAD/docs/guides/darwin.md
- S18 — Unipi, Indoor Air Quality sensor, user guide and technical documentation (in repo: `docs/dev/modbus-reg-map/accessories/Accessory-IAQ.pdf`); KB page: https://kb.unipi.technology/en:hw:05-sensors:iaq
- S19 — Unipi e-shop, 1-Wire temperature and humidity sensors: https://www.unipi.technology/products/1-wire-temperature-and-humidity-sensors-382
- S20 — Unipi news, 1W-T-IB and 1W-TH-IB (2019-02-07): https://unipi.technology/news/try-the-brand-new-unipi-1-wire-sensors-264
- S21 — Unipi KB, analog sensors (PTS Pt1000): https://kb.unipi.technology/en:hw:05-sensors:analog
- S22 — Unipi KB, connection of digital inputs: https://kb.unipi.technology/_export/raw/en:hw:connection-of-di-hidden
- S23 — Unipi KB, sensors index (1-Wire, analog, IAQ only): https://kb.unipi.technology/en:hw:05-sensors
