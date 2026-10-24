# 12c-04 — Sensors

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `ContactSensor` | open / closed | Contact Sensor `0x0015` |
| `OccupancySensor` | occupied, how it senses, hold time | Occupancy Sensor `0x0107` |
| `TemperatureSensor` | temperature | Temperature Sensor `0x0302` |
| `HumiditySensor` | relative humidity | Humidity Sensor `0x0307` |
| `LightSensor` | illuminance | Light Sensor `0x0106` |
| `AirQualitySensor` | air-quality level; optionally CO₂, PM2.5, VOC index, temperature, humidity | Air Quality Sensor `0x002C` |

The fields follow Matter's device types (research/matter/04 §1). `vocIndex` is the one field Matter has no place for.

**For:** a state or a quantity in a room that rules (12b), the Home UI and Matter controllers read — a door contact, a PIR detector, a probe, an IAQ sensor.

**Not for:**

- Control: a sensor has no `SET` and no method but `identify`.
- DALI-2 occupancy and light sensors, DALI-2 buttons: out of scope (12 §13).
- Water leaks: `WaterLeakDetector`, its own section.
- Pressure, dew point, absolute humidity, the IAQ's "VOC CO₂ equivalent": no type. They stay readable on the source driver.

### 1.1. Behaviour every sensor shares

- **Readings only.** A field changes when its source does; nothing is written.
- **No value is better than a wrong one.** A source that is stale or says its value is invalid — `polled.stale`, xG18's `valid` false, VOC accuracy 0, an AI in a mode the template can't read — makes the template call `markStale(true)`: the device is not `reachable` (12a §4.2), its fields keep their last values.
- **Units** are the human ones: °C, %, lx, ppm, µg/m³, float32. Matter's encodings are 16a's (§4).
- **No state is saved** (12a §3): after a restart a sensor reports what its source reports.
- **`identify`** is unbound on every `local` sensor: none of these sources can show anything.

## 2. Fields

```ts
// @evok-node/driver-home
const Celsius  = Codecs.float32({ min: -273.15, unit: '°C' });
const Percent  = Codecs.float32({ min: 0, max: 100, unit: '%' });
const Modality = Codecs.string({ enumValues: ['pir', 'ultrasonic', 'physicalContact', 'activeInfrared', 'radar', 'rfSensing', 'vision', 'other'] });
const AirQualityLevel = Codecs.string({ enumValues: ['unknown', 'good', 'fair', 'moderate', 'poor', 'veryPoor', 'extremelyPoor'] });

export const ContactSensor = device('home.ContactSensor', {
  ...CommonFields,
  closed: reading(Codecs.bool(), { subscribe: true }),
});

export const OccupancySensor = device('home.OccupancySensor', {
  ...CommonFields,
  occupied: reading(Codecs.bool(), { subscribe: true }),
  sensing:  reading(Codecs.struct({                       // settings a consumer must see (12a §2.3)
              modalities: Codecs.array(Modality, { min: 1 }),
              holdTimeS:  Codecs.optional(Codecs.uint16({ min: 1, unit: 's' })),   // absent ⇒ the detector's own delay only
            }), { subscribe: true }),
});

export const TemperatureSensor = device('home.TemperatureSensor', {
  ...CommonFields,
  temperature: reading(Celsius, { subscribe: true }),
});

export const HumiditySensor = device('home.HumiditySensor', {
  ...CommonFields,
  humidity: reading(Percent, { subscribe: true }),
});

export const LightSensor = device('home.LightSensor', {
  ...CommonFields,
  illuminance: reading(Codecs.float32({ min: 0, unit: 'lx' }), { subscribe: true }),   // 0 = too dark to measure
});

export const AirQualitySensor = device('home.AirQualitySensor', {
  ...CommonFields,
  airQuality:  reading(AirQualityLevel, { subscribe: true }),
  co2:         optional(reading(Codecs.float32({ min: 0, unit: 'ppm' }), { subscribe: true })),
  pm25:        optional(reading(Codecs.float32({ min: 0, unit: 'µg/m³' }), { subscribe: true })),
  vocIndex:    optional(reading(Codecs.uint16({ min: 0, max: 500 }), { subscribe: true })),   // relative, unitless — no Matter counterpart
  temperature: optional(reading(Celsius, { subscribe: true })),
  humidity:    optional(reading(Percent, { subscribe: true })),
});
```

