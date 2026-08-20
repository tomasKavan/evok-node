# IAQ — derived CSVs, and what is inferred rather than sourced

Transcribed 2026-08-13 from
[`modbus-reg-map/accessories/Accessory-IAQ.pdf`](../../modbus-reg-map/accessories/Accessory-IAQ.pdf)
§6.6 (doc pages 11–12; PDF pages 12–13). The CSVs this describes are in
[`accessories/Accessory_IAQ/`](../../modbus-reg-map/accessories/Accessory_IAQ/). The PDF's
text layer contains **none** of this — the tables are rendered, so the source was read visually, page by
page. Verify against the PDF before these are used to generate a definition.

Covers `RLW-THC` / `RW-THC` / `RLW-TH` / `RW-TH`. Per §6.6 the register map "is shared between TCP and
RTU", and the sensor is a Modbus slave supporting one open TCP connection at a time, port 502 by default.

## Deviations from the corpus CSV schema

| | why |
|---|---|
| Two register files, `-InputRegisters` and `-Registers` | The source separates **input** registers (§6.6.1, the measurements) from **configuration/holding** registers (§6.6.2). Every other model in the corpus documents one space, so there was no existing convention. `-Registers` is holding, matching the rest of the corpus |
| Header says `Via Unit N`, not `Via Unit 1` | A standalone sensor has no section layout and its unit id is configured by the operator, so there is no unit-0 aggregate space. Both columns carry the same local address, as they do for the single-group xS11 |
| No Coils file | The source documents none. The digital output is holding register 5001, not a coil |

## Inferred, not stated in the source

- **`Category`** — the source has no such column. Everything documented in §6.6 is user-facing, so all
  rows are `Basic`.
- **`R/W`** — input registers are read-only by definition. 5000 and 5001 are marked `RW` because they are
  configuration values the document describes setting; the table itself does not state direction.
- **`Data Type`** — the source says "float (32 bits)" and "integer (16 bits)"; written as the corpus's
  own `Real` and `Word`.

## Gaps in the address space are deliberate

The source table has visually blank rows between entries. Those are **undefined registers**, not missing
transcription: §6.6 states that "any values outside the registers have a non-defined state (eg. the
control system should discard them)". Only defined registers appear in the CSVs. The gaps are 2–5, 12–17,
20–25, 30–33, 36–41, 44–75 and 78–83.

## Still owed

- **Which quantities exist on which variant.** `TH` has no CO2 sensor, and §4 notes some values are
  "indicative and depend on the sensor variant", but §6.6's table is not annotated per variant. So the
  `IAQ-TH` versus `IAQ-THC` split cannot be derived from this document — it has to come from EVOK's two
  shipped definitions or from measurement.
- **Whether unset quantities read as a defined value or as garbage.** The HTTP JSON API returns
  `"CO2": null` on a variant without the sensor (§6.4 example); the Modbus map says nothing about the
  equivalent, and `float32` has no null. Relevant to whether our reading needs a validity flag.
