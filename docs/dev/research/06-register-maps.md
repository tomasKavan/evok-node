# Register maps — the local corpus, and what it closed

The official Unipi Modbus maps are now in the repo at **`docs/modbus-reg-map/`**. This
document records what's there, the facts it verified, and the two places where it
**corrects** earlier notes.

## 1. Corpus inventory

| Path | Format | Coverage |
|---|---|---|
| `neuron/Neuron_<model>/` | CSV | 14 models: S103, M103, M203, M303, M403, M503, M523, L203, L303, L403, L503, L513, L523, L533 |
| `patron/Patron_<model>/` | CSV | 10 models: S107, S117, S167, S207, M207, M267, M527, M567, L207, L527 |
| `axon/Axon_<model>/` | CSV | 18 models (discontinued family, useful for cross-checking) |
| `extensions/Extension_xS11`, `Extension_xS51`, `Neuron_xS10/xS30/xS40/xS50` | CSV | current + discontinued extensions |
| `extensions/unipi-extension-{xg18,xs52,xs53,xs54}-modbus-map.pdf` | PDF | xG18, xS52–54 |
| `edge/unipi-edge-e41{0,1,2,3}-modbus-map.xlsx` | XLSX | all four Edge models |
| `1_1/unipi-{11,lite}-modbus-map.xlsx` | XLSX | Unipi 1.1 and 1.1 Lite |

**CSV schema** (both Registers and Coils):

```
Via Unit 0, Via Unit <N>, Register Count, R/W, Data Type, Content, Start Bit Nr., Category
```

- `Via Unit <N>` = address when addressing the section directly at unit-id N.
- `Via Unit 0` = address when addressing everything through unit-id 0.
- `Category` ∈ `Basic | Advanced | Expert | Reserved | Obsolete`. **`Obsolete` is a real
  category and appears on live registers** (e.g. `Analog Output (raw value)`, `Length of
  RS485 TX Queue`) — don't expose those.
- Bit-mapped registers repeat the address once per bit with `Start Bit Nr.` filled in.

Each model directory contains both `-section-N` and `-group-N` files. **They are
byte-identical except that "Section MasterWatchDog" is spelled "Group MasterWatchDog"** —
pure terminology, no data difference. Pick one naming and ignore the other.

XLSX files carry an extra **`Description` sheet** with the mode enumerations and factory
defaults that the CSV exports drop. That's why Edge and Unipi 1.1 are better documented
than the CSV-only families.

A derived per-model I/O census is generated at
**`docs/research/derived/model-io-census.csv`** (83 model×section rows, columns
`family, model, section, DI, DO, RO, AI, AO, LED`). Use it to validate hardware definitions
at load time and to generate per-model address tests.

## 2. Gaps now closed `[V]`

### 2.1 Unit-0 aggregate addressing — exact formula

From the Edge map's Description sheet, verbatim:

> Access to all coils/registers via Unit ID 0 is possible by using formula
> **`address + ((Unit ID - 1) * 100)`**

Confirmed independently by the CSV `Via Unit 0` column on every multi-section model
(section 2 → +100, section 3 → +200). This is the "section 0 addresses all sections at
once" behaviour the KB alluded to but never quantified.

Consequence worth designing around: **a single Modbus read at unit 0 can span multiple
sections**, because section 2's registers start at 100 and section 3's at 200. That is a
real optimisation for a whole-unit scan — one request instead of three — at the cost of
losing per-section fault isolation. EVOK never uses it (autogen always emits one device per
section). Treat it as an optional scan strategy, off by default.

Some registers have an **empty `Via Unit 0`** and are only reachable per-section:
`RS485 TERMIOS *`, `RS485 ModBus Timeout`, `(Internal) RS485 Full Mode Configuration`, all
`(Internal) Stored *` registers, and `Reserved`. Any unit-0 scan strategy must exclude them.

### 2.2 The identification block is identical on PLC boards

Previously `[I]`, now `[V]` — holding registers 1000–1009 on Neuron/Patron/Axon/Edge
sections match the Extension layout exactly:

| Reg | Content |
|---|---|
| 1000 | Firmware Version |
| 1001 | Number of I/Os (bit-packed) |
| 1002 | Number of peripherals (bit-packed) |
| 1003 | Firmware ID |
| 1004 | Hardware ID |
| 1005–1006 | PCB Serial Number (uint32) |
| 1007 | Interrupt Mask (PLC) / Reserved (Edge) |
| 1008 | Section/Group MWD Timeout, ms |
| 1009 | VRef of MCU |

So the startup cross-check proposed in `03-config-and-hw-definitions.md` §"Definition-load
validation" works on **every** family: read 1001/1002, compare against the census, refuse to
run on mismatch.

### 2.3 ⚠ Correction — register 1002 bit layout was reversed

`02-hardware-model.md` §3.3 and the raw hardware appendix state 1002 as
*"bits 0–3 = AOs, 4–7 = AIs, 8–15 = internal RS485 lines"*. The Edge map spells the fields
out explicitly and it is **the other way round**:

| Reg | bits 0–3 | bits 4–7 | bits 8–15 |
|---|---|---|---|
| **1001** | \multicolumn — bits 0–7 = **number of DIs** | | bits 8–15 = **number of DOs** |
| **1002** | **number of internal RS485 lines** | **number of AOs** | **number of AIs** |

The earlier reading came from text-extracted PDF tables whose column order had been
scrambled. Use the table above; `02-hardware-model.md` has been corrected.

### 2.4 Storage-life registers

Previously `[GAP]`, now `[V]` — a unit-0 band:

| Reg | Content |
|---|---|
| 4000 | Storage — erase cycles used [%] |
| 4001 | Storage — good blocks [%] |
| 4002 | Storage — power cycles |
| 4003–4005 | Storage — vendor specific 1–3 |

Edge adds a connection band: **4200** mode, **4201** network type, **4202** RSSI [dBm],
**4203** signal quality.

Edge also puts **User Programmable LEDs on unit 0**: register **3998** (bitmap, bits 0–2)
and coils **3000–3002** — unlike the PLC families where ULED is a per-section register. A
hardware definition for Edge therefore needs a unit-0 device alongside the unit-1 one.

### 2.5 There is no `ForceOutput` register

Searched every CSV and XLSX in the corpus: the string does not exist. What does exist,
consistently, is a pair per output:

- `Synchronised DO/RO <n>` (register bitmap + per-bit)
- `Synchronised DO/RO Lock <n>`

`[V]` that no register named ForceOutput exists; `[I]` — now strongly supported by
elimination — that the Sync/Lock pair is the mechanism the KB's DirectSwitch warning refers
to. Still needs one confirmation on live hardware before we document it as the way to write
a DirectSwitch-claimed output.

### 2.6 The two AI abstractions, verified on PLC maps

Previously verified only from sysfs; now visible in the maps:

- Section 1: `Analog Input Configuration(U/I) 1.1` at register **1024** — two modes.
- Sections 2/3: `Analog Input Configuration(U/I/R) 2.1…` at registers **1019–1022** — six
  modes.

And AO likewise: `Analog Output Configuration(U/I/R-measure)` on section 1 vs plain
`Analog Output value` on sections 2/3. AO values are `0..4000 ~ 0..10 V` raw counts, `int16`.

### 2.7 Edge AI modes differ from the PLC families

From the Edge Description sheet — note **4–20 mA, not 0–20**, and **90–2000 Ω**:

| Value | Mode | Available on |
|---|---|---|
| 0 | OFF | all |
| 1 | Voltage 0–10 V | AI1, AI2, AI3 |
| 2 | Voltage 0–2.5 V | AI2, AI3 |
| 3 | Current **4–20 mA** | AI2, AI3 |
| 4 | Resistance **90–2000 Ω** | AI4, AI5 only |

So the mode enum is **per model and per channel**. Confirms the design rule: modes come from
the hardware definition, and a definition needs per-channel mode sets, not one set per
feature block. EVOK's format only supports the latter — an extension we'll need.