- `closed` is Matter's meaning of the contact: `true` = closed.
- `airQuality` is always present; `unknown` until there is a value to classify.
- An `AirQualitySensor`'s optional fields are bound only when its origin has them — a `matter` endpoint's optional clusters (12a §4.1, `optionalBound`), a template's roles.

## 3. Templates

| DeviceType | Template | Roles |
|---|---|---|
| `ContactSensor` | `contact-from-di` (§3.2) | `input`: `unipi.di`, 1 |
| `OccupancySensor` | `occupancy-from-di` (§3.3) | `input`: `unipi.di`, 1 |
| `LightSensor` | `light-from-sensor` (§3.4) | `input`: `unipi.lux`, 1 |
| `LightSensor` | `light-from-ai` (§3.5) | `input`: `unipi.ai`, 1 |
| `TemperatureSensor` | `temperature-from-sensor` (§3.6) | `probes`: `unipi.temp`, 1–8 |
| `TemperatureSensor` | `temperature-from-ai` (§3.7) | `input`: `unipi.ai`, 1 |
| `HumiditySensor` | `humidity-from-sensor`, `humidity-from-ai` (§3.8) | `input`: `unipi.humidity` / `unipi.ai`, 1 |
| `AirQualitySensor` | `air-quality-from-iaq` (§3.9) | `co2`: `unipi.co2`, 0–1 · `voc`: `unipi.vocIndex`, 0–1 · `vocAccuracy`: `unipi.vocAccuracy`, 0–1 |

`unipi.temp` and `unipi.humidity` are one kind each, whatever reaches them — 1-Wire (10), xG18 or an IAQ (09) — so one template serves all.

Bundle: `iaq-unipi` (§3.10) creates the four devices of a Unipi IAQ sensor at once.

### 3.1. Rules every sensor template follows

- Each source value is converted and emitted at once — only when the result changes.
- `polled.stale` of a source, or a value the template can't read, → `markStale(true)` until it can again (§1.1).
- **A missed pulse.** A `unipi.di` counts rising edges (07a §10.1). When `counter` rose by more than the rising edges seen since its last value, the input was active and back between two polls. The DI templates replay it at once as two values — active, then the value read — so a rule sees a door opened and shut within one poll. The delta is taken modulo 2³² (research/02 §4.9).
- Timing is the poll's: an edge is seen at the next poll, 100 ms onboard, 200 ms on an extension (12c-03 §3).

### 3.2. `contact-from-di`

A door or window contact on a digital input.

| Setting | Default | Note |
|---|---|---|
| `invert` | `false` | `true` when the contact conducts with the door open |

`closed = value XOR invert`. A DI is `true` when the contact conducts (research/matter/04 §8a.3).

### 3.3. `occupancy-from-di`

A PIR or presence detector with a relay or open-collector output on a digital input.

| Setting | Default | Note |
|---|---|---|
| `invert` | `false` | `true` for an NC output |
| `modality` | `pir` | how the detector senses; `sensing.modalities` = `[modality]` |
| `holdTimeS` | absent | the detector's own delay only |

`active = value XOR invert`.

| Input | `occupied` |
|---|---|
| `holdTimeS` absent | follows `active` |
| `active` true | true; a running hold timer is cancelled |
| `active` → false | stays true; the hold timer starts for `holdTimeS` |
| hold timer fires | false |
| a missed pulse (§3.1) | true; the hold timer (re)starts — without `holdTimeS`, true then false |

The hold timer runs on the `Clock` (04 §4), measured from `readAt`. A detector usually has its own delay; `holdTimeS` adds to it.

### 3.4. `light-from-sensor`

`illuminance` = the source's lux. No settings. The IAQ's light value is indicative and depends on placement (research/matter/04 §8a.2).

### 3.5. `light-from-ai`

A lux transmitter on an analog input — linear.

| Setting | Default | Note |
|---|---|---|
| `in` | `{ min: 0, max: 10 }` | the transmitter's output range, in the AI's unit for its mode (V, mA) |
| `out` | none — required | `{ min, max }` in lx, from the transmitter's datasheet |

```
illuminance = max(0, out.min + (value − in.min) · (out.max − out.min) / (in.max − in.min))
```

The AI must be in `voltage10`, `voltage2_5` or `current20` mode (07a §10.1); any other marks the device stale.

### 3.6. `temperature-from-sensor`

One or more temperature probes — 1-Wire, xG18, IAQ. Several probes are one measurement: a large room, a tank (12a §3).

| Setting | Default |
|---|---|
| `offsetC` | 0 |

- `temperature` = the average of the probes that are fresh, plus `offsetC`.
- A probe that is stale, or whose `valid` is false (xG18, 07a §10.3), is left out of the average. With none left, the device is stale.

### 3.7. `temperature-from-ai`

A Pt1000 on a resistance input, or a transmitter on a voltage or current input.

| Setting | Default | Note |
|---|---|---|
| `element` | `pt1000` | `pt1000` \| `linear` |
| `in`, `out` | — | `linear` only, as §3.5; `out` in °C |
| `offsetC` | 0 | e.g. for the wire's resistance |

- `pt1000`: the AI must be in `resistance3w` or `resistance2w` mode. Ω → °C by IEC 60751 (Callendar–Van Dusen, R₀ = 1000 Ω, A = 3.9083·10⁻³, B = −5.775·10⁻⁷, C = −4.183·10⁻¹² below 0 °C): 803 Ω → −50 °C, 1000 Ω → 0 °C, 1573 Ω → 150 °C. Outside −200…850 °C the device is stale.
- `linear`: as §3.5, the AI in `voltage10`, `voltage2_5` or `current20` mode.
- Any other mode marks the device stale.
- A resistance conversion takes 100–400 ms (research/02 §4.5) — the source's poll, not this template's.

### 3.8. `humidity-from-sensor`, `humidity-from-ai`

- `humidity-from-sensor`: the source's %, clamped to 0–100. A 1W-TH-IB2 measures only 11–89 % (research/matter/04 §8a.1).
- `humidity-from-ai`: linear as §3.5, `out` in %, clamped to 0–100.

### 3.9. `air-quality-from-iaq`

The air-quality level of an IAQ sensor, from its CO₂, its VOC index, or both. At least one of `co2` and `voc` must have a source — otherwise `invalid-sources`.

| Setting | Default | Note |
|---|---|---|
| `co2Max` | `{ good: 800, fair: 1000, moderate: 1400, poor: 2000, veryPoor: 5000 }` | ppm; upper bound of each level, above `veryPoor` ⇒ `extremelyPoor` |
| `vocMax` | `{ good: 50, fair: 100, moderate: 150, poor: 200, veryPoor: 350 }` | VOC index; Bosch BSEC's classes on Matter's six levels (research/matter/04 §8a.2) |

- `airQuality` is the worse of the two levels it has.
- `co2` and `vocIndex` are bound when their role has a source, and carry the source's value. `temperature`, `humidity` and `pm25` are never bound here: an IAQ's temperature and humidity are devices of their own (§3.10).
- `vocAccuracy` 0 — the VOC index is invalid, minutes after power-up — marks the device stale.

### 3.10. Bundle `iaq-unipi`

A Unipi IAQ sensor (RW-TH, RLW-TH, RW-THC, RLW-THC) on an extension line, as four devices (12a §3a):

| | |
|---|---|
| Anchor | `unipi.unitType`, 1 — the unit's `<unit>.type` (09 §3a). Taken only when its `vendor` is `unipi` and its `device` names an IAQ definition; otherwise `invalid-anchor` |
| Settings | none |