### 2.8 Factory defaults, from the XLSX Description sheets

| | Edge | Unipi 1.1 |
|---|---|---|
| DI counter | 0 | 0 |
| DI debounce | 50 (= 5 ms) | **0 (= 0 ms)** |
| DirectSwitch | 0 (off) | n/a |
| AI state / config | 0 (off) | 0 (off), resolution **18 bits** |
| DO/RO state | 0 (off) | 0 (off) |
| MWD timeout / enable | 2500 ms / off | n/a |

Unipi 1.1's sheet carries an important note: **"configuration is not permanently saved, set
on each power-on"** — there is no save-config coil, so evok-node must re-apply debounce, AI
config and similar on every start for that family.

Bit numbering everywhere is **`0 = LSB, 15 = MSB`**.

### 2.9 Modbus-address register floats on PLCs too

`Modbus Address Configuration (1-254)` appears at **1024, 1028, 1032 and 1035** depending on
the model. The rule from the Extensions ("no fixed offset for the RS485/address registers")
holds across the whole product line. Never hard-code it.

## 3. The >16-channel bug, now fully explained `[V]`

Neuron M403 section 2 has exactly **28 relay outputs** (confirmed in the census). The map:

| | Via Unit 2 | Via Unit 0 |
|---|---|---|
| RO 2.1 … 2.16 | register **0**, bits 0–15 · coils **0–15** | register 100 · coils 100–115 |
| RO 2.17 … 2.28 | register **1**, bits 0–11 · coils **16–27** | register 101 · coils 116–127 |

So the hardware layout is exactly `register = base + floor(i/16)`, `bit = i % 16`,
`coil = base + i`.

The field report on issue #209 — *"circuits `_01…_12` were silently driving coils 116–127,
i.e. relays 17–28"* — is now precisely diagnosed. Unipi's definition for that board must
declare **two** `RO` feature blocks (one `count: 16` at `val_reg 0 / val_coil 0`, one
`count: 12` at `val_reg 1 / val_coil 16`). `parse_feature_ro` names circuits from
`counter + 1` **and ignores `start_index`** — which `parse_feature_di` does honour — so the
second block re-registers circuits `_01…_12` pointing at coils 16–27 (= 116–127 via unit 0),
silently overwriting the first block's entries in the registry.

Two independent defects, both needing fixing:

1. `RO` / `DO` / `LED` parsers ignore `start_index` (only `DI` honours it).
2. Within a single block of more than 16 channels, `val_reg` is never advanced by
   `floor(i/16)` even though the mask correctly wraps with `% 16`.

This is exactly why R04-1 (one audited address function) and
R04-2 (assert global uniqueness of circuit ids and of coil mappings at startup) are the top
two rules. A duplicate-circuit registration must be a **fatal startup error**, not a silent
overwrite.

## 4. Still open after the maps

1. **RS485 `Configuration` register encoding** (baud + parity bits). The legend lives in the
   XLSX Description sheets, and the PLC/Extension maps are CSV/PDF-only. The reconstructed
   Extension table (`11=2400 … 14=19200 … 4098=115200`) remains `[I]` with only `14 = 19200`
   verified. Resolve by reading the register on a live device.
2. **`ForceOutput` / DirectSwitch write path** — Sync + Lock is the only candidate; needs one
   hardware confirmation (§2.5).
3. **`Interrupt Mask` (register 1007)** — named on PLC maps, semantics undocumented. Possibly
   the basis for interrupt-driven rather than polled reads, which would matter for the
   latency question in `05-evok-node-design-notes.md` §5. Worth investigating.
4. **`(Internal) RS485 Full Mode Configuration`** (register 100, DWord, per-section only) and
   the `RS485 TERMIOS *` band (500–503) — how the internal serial lines are configured
   through Modbus. Relevant if we want to configure extension buses programmatically.
5. **Firmware-version floor per model** — the maps are versioned `v1.0` with no statement of
   which firmware they describe. FW 5.x boards may not match.