`resolve` finds each source under the anchor's unit prefix by kind (`ctx.find({ prefix: 'EXT:7.', kind })`):

| Member | Template | Sources |
|---|---|---|
| `temperature` | `temperature-from-sensor` | `probes`: the `unipi.temp` |
| `humidity` | `humidity-from-sensor` | `input`: the `unipi.humidity` |
| `light` | `light-from-sensor` | `input`: the `unipi.lux` |
| `airQuality` | `air-quality-from-iaq` | `co2`: the `unipi.co2` — absent on a TH unit · `voc`: the `unipi.vocIndex` · `vocAccuracy`: the `unipi.vocAccuracy` |

```json
CALL home:manage.createBundle { "bundleKind": "iaq-unipi", "name": "Living room", "anchor": "EXT:7.type" }
→ devices "Living room – Temperature", "– Humidity", "– Light", "– Air quality"
```

## 4. Matter

Part of the mapping table (16a, `driver-home/matter-map`). Encodings per research/matter/04 §2.

| DeviceType | Matter | Home |
|---|---|---|
| `ContactSensor` | Boolean State `StateValue` | `closed` |
| `OccupancySensor` | Occupancy Sensing `Occupancy` bit 0 | `occupied` |
| | FeatureMap | one bit per `sensing.modalities` entry |
| | `OccupancySensorType`, `…Bitmap` (legacy, mandatory) | `pir` → PIR; `ultrasonic` → Ultrasonic; both → PIRAndUltrasonic; anything else → PhysicalContact |
| | `HoldTime`, `HoldTimeLimits` | present only with `sensing.holdTimeS`: `HoldTime` = it, limits min = max = default = it. Writes refused — `manage` only (12a §2.3) |
| `TemperatureSensor` | Temperature Measurement `MeasuredValue` | `round(temperature × 100)`, clamped to −27315…32767 |
| `HumiditySensor` | Relative Humidity `MeasuredValue` | `round(humidity × 100)` |
| `LightSensor` | Illuminance `MeasuredValue` | `illuminance < 1` → 0; else `round(10000 · log10(illuminance) + 1)`, clamped to 1…0xFFFE |
| `AirQualitySensor` | Air Quality `AirQuality` | `airQuality`, value for value |
| | FeatureMap | `FAIR`, `MOD`, `VPOOR`, `XPOOR` always |
| | CO₂ Concentration (`MEA`, `PPM`, medium `Air`) | `co2` |
| | PM2.5 Concentration (`MEA`, `UGM3`, medium `Air`) | `pm25` |
| | Temperature, Relative Humidity | `temperature`, `humidity` — as their own types above |
| | — | `vocIndex`: ignored |

- Every `Min`/`MaxMeasuredValue` is null — "not defined", which Matter allows. `Tolerance` is absent.
- A measurement cluster is present only when its field is bound.
- Apple Home doesn't show temperature or humidity on an Air Quality Sensor endpoint (research/matter/04 §6); 16a puts them on child endpoints (16a).

**`matter` origin** (12a §4a), the other direction:

- An endpoint's device type picks the home type; its optional clusters pick the optional fields.
- Illuminance: 0 → 0; `v` → `10^((v − 1) / 10000)`.
- Occupancy FeatureMap → `modalities`; the device's `HoldTime` → `holdTimeS`, read-only here.
- Concentrations: a `MEA` value in another unit is converted (ppb → ppm, mg/m³ → µg/m³); a level-only (`LEV`) cluster is ignored.
- `null` from a measurement cluster makes the device not `reachable` (12a §4.2).

**Open:** an attribute a Matter controller may write — `HoldTime` here, a light's `behavior` (12c-01 §4) — should be writable through the device; only a setting with no Matter counterpart stays a template setting. Today every one is a template setting, changed through `manage`. Deferred to M3.13: the write path from 16a through the device is the bridge's design.

## 5. Moving and target

Nothing moves, and nothing is written. Every field is reported as its source reports it; `occupied` stays true for `holdTimeS` after the detector goes quiet (§3.3).
