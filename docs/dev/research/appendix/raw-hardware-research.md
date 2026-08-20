# Unipi Technology Hardware Model — Reference for an EVOK 3.x-compatible Node/TS Implementation

**Scope note on evidence.** Everything below is marked either **[V]** = verified from a source I read (URL cited), or **[I]** = inferred/reconstructed by me, or **[GAP]** = the KB is vague / the data is in an image or binary file I could not read. Several key tables on the KB (Neuron model overview, Patron model overview, Extension model overview, Edge part-number decoder) are **PNG images**, and all PLC Modbus register maps are **XLSX** — `web_fetch` returns those as binary. Only the Extension register maps exist as PDF, and those I read in full.

---

## 1. Product families and models

### 1.1 Family overview and platform identity **[V]**

| Family | KB page | Compute module | Sections/"groups" | Notes |
|---|---|---|---|---|
| **Unipi Edge** (E4xx) | `en:hw:004-edge` | Unipi compute module (i.MX-class; ext-temp variant limited to 16 GB eMMC / ≤4 GB RAM) | not described as sections | Newest line; TPM 2.0, NVRAM "Retain", RTC, HW watchdog, INIT USB-C port |
| **Unipi Patron** (S/M/L…7) | `en:hw:007-patron` | Unipi module, **NXP i.MX 8M Mini**, 4× Cortex-A53 max 1.8 GHz, 1 GB RAM, 8 GB eMMC | **1–3 sections**, each with its own **STM32** | 4-year warranty; replaces Axon |
| **Unipi Neuron** (S/M/L…3) | `en:hw:02-neuron` | **Raspberry Pi 3B/3B+ or 4B** (2/4/8 GB), microSD | **1–3 sections**, each with own **STM32** | FID label decodes the RPi: FID 2.x=RPi3B, 3.x=RPi3B+, 4.2/4.4/4.8=RPi4 2/4/8 GB. HDMI intentionally sealed |
| **Unipi Axon** (S/M/L…5) | `en:hw:01-axon` | Allwinner H5 quad-core 1.2 GHz, 1 GB RAM, 8 GB eMMC | **1–3 I/O groups**, each with own **STM32** | **Discontinued**, no further SW updates (`en:hw:01-axon:downloads`) |
| **Unipi Gate** (G1xx) | `en:hw:025-gate` | quad-core ARM A53 600 MHz, 0.5–1 GB RAM, 16/32 GB eMMC | none (no I/O) | Ethernet/RS485 gateway; **no local I/O** |
| **Unipi 1.1 / 1.1 Lite** | `en:hw:03-unipi11` | Raspberry Pi 2B/3B/3B+/4B via GPIO ribbon | none | I/O reached via **GPIO + I²C**, not Modbus/SPI coprocessor |
| **Unipi Extension** (xS/xG) | `en:hw:04-extensions` | STM32 only | n/a | External **RS-485 / Modbus RTU** modules |
| **Unipi sensors** (IAQ RW/RLW) | `en:hw:05-sensors:iaq` | — | n/a | RS485 Modbus RTU/TCP + Wi-Fi (+LoRaWAN on RLW) |

Sizes are common to Neuron/Axon/Patron **[V]** (`en:hw:007-patron`, `en:hw:02-neuron`):
- **S**: max 10 I/O, 70×90×60 mm (4 DIN modules), **1 section**
- **M**: max 40 I/O, 140×90×60 mm (8 DIN), **2 sections**
- **L**: max 70 I/O, 210×90×60 mm (12 DIN), **3 sections**
- **Section 0** is special: "through which in some cases all three sections can be accessed simultaneously" **[V]**.

### 1.2 Model lists

**Patron** — from the Downloads page (`en:hw:007-patron:downloads`) **[V]**:

| Size | Models |
|---|---|
| S | S107, S117, **S167-LTE** (FID 1.x and FID 2.0 variants), S207 |
| M | M207, **M267-LTE** (FID 1.x / 2.0), M527, **M567-LTE** (FID 1.x / 2.0) |
| L | L207, L527 |

Patron serial-line map (`en:hw:007-patron:portmap`) **[V]** — this is the most concrete per-model I/O evidence I could read:

| Model | RS485-1 / 1.1 | RS232(485)-2 / 1.2 | RS485-3 / 1.3 | RS485-4 / 2.1 |
|---|---|---|---|---|
| S107 | ttyNS0 | ttymxc1 | ttymxc0 | – |
| S117 | ttyNS0 | ttymxc2 | ttymxc1 | ttymxc0 |
| S167 LTE | ttyNS0 | ttymxc0 | – | – |
| S207 | ttymxc0 | – | – | – |
| M207 | ttyNS0 | ttymxc1 | ttymxc0 | – |
| M267 LTE | ttyNS0 | ttymxc0 | – | – |
| M527 | ttyNS0 | ttymxc1 | ttymxc0 | ttyNS1 |
| M567 LTE | ttyNS0 | ttymxc0 | – | ttyNS1 |
| L207 | ttyNS0 | ttymxc1 | ttymxc0 | – |
| L527 | ttyNS0 | ttymxc1 | ttymxc0 | ttyNS1 |

Note **S207 has no 1-Wire** (`en:sw:02-apis:04-sysfs`: "This file does not work on units without 1-Wire, Unipi 1.1 and Patron S207") **[V]**. LTE is on **S167, M267, M567** **[V]**.

**Neuron** — from `en:hw:02-neuron:downloads` + `en:hw:02-neuron:portmap` **[V]**:

| Size | Models | RS485 lines (from portmap) |
|---|---|---|
| S | S103, **S103-G** (GSM/GPRS, modem on `ttyAMA0`) | 1 (ttyNS0) |
| M | M103, M203, M303, M403, M503, M523 | 1 for M103–M403; **2** for M503/M523 (ttyNS0, ttyNS1) |
| L | L203, L303, L403, L503, L513, L523, L533 | 1 for L203–L403; 2 for L503/L523; **3** for L513/L533 (ttyNS0/1/2) |

Neuron family maxima **[V]**: up to 64 DI, 4 DO, 56 RO, 9 AI, 9 AO, 3 RS485, 1× 1-Wire, up to 4 USB.

**Axon** (discontinued) — from `en:hw:01-axon:downloads` **[V]**:

| Size | Models |
|---|---|
| S | S105, S115, S155, S205, S215, S505, S515 |
| M | M205, **M265-LTE**, M505, M515, M525, M535, **M565-LTE** |
| L | L205, L505, L525 |

Axon family maxima **[V]** (`en:hw:01-axon`): up to 36 DI, 4 DO, 28 RO, 8 AI, 8 AO, 4 RS485, RS232, 1× 1-Wire, **4× IEC 62386 (DALI-compatible) channels**, up to 2 Ethernet ports.

**Edge** — full model table is text on the KB **[V]** (`en:hw:004-edge`):

| Model | DI | DO | AI | RS-485 | USB | ETH | Wi-Fi | LTE | GNSS | RETAIN | TPM | RTC | µHDMI |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| E410 | 4 | 2 | 5 | 2 | 2 | 2 | opt | opt | opt | 128 kB | ✔ | ✔ | ✔ |
| E411 | 0 | 0 | 0 | 1 | 0 | 1 | opt | ✘ | ✘ | 128 kB | ✔ | ✔ | ✘ |
| E412 | 4 | 2 | 0 | 2 | 0 | 1 | opt | opt | opt | 128 kB | ✔ | ✔ | ✘ |
| E413 | 0 | 0 | 0 | 2 | 2 | 2 | opt | opt | opt | 128 kB | ✔ | ✔ | ✔ |

Edge AI mode-per-input mapping **[V]** (`en:hw:004-edge:11-technical-parameters`): 0–10 V on AI1/AI2/AI3; 0–2.5 V on AI2/AI3; 4–20 mA on AI2/AI3; 90–2000 Ω on **AI4/AI5** only. Edge DO are **solid-state MOSFET relays**, 48 V/500 mA, PWM up to 16-bit, recommended ≤200 Hz. Edge RS-485 port map: `rs485.1/tty`, `rs485.2/tty` under `/run/unipi-plc/by-sys/`, i.e. `/dev/ttyAMA1`, `/dev/ttyAMA2` **[V]**.

**Gate** **[V]** (`en:hw:025-gate`): **G100** = 1× RS485 + 2× ETH; **G110** = 2× RS485 + 2× ETH. Both 35×94×70 mm. FID table maps 1.0/1.1/1.2/2.0 to RAM/eMMC combos. Per `en:sw:02-apis`, on Gate EVOK is usable **only to talk to Extension modules**, and Modbus TCP/sysfs expose **only storage-life status**.

**Unipi 1.1 / Lite** **[V]** (`en:hw:03-unipi11`):
- **1.1**: 8× Finder 36.11 changeover relays, 12× isolated DI, 2× 0–10 V AI, 1× 0–10 V AO, 1× 1-Wire, 1× I²C (for EMO-R8 relay extension), 1× UART, RTC battery socket. RO rated 10 A @230 V~ / 30 V⎓.
- **1.1 Lite**: 6× Omron G5Q changeover relays, 6× isolated DI, 1× 1-Wire, short-circuit LED. No AI/AO.
- I/O attach to the Pi "either directly via GPIO or indirectly via I²C".

**Extensions** — current vs discontinued, from `en:hw:04-extensions:downloads` **[V]**. I/O counts below are derived from the register maps I read in full (PDF) **[V for xS11/51/52/53/54/xG18]**; the summary image table on `en:hw:04-extensions` is a PNG **[GAP]**:

| Model | Status | DI | RO | AI | AO | ULED | AI modes |
|---|---|---|---|---|---|---|---|
| xS11 | current | 12 | 13 | – | – | 3 | – |
| xS51 | current | 4 | 5 | 4 | 4 (0–10 V, 0..4000 counts) | 3 | OFF / 0–10 V / 0–2.5 V / 0–20 mA / 0–1960 Ω / 0–100 kΩ |
| xS52 | current | 4 | 5 | 8 | – | 3 | OFF / 75–2000 Ω / 1–20 kΩ |
| xS53 | current | 4 | 5 | 8 | – | 3 | OFF / 0–10 V / 0–2 V / 0–20 mA |
| xS54 | current | 4 | 5 | 8 | – | 3 | OFF / 0–10 V / 0–2 V / 0–20 mA / 75–2000 Ω / 1–20 kΩ |
| xG18 | current | – | – | 8× 1-Wire temp channels (int16, ×0.01 °C) | – | – | n/a (per-channel measuring interval in seconds) |
| xS10, xS30, xS40, xS50 | **no longer available** | — | — | — | — | — | maps only as XLSX **[GAP]** |

xS AI values are read as **float32/real** in physical units (V, mA, Ω) starting at holding reg 2 (xS52/53/54) or 6 (xS51) **[V]**. AO on xS51 is **raw 0..4000 ≙ 0..10 V** at holding regs 2–5 **[V]** — note the asymmetry: AI in engineering units, AO in raw counts.

Warning worth carrying into the API layer **[V]** (`en:hw:04-extensions:technical-parameters`): on xS5* modules **only ELV may be connected to RO 1**.

### 1.3 Model-code / naming scheme

**[V]** for Edge: `en:hw:004-edge#part_number_description` gives a decoder **image** plus two worked examples:
- `E4130SX20830` = model E413, 2 GB RAM, 8 GB eMMC, LTE CAT 1 with GNSS, standard-temp compute module
- `E4110SW83200` = model E411, 8 GB RAM, 32 GB eMMC, Wi-Fi, standard-temp compute module
- `unipiid product_model_full` returns e.g. `E4130SW43200-M1` — so `product_model_full` is the **full part number**, `product_model` is just `E413`.
The exact field boundaries are only in the PNG **[GAP]** — do not hard-code a parser from my guesses.

**[I]** for Neuron/Axon/Patron, the pattern is `<Size><CC><F>`:
- `Size` ∈ {S, M, L} ⇒ 1/2/3 sections
- `CC` = 2-digit I/O configuration code, shared across families (S103/S105/S107 are the same config on three generations; M523/M525/M527; L203/L205/L207; `x6x` = LTE/GSM variants: S167, M267, M567, M265, M565, S103-G)
- `F` = family digit: **3 = Neuron, 5 = Axon, 7 = Patron**
This is a strong pattern across all three model lists and it lines up with the verified `platform_family` numbers (Patron = 7, Edge = 6, see §3), but **the KB never states the rule**. Treat as a heuristic, not a parsing contract. Edge (`E4xx`) and Gate (`G1xx`) do not follow it.

---

## 2. Internal architecture: CPU ↔ I/O boards

### 2.1 The section/coprocessor model **[V]**
- Neuron, Axon and Patron: "**Each I/O circuit board is controlled by its STM32 processor**, which controls inputs and outputs and communicates with the central processing unit (CPU). Processors are using custom firmware containing not only basic I/O functions but also additional functions and features." (`en:hw:02-neuron`, `en:hw:007-patron`, `en:hw:01-axon`)
- The section number is explicitly a **software addressing concept**: "The section numbers is important for the software, especially for addressing input and output boards." **Section 0** can address all three at once in some cases (`en:hw:02-neuron`, `en:hw:007-patron`).
- Sections are independent failure domains: each section has its **own MWD**, its own **NVRAM default config**, its own **reboot** control (`en:sw:02-apis:04-sysfs`, `en:automation:mwd-hidden`).

### 2.2 Physical bus to the coprocessors
- **SPI** for internal I/O boards **[V]**: the firmware tool for internal boards is `fwspi`, and `unipi-tools` README states plainly: "*fwspi – firmware update utility to flash internal modules via SPI*", "*fwserial – ... Unipi Extensions connected via RS-485*", "*fwi2c – firmware update utility to flash internal modules through I2C*", "*libunipichannel.so – library to directly talk to I/O via kernel modules*" — for "Neuron, Axon, Patron, Iris" (https://github.com/UniPiTechnology/unipi-tools).
- KB confirms `fwspi -u <n>` where "the parameter *-u* specifies the board Modbus address – board section" **[V]** (`en:sw:04-unipi-firmware:05-update-firmware`). So **the section number is literally the Modbus unit-id of the coprocessor**, carried over SPI, not RS-485.
- **[GAP]** The KB pages I read never say "SPI" in prose for the internal link; the Edge block diagram that would show it is a PNG. The SPI claim rests on `unipi-tools` README + `fwspi` naming.
- **[I]** Legacy background from search results: the old `neuron-tcp-modbus-overlay` was replaced by the Unipi kernel module, which exposes `/dev/unipispi`; the TCP Modbus server "can handle low-level communication on SPI with all embedded Neuron CPIs". Sources: https://github.com/UniPiTechnology/neuron-tcp-modbus-overlay , https://github.com/UniPiTechnology/unipi-tools

### 2.3 How software actually reaches the boards — the numbers you need **[V]**

| Path | Transport | Device / endpoint | Unit-id | Source |
|---|---|---|---|---|
| Unipi PLCs (Edge/Patron/Neuron/Axon), Debian 13 | Modbus **TCP** via `unipitcp` service | `127.0.0.1:502` (loopback-only by default; `-l 0.0.0.0`, `-p <port>` to change; persist in `/etc/default/unipitcp`) | **1, 2, 3 = section number** | `en:sw:02-apis:02-modbus-tcp`, `evok_configuration` autogen example |
| Same, Debian 12 | binary at `/opt/unipi/tools/unipitcp` | 502 | " | `en:sw:02-apis:02-modbus-tcp` |
| Older images | service named **`unipi_tcp_server`** (`/opt/unipi/tools/unipi_tcp_server`) | 502 | " | " |
| **Unipi 1.1 / Lite** | `unipi-one-modbus` service | loopback **port 50200**; config `/etc/unipi-one-modbus.d/1-modbus.yaml` (change `127.0.0.1`→`0.0.0.0`) | not documented **[GAP]** | `en:sw:02-apis:02-modbus-tcp` |
| Extensions | Modbus **RTU** on RS-485 | `/run/unipi-plc/by-sys/rs485-N/tty` (or `/dev/ttyNS0`, `ttymxc*`, `ttyAMA*`) | DIP/SW-configured, default **15** | `en:hw:04-extensions:*`, `en:sw:04-unipi-firmware:05-update-firmware` |
| Kernel/sysfs | `unipi` kernel module | `/run/unipi-plc/by-sys/...` | — | `en:sw:02-apis:04-sysfs` |

**EVOK's actual view is Modbus TCP to localhost:502** — the auto-generated config is literally:

```yaml
comm_channels:
  LOCAL_TCP:
    type: MODBUSTCP
    hostname: 127.0.0.1
    port: 502
    device_info: { family: Neuron, model: L533, sn: 0, board_count: 3 }
    devices:
      1: { slave-id: 1, model: "00" }
      2: { slave-id: 2, model: "13" }
      3: { slave-id: 3, model: "13" }
  OWFS: { type: OWBUS, interval: 10, scan_interval: 60, owpower: 1 }
```
(https://evok.readthedocs.io/en/latest/configs/evok_configuration/) **[V]**

So for a drop-in replacement: **EVOK never speaks SPI**. It is a Modbus client only (TCP to `unipitcp`, RTU to extensions) — confirmed by the EVOK docs: "Evok is a translation layer between its provided APIs and Modbus, which Unipi PLCs use" (https://evok.readthedocs.io/en/latest/). Notably **1-Wire is not on Modbus at all** and must be done via OWFS/owserver (`en:sw:02-apis:02-modbus-tcp` explicit warning) **[V]**.

Deprecation to be aware of **[V]**: `/dev/extcomm/Y/X` (section/port indexed serial aliases) is **deprecated and removed on Debian 13** (`en:hw:007-patron:portmap`, `en:hw:02-neuron:portmap`).

---

## 3. Device identification / self-description

### 3.1 `unipiid` — the authoritative host-side identity API **[V]** (`en:sw:02-apis:05-unipiid`)

Requires root; **Debian 13+ only**. `unipiid -d` populates `/run/unipi-plc/unipi-id/` with world-readable text files. Available names:

`product_description, product_model, product_model_full, product_version, product_serial, product_code, product_family, product_options, platform_family, platform_id, mainboard_description, mainboard_id, uboard_id, api_version, fingerprint`

Real examples:
```
$ unipiid product_description          $ /run/unipi-plc/unipi-id/product_description
Product model:   E413                  Product model:   S167
Product version: 1.0                   Product version: 1.1
Product serial:  1260244349            Product serial:  00000667
SKU:             2025058               SKU:             2020028
Options:         0x02                  Options:         0x00
Platform family: Edge (6)              Platform family: Patron (7)
Platform series: 0x06                  Platform series: 0xFF
RAW platform ID: 0x0606                RAW platform ID: 0xFF07
```
- **`platform_family`: Edge = 6, Patron = 7** **[V]**. Neuron/Axon/Gate numbers not shown anywhere I read **[GAP]** — but see the model-code inference in §1.3.
- **RAW platform ID = (series << 8) | family** **[I]**, consistent with both samples (0x0606, 0xFF07).
- `product_code` = `#SKU;product_model_full_product_version;product_serial#`, e.g. `#2025058;E4130SW43200-M1_1.0;1260244349#`, and **is the same string as the 2D DataMatrix on the manufacturing label** **[V]**.
- `unipiid api_version` returns `2` (unipiid); the sysfs `unipi-id/api_version` returns `1.1` **[V]** — two different version counters. Both docs say "verifying the API version before any usage is strictly recommended".
- **`fingerprint`** = SHA1-length hash recomputed every boot; changes if the HW configuration changes (e.g. a card inserted into a slot). Ideal cache-invalidation key **[V]**.

### 3.2 EEPROMs **[V]** (`en:sw:02-apis:04-sysfs`, `en:sw:02-apis:05-unipiid`)
- **Mainboard**: "Contains own EEPROM memory storing all information about itself **and the whole unit**".
  - Edge example: `Model: Mainboard / Version: 4C / Serial: 00000548 / ID: 0x00CC / Nvmem: /sys/bus/i2c/devices/1-0057/eeprom`
  - Patron example: `Model: Mainboard / Version: 1.2 / Serial: 00000515 / ID: 0x07D0 / Nvmem: /sys/bus/nvmem/devices/2-00571/nvmem`
  - ⇒ mainboard EEPROM is an **I²C device at 0x57**, bus 1 on Edge, bus 2 on Patron **[I from the paths]**.
- **Upper board**: `unipiid uboard_id` → e.g. `00e0` (only present if the device has one).
- **Cards / slots**: "Some Unipi platforms use a plug-in slot system. Every slot can host one custom-defined type of card. Similarly, as the mainboard, every card contains EEPROM memory." Files `card_description.<xx>` / `card_id.<xx>`, `<xx>` = slot number. Example for slot 12: `Model: IM205 / Version: 1.0 / Serial: 00000080 / ID: 0x0079 / Nvmem: /sys/bus/nvmem/devices/plcid12/nvmem / Slot: 12`.
  - **[I]** This slot/card model is presumably how Edge (and future) platforms compose I/O; the "sections" model is the Neuron/Axon/Patron equivalent.

### 3.3 Per-section board identity via sysfs **[V]** (`en:sw:02-apis:04-sysfs`)
```
/run/unipi-plc/by-sys/iogroup[1-3]/sys_board_name       # read-only; ERROR if the board's unit ID is unknown
/run/unipi-plc/by-sys/iogroup[1-3]/sys_board_serial     # read-only; 0 if invalid
/run/unipi-plc/by-sys/iogroup[1-3]/firmware_version     # format [0-9,A-F].[0-9,A-F][0-9,A-F]
```
The phrase "*Returns error if the board has an **unknown unit ID** and it is not possible to determine the board name*" is the clearest KB statement that **a numeric board/unit ID is read from the coprocessor and looked up in a table of known board types** **[V]**.

### 3.4 Identification registers on the coprocessor itself **[V]** (from the xS/xG Modbus map PDFs; same block on all six maps I read)

| Holding reg (dec / hex) | Len | R/W | Content |
|---|---|---|---|
| **1000 / 0x03E8** | 1 | R | **Firmware Version** (uint16) |
| **1001 / 0x03E9** | 1 | R | *Number of I/Os*: bits 0–7 = **number of DIs**, bits 8–15 = **number of DOs** |
| **1002 / 0x03EA** | 1 | R | *Number of peripherals*: bits 0–3 = **number of internal RS485 lines**, bits 4–7 = **number of AOs**, bits 8–15 = **number of AIs** — **corrected 2026-08-13**, see note below |
| **1003 / 0x03EB** | 1 | R | **Firmware ID** (uint16) |
| **1004 / 0x03EC** | 1 | R | **Hardware ID** (uint16) |
| **1005–1006 / 0x03ED** | 2 | R | **PCB Serial Number** (uint32) |
| 1007 / 0x03EF | 1 | (Mixed) | reserved / mixed bits (Expert) |
| **1008 / 0x03F0** | 1 | RW | **MWD Timeout** (ms) |
| **1009 / 0x03F1** | 1 | R | **VRef of MCU** (uint16) |

This is the register-level self-description you'd use for autodetect: **1004 Hardware ID** is the board-type discriminator, **1003 Firmware ID + 1000 Firmware Version** the firmware identity, **1005/1006** the unit serial, and **1001/1002** give the I/O census (DI, DO, AI, AO, internal RS485 count) so a client can sanity-check a hardware definition against the physical board. **[V]** for extensions; **[I]** — very likely identical on internal PLC boards, since it is one firmware family (`unipi-firmware6`) and the sysfs exposes exactly `sys_board_name` / `sys_board_serial` / `firmware_version` per iogroup. I could not confirm on a PLC map (XLSX) **[GAP]**.

> **Corrected 2026-08-13 (RD-7).** Register **1002**'s bit order above was reversed. The reading came from
> a text-extracted PDF whose columns were scrambled; the Edge XLSX spells the ranges out explicitly and
> `06-register-maps.md` §2.3 carries the verified version: **bits 0–3 = RS485 lines, 4–7 = AOs, 8–15 = AIs**.
> `02-hardware-model.md` §3.3 was fixed on 2026-07-27; this file was missed. It matters because ADR-0014's
> census check refuses to start on a mismatch, so a reversed reading would refuse on every board with AIs.
>
> The **`[GAP]`** above is also closed: the identification block **is** identical on Neuron, Patron, Axon
> and Edge sections — verified against the maps in `docs/modbus-reg-map/` (§2.2 of `06-register-maps.md`).

### 3.5 How EVOK maps an ID to a hardware definition file **[V]** (https://evok.readthedocs.io/en/latest/configs/hw_definitions/ , .../evok_configuration/)
- HW definitions live in **`/etc/evok/hw_definitions/`**, **one YAML file per Modbus device type**, and "**the file name is the device code**".
- A device in `config.yaml` (or `autogen.yaml`) references it by `model:` — e.g. `model: xS51`, `model: IAQ`, and for internal boards `model: "00"` / `model: "13"` (two-hex-digit board codes; on an L533, section 1 = `00`, sections 2 and 3 = `13`).
- `slave-id` is the Modbus unit-id; for standard Unipi controllers "**it is the same as the section number**".
- The mapping ID→file is done by **`unipi-os-configurator`** (`/opt/unipi/tools/os-configurator -f`), which writes `/etc/evok/autogen.yaml` when hardware change is detected, based on **`unipiid`**. EVOK includes that file when `autogen: true`.
- `autogen.yaml` also emits a `device_info` block: `family`, `model`, `sn`, `board_count`.
- Autogen rules **[V]**: bus is always named `LOCAL_TCP`; device name = slave-id; OWFS section only if the device supports 1-Wire and `owserver` is installed; `owpower` only if supported.

**Implication for a drop-in replacement:** you must (a) read `/etc/evok/autogen.yaml` + `/etc/evok/config.yaml`, (b) load `/etc/evok/hw_definitions/*.yaml` keyed by filename, and (c) be prepared for two-hex-digit internal board codes as well as `xS11`-style names.

### 3.6 EVOK "circuit" naming (identity as exposed on the API) **[V]** (https://evok.readthedocs.io/en/latest/circuit/)

| Type | key | circuit format | examples |
|---|---|---|---|
| Relay | `ro` | `<device_name>_<number>` | `2_01`, `xS11_02` |
| Digital output | `do` | `<device_name>_<number>` | `1_01` |
| Digital input | `di` | `<device_name>_<number>` | `1_01`, `xS11_02` |
| Analog out/in | `ao`/`ai` | `<device_name>_<number>` | `1_01`, `xS51_02` |
| User LED | `led` | `<device_name>_<number>` | `1_01`, `2_02` |
| Master Watchdog | `wd` | `<device_name>_<number>` | `1_01` |
| 1-Wire bus / power | `owbus` / `owpower` | `<device_name>` | `1` |
| Temp sensor | `temp` | 1-Wire address w/o dots | `2895DCD509000035` |
| NV save | `nvsave` | `<device_name>` | `1`, `xS51` |
| Modbus slave | `modbus_slave` | `<device_name>` | `1`, `IAQ` |
| Device info | `device_info` | `<model_name>` grouped / `<device_name>` single | `L533`, `S167`, `xS51` |
| Data point | `data_point` | `<device_name>_<register_address>` | `IAQ_0`, `IAQ_6` |
| Modbus register | `register` | `<device_name>_<register_address>` | `1_0`, `1_1000` |

Numbers are zero-padded to 2 digits and derived from the hw-definition `count`.

---

## 4. Modbus register maps

### 4.1 Global structure **[V]** (all six extension PDFs are structurally identical)

Two address bands, in **both** the coil space and the holding-register space:

| Band | Coils | Holding registers |
|---|---|---|
| **I/O data** | 0 … ~30: one coil per RO, DI, ULED | 0 … ~30: **bit-packed** RO/DI/ULED words, AI/AO values, 32-bit counters, sync-RO words |
| **System / config** | 1000 … ~1042 | 1000 … ~1030 |

Categories used in the maps: **Basic / Advanced / Expert / Reserved** **[V]**. Note: the term **"SysP" does not appear anywhere in the KB or in the register maps I read** **[GAP]** — the KB has no such label; the 1000+ band is just "configuration (registers 1000–1100)" (`en:hw:04-extensions:01-first-steps`).

Data-type conventions **[V]**: `uint16/uint`, `int16/int`, `uint32/udint` (2 regs), `float32/real` (2 regs), `MixedBits`. **Word/byte order: 16-bit Big Endian (AB); 32-bit Mid-Little Endian (CDAB)** — i.e. **word-swapped** 32-bit values. This is critical and easy to get wrong.

### 4.2 Register groups (exact, xS11 as the DI/RO archetype) **[V]**

Holding registers:

| Addr | Len | R/W | Type | Content |
|---|---|---|---|---|
| 0 (0x0000) | 1 | R | MixedBits | MWD status group: **bit 0 = MWD Enable**, **bit 1 = MWD Reboot Detected** |
| 1 (0x0001) | 1 | RW | MixedBits | **Relay Outputs** bitmap, bits 0..12 = RO1..RO13 |
| 2 (0x0002) | 1 | R | MixedBits | **Digital Inputs** bitmap, bits 0..11 = DI1..DI12 |
| 3,5,7,…,25 | 2 each | RW | uint32 | **Counters DI1..DI12** (writable ⇒ presettable/resettable) |
| 27–30 | 1 | — | MixedBits | reserved |
| 31 (0x001F) | 1 | RW | MixedBits | **ULED states**, bits 0..2 = ULED1..3 |
| 32 (0x0020) | 1 | RW | MixedBits | **Synchronised Relay Outputs** (RO1..RO13) |
| 33 (0x0021) | 1 | RW | MixedBits | **Synchronised RO Locks** (RO1..RO13) |
| 1000–1009 | | | | identification + MWD timeout + VRef — see §3.4 |
| 1010–1021 | 1 each | RW | uint16 | **Debounce for DI1..DI12**, unit = **100 µs** |
| 1022 (0x03FE) | 1 | RW | MixedBits | **Enable DirectSwitch** per DI (bits 0..11) |
| 1023 (0x03FF) | 1 | RW | MixedBits | **Invert DirectSwitch polarity** per DI |
| 1024 (0x0400) | 1 | RW | MixedBits | **DirectSwitch Toggle mode** per DI |
| 1025, 1026 | 1 | — | MixedBits | reserved (Expert) |
| **1027 (0x0403)** | 1 | RW | MixedBits | **RS485 configuration**: bits **0–12 = baud rate code**, bit **13 = parity (0=Even, 1=Odd)**, bit **14 = parity enable** |
| **1028 (0x0404)** | 1 | RW | uint16 | **Modbus address (1–254)** |

Coils (xS11):

| Addr | R/W | Content |
|---|---|---|
| 0–12 | RW | RO1..RO13 |
| 13–24 | R | DI1..DI12 |
| 25–27 | RW | ULED1..3 |
| **1000** | RW | **MWD reset indication** (set to 0 after reading to detect the next event) |
| 1001 | — | reserved |
| **1002** | RW | **Reset group MCU** (reboot the section/module processor) |
| **1003** | RW | **Save current configuration and use on startup** ("copy running-config to startup-config") |
| 1004–1006 | — | reserved |
| 1007–1018 | RW | Enable DirectSwitch DI1..DI12 |
| 1019–1030 | RW | Invert DirectSwitch polarity DI1..DI12 |
| 1031–1042 | RW | Enable DirectSwitch Toggle mode DI1..DI12 |

The "system" coil quartet **1000 / 1002 / 1003** and the **DirectSwitch triple starting at 1007** are identical on **xS51, xS52, xS53, xS54, xG18** — with per-DI blocks scaled to 4 inputs (1007–1010 enable, 1011–1014 polarity, 1015–1018 toggle) **[V]**.

### 4.3 Per-model deltas in the system band **[V]**

| Model | Debounce | DS enable / polarity / toggle | AI mode regs | RS485 cfg | Modbus addr |
|---|---|---|---|---|---|
| xS11 | 1010–1021 (12 DI) | 1022 / 1023 / 1024 | – | **1027** | **1028** |
| xS51 | 1010–1013 | 1014 / 1015 / 1016 | **1019–1022** (AI1–4, U/I/R) | **1023** | **1024** |
| xS52 | 1010–1013 | 1014 / 1015 / 1016 | **1017–1024** (AI1–8, 2k/20k) | **1025** | **1026** |
| xS53 | 1010–1013 | 1014 / 1015 / 1016 | **1017–1024** (AI1–8, U/I) | **1025** | **1026** |
| xS54 | 1010–1013 | 1014 / 1015 / 1016 | **1017–1024** (AI1–8, U/I/R) | **1025** | **1026** |
| xG18 | – | – | **1010–1017** = per-channel measuring interval (s) | **1018** | **1019** |

**⚠️ There is no fixed offset for the RS485-config and Modbus-address registers — they float depending on how many DI/AI the board has.** Anything that "knows" 1023/1024 will break on xS52/53/54.

### 4.4 AI / AO mode encodings **[V]**

xS51 (`Configuration (U/I/R) of Analog Inputs`) and Patron/Neuron sections 2–3 use the same 6-value enum, which also matches the sysfs table and the EVOK `AI` hw-definition example exactly:

| Value | Mode |
|---|---|
| 0 | Off / Disabled |
| 1 | Voltage 0–10 V |
| 2 | Voltage 0–2.5 V (xS53/54 say 0–2 V) |
| 3 | Current 0–20 mA |
| 4 | Resistance 0–1960 Ω (three-wire) — xS52/54: 75–2000 Ω |
| 5 | Resistance 0–100 kΩ (two-wire) — xS52/54: 1–20 kΩ |

xS52 only: 0=OFF, 1=Resistance 75–2000 Ω, 2=Resistance 1–20 kΩ **[V]**.
xS53 only: 0=OFF, 1=0–10 V, 2=0–2 V, 3=0–20 mA **[V]**.

Sysfs exposes two different AI abstractions **[V]** (`en:sw:02-apis:04-sysfs`), matching the two AI hardware types:
- Section 1 (except S5xx): `AI[1-3].[1-9]/mode_voltage_current`, **0 = Voltage 0–10 V, 1 = Current 0–20 mA** (only 2 modes, 12-bit, 10 µs conversion)
- Sections 2/3 and S5xx: `AI[1-3].[1-9]/mode`, the 6-value enum above (16-bit V/I, 24-bit R)
Read files: `in_voltage_input` (mV), `in_current_input` (mA), `in_resistance_input` (Ω). Only the one matching the set mode is valid.

AO **[V]**: `AO[1-3].[1-9]/mode_voltage_current_resistance`, **0 = Voltage 0–10 V, 1 = Current 0–20 mA, 2 = Resistance 0–2 kΩ**. Section-1 AOR is special: it can also *measure* resistance (`in_resistance_input`). Sections 2/3 AO are voltage-only. Write via `out_voltage_input` (mV) / `out_current_input` (mA). On S-size units, resistance measurement is only possible via the AO (AOR) **[V]** (`en:hw:007-patron:description-of-io:04-description-of-ai`).

### 4.5 PWM **[V]**
EVOK hw definitions model PWM with `pwm_reg` (duty), `pwm_ps_reg` (prescale), `pwm_c_reg` (cycle) and DO `modes: [Simple, PWM]`. Patron DO: max PWM resolution **16 bit**, max PWM frequency **200 kHz**; the saved default is "off, duty 0, resolution 4800 ⇒ frequency 10 kHz, step 0.02 %" (`en:hw:007-patron:description-of-io:02-description-of-do`). Edge DO: **max switching speed 500 Hz / 8 bit**, PWM max resolution 16 bit, **recommended max 200 Hz** (`en:hw:004-edge:11-technical-parameters`) — Edge is far slower than Patron here.

### 4.6 DirectSwitch semantics **[V]**
Three modes: **Copy**, **Inverse copy**, **Switch** (toggle on rising edge), plus **Block** (disabled). Configurable **only between matching-numbered DI and DO/RO in the same section** (DI1→DO1 only). Critical API gotcha: **"If DirectSwitch is applied to an output, it is not possible to write onto output (DO) in a regular way. Instead, you need to set the ForceOutput register to TRUE for approx. 1 second."** (`en:hw:004-edge:02-description-of-io:01-description-of-di`, `en:hw:007-patron:description-of-io:02-description-of-do`) — I did **not** find a `ForceOutput` register address anywhere **[GAP]**; it's presumably the "Synchronised RO / Synchronised RO Lock" pair at holding 32/33 on xS11, but that is my guess **[I]**.

### 4.7 Master Watchdog **[V]** (`en:automation:mwd-hidden`, `en:sw:02-apis:04-sysfs`)
- Registers: **MWD Enable bit** (holding 0 bit 0), **MWD Timeout** (holding 1008, ms), **MWD Reboot Detected** (holding 0 bit 1), **MWD reset indication coil 1000**.
- Semantics: per-section/per-module. Starts only **after the first read of inputs / write of outputs**; every action resets the timer; on expiry the section MCU **reboots into the saved default configuration**.
- **Firmware behaviour change: "In FW versions 6.26 and older any valid communication will start MWD and refresh the timeout on that section. From version 6.28 reading the configuration will not start the MWD on that section."** ⇒ a polling client's config reads can hold the MWD off on ≤6.26 and cannot on ≥6.28. Test both.
- sysfs mirror: `iogroup[1-3]/master_watchdog_enable`, `master_watchdog_timeout` (default **2500**, max **65535**, "strongly recommended > 100"), `was_watchdog` (does not self-clear).
- Danger noted by the KB: after enabling MWD you must save the default configuration **before the timeout expires**, otherwise the MWD reboots the section into a config where MWD is disabled again.
- Saved by "Save current configuration" (coil 1003): **AO/DO/RO states; PWM, PWM_prescale, PWM_Cycle; Debounce, DS_enable, DS_polarity, DS_toggle; UART config**.
- **Neuron vs Patron difference**: on **Neuron**, a section restart resets the **serial bus config to default — you must reconfigure the RS485 line after any section restart**. On **Patron** the serial config is in non-volatile memory and survives. **[V]** — this is a real behavioural fork you must handle.
- MWD is *not* the hardware watchdog: the Edge HW watchdog is a separate GPIO27-pulse/GPIO26-cold-reboot system with a fixed 10 s window (reboot occurs between 10 and 20 s), fed by u-boot then systemd every 4 s (`en:hw:004-edge:06-peripherals:09-other`).

### 4.8 ULED **[V]**
Holding bitmap (xS11 reg 31; xS5x reg 1 field) + individual coils; sysfs `ULED[1-3].[1-9]/brightness` (0 = off, ≥1 = on), Edge path `/run/unipi-plc/by-sys/ULEDx/brightness`. **Explicit warning: "When reading ULED from Modbus registers mind that this value is cached (together with ULED coils). Avoid using Modbus and sysfs together to read/write ULEDs, otherwise the Modbus can return incorrect values."** (`en:hw:004-edge:06-peripherals:09-other`)

### 4.9 Counters and debounce **[V]**
- 32-bit, range 0–4 294 967 295, wraps to 0; **writable** (write 0 to reset). Max input frequency **10 kHz**, min pulse 20 µs. Only rising edges. Available on **every** DI of Edge/Patron/Neuron/Axon/Extension, and on Unipi 1.1/Lite.
- Debounce unit is **hundreds of µs** ("value 10 = 1 ms"); factory value **50 = 5 ms**; **0 = disabled**.

### 4.10 Storage-life registers **[V]** (`en:sw:02-apis:02-modbus-tcp`, `en:sw:02-apis:04-sysfs`)
Available on Modbus TCP for **all units except Unipi 1.1**: *Erase cycles used [%]*, *Good blocks [%]*. Neuron additionally exposes *power cycles* with the current SD card and *SD vendor detection* (only for a limited set of supported SD cards). sysfs: `/run/unipi_stats/cycles_used`, `good_blocks`, `power_cycles`, `vendor_1..3`. Exact register addresses **[GAP]** — only in the XLSX maps. On **Gate**, storage-life status is the *only* thing Modbus TCP/sysfs expose.

### 4.11 EVOK hw-definition schema (what your loader must parse) **[V]** (https://evok.readthedocs.io/en/latest/configs/hw_definitions/)

```yaml
modbus_register_blocks:      # what to poll, and how often
  - start_reg: 0
    count: 10
    frequency: 1             # read every scan_frequency ÷ frequency seconds
    type: holding            # or 'input'
modbus_features:             # how to slice those registers into entities
  - type: DO | RO | DI | AO | AI | WD | DATA_POINT
    count: N                 # addresses increment by this
    reg_type: holding|input
```
Per-type fields: **DO** `val_reg, val_coil, pwm_reg, pwm_ps_reg, pwm_c_reg, modes[Simple,PWM]`; **RO** `val_coil, val_reg`; **DI** `val_reg, counter_reg, deboun_reg, direct_reg, polar_reg, toggle_reg, modes[Simple,DirectSwitch], ds_modes[Simple,Inverted,Toggle]`; **AO** `val_reg, mode_reg, modes{name:{value,unit,range}}, min_v, max_v`; **AI** `val_reg, mode_reg, modes{...}`; **WD** `val_reg, timeout_reg, nv_sav_coil, reset_coil`; **DATA_POINT** `name, unit, value_reg, datatype (null|float32)`.

Beware: the doc's DI example uses `direct_reg: 1016, deboun_reg: 1010, polar_reg: 1017, toggle_reg: 1018` and the DO example `pwm_ps_reg: 1017, pwm_c_reg: 1018`, which **conflicts with the xS51 map** (DS enable 1014 / polarity 1015 / toggle 1016). The doc examples are illustrative composites, not any real board **[I]**. Trust the shipped `/etc/evok/hw_definitions/*.yaml` files and the per-model Modbus maps, not the doc snippets.

Default `scan_frequency` is **50** **[V]**.

---

## 5. Firmware and OS

- **Firmware** = the software on the I/O boards; exists on everything **except Unipi 1.1** **[V]** (`en:sw:04-unipi-firmware:05-update-firmware`).
- Distributed in the Debian package **`unipi-firmware6`** (older: `unipi-firmware`, e.g. `unipi-firmware_5.50_all.deb`), from `https://repo.unipi.technology/debian/pool/`. Tooling package: **`unipi-firmware-tools`** (referenced on every Modbus map PDF). **Installing the package does not flash the boards** — flashing is a manual step **[V]**.
- Flashing tools live in **`/opt/unipi/tools/`**, must be run as root **[V]**:
  - `fwspi` — internal I/O boards. `fwspi -u <section>` shows current FW; `fwspi -av` updates all; `-PRv` also resets configuration (AO type, MWD, default states) via `-R`.
  - `fwserial` — RS-485 Extensions. `fwserial -p /run/unipi-plc/by-sys/rs485-1/tty [-u addr] [-b baud] [--parity E] -Pv`. Defaults assumed: **19200 8N1, address 15**. Options `-b/--baud`, `-o/--stopbits (1|2)`, `-r/--parity (N|E|O)` — **`-r` only exists on Debian 13**.
  - `fwi2c` — internal modules over I²C (from `unipi-tools` README, not the KB).
  - `unipi_modbus_tcp` / `unipitcp` — Modbus TCP server; `libunipichannel.so` — direct kernel-module I/O library.
- **Version constraint that matters: "Direct update from older firmwares (5.x and below) is not possible, an upgrade needs to be performed"** — use `-U` instead of `-P` (`fwspi -u 1 -Uv`, `fwserial ... -u 15 -Uv`) **[V]**. So expect to encounter FW 5.x boards where the modern register layout may not hold.
- Behaviour depends on FW version: MWD start semantics changed at **6.26 → 6.28** (§4.7) **[V]**.
- Bricking hazard **[V]**: during `fwserial` no other application may use the port and power must not be interrupted — "Any of this will lead to bricking the extension."
- **OS**: Debian-based Linux. The KB never uses the string "unipi-os" as a product name on the pages I read **[GAP]**; it talks about **Mervis OS**, **Node-RED OS** and **Base OS** images per family (`en:hw:007-patron:download-image`, `en:hw:004-edge:05-downloads`, etc.). Debian generations explicitly referenced: **10 (unsupported/legacy), 11, 12 Bookworm, 13 Trixie** **[V]**.
  - Debian 13 changes to plan for: `unipitcp` is on `$PATH` (no `/opt/unipi/tools/` prefix); `unipiid` exists **only** on Debian 13+; `extcomm` serial aliases **removed**; the sysfs `ow_power_off` method of disabling 1-Wire **removed** (use the Modbus coil instead).
- Related packages: **`unipi-os-configurator`** (generates `/etc/evok/autogen.yaml`; binary `/opt/unipi/tools/os-configurator -f`), **`evok`**, **`evok-web`**, **`owserver`/OWFS**, **`unipi-lte`** (LTE + `/dev/ttyLTE_AT1`), **`unipi-one-modbus`** (Unipi 1.1) **[V]**.
- Where things live on disk **[V]**:
  - `/etc/evok/config.yaml`, `/etc/evok/autogen.yaml`, `/etc/evok/hw_definitions/*.yaml`
  - `/etc/default/unipitcp`, `/etc/unipi-one-modbus.d/1-modbus.yaml`
  - `/run/unipi-plc/` (symlink hub), `/run/unipi-plc/by-sys/…`, `/run/unipi-plc/unipi-id/…`, `/run/unipi_stats/…`
  - `/etc/nginx/sites-available/evok` (must be edited if you change the EVOK port)
  - Peripheral paths: `/run/unipi-plc/by-sys/tpm/dev`, `/run/unipi-plc/by-sys/retain/mem`, `/dev/rtc`, `/dev/input/event0` (service button)
- EVOK 2 → 3 migration is **unsupported**; a fresh OS is recommended (EVOK README) **[V]**.
- **OWFS caveat [V]**: install OWFS manually on Base OS for 1-Wire; it's preinstalled with EVOK; **never install OWFS on Mervis OS** (collision).
- 1-Wire disable/enable: on Debian ≤12 via `iogroup[1-3]/ow_power_off`; the alternative is unbinding the **DS2482** I²C driver at address 0x18 — `echo x-0018 | sudo tee /sys/bus/i2c/drivers/ds2482/unbind`, where **x = 1 for Neuron, 2 for Patron** **[V]**. (Confirms the 1-Wire master is a DS2482 I²C bridge.)

---

## 6. Extensions on RS-485

### 6.1 Defaults and addressing **[V]** (`en:hw:04-extensions:communication-and-addressing-of-module`)

Factory (SW) defaults: **address 15, 19200 bps, 8 data bits (fixed), no parity** — i.e. **19200 8N1, unit-id 15**. Corroborated by every register-map PDF ("Modbus address 15", "Configuration 14 → 19200 bps, 8N1") and by the `fwserial` docs.

Two configuration channels, with a hard precedence rule:
> "HW configuration of switches is read **only at module startup** (power connection, SW reset, Watchdog). HW configuration will be applied only when **at least one** address switch is in position 1 (ON). If **all** address switches are OFF, the **SW configuration is read instead**."

**DIP switch layouts** (address bits are binary-weighted, summed):

| Models | Switches | Layout |
|---|---|---|
| xS11, xS51, xS52, xS53, xS54 | 5 (next to power connector; No.5 nearest) | 1=+1, 2=+2, 3=+4, 4=bitrate (OFF 19200 / ON 9600), 5=parity (OFF **even** / ON none) |
| xG18 | 6 (+ separate terminator switch by RS485) | 1=+1, 2=+2, 3=+4, 4=+8, 5=bitrate (OFF 19200 / ON 9600), 6=parity (OFF even / ON none) |
| xS10, xS30, xS40 | 8 (next to RS485; No.1 nearest) | 1=terminator, 2=unused, 3=+1, 4=+2, 5=+4, 6=+8, 7=bitrate, 8=parity |
| xS50 | 3 | 1=+1, 2=+2, 3=+4; **baudrate always 19200, parity always even** when HW address is set |

⚠️ Note the trap: DIP-switch addressing gives **1–7** (or 1–15) and **default parity = EVEN**, while the SW default is **address 15, parity NONE**. Switching a module from DIP to SW configuration changes the parity too.

SW configuration range is wider: **Modbus address 1–254** (holding register, see §4.3) and 2400–115200 bps.

### 6.2 Baud-rate register encoding **[I, reconstructed]**
The "Baud rate configuration" table in each PDF has its two columns interleaved by text extraction. The values present are `11, 12, 13, 14, 15, 4097, 4098` and the speeds `2400, 4800, 9600, 19200, 38400, 57600, 115200`; the maps state the **default value is 14 = 19200 bps, 8N1**. That anchors the mapping to:

| Value | Speed |
|---|---|
| 11 | 2400 |
| 12 | 4800 |
| 13 | 9600 |
| **14** | **19200 (default)** |
| 15 | 38400 |
| 4097 (0x1001) | 57600 |
| 4098 (0x1002) | 115200 |

Only `14 = 19200` is directly verified; the rest is ordered inference. **Verify against a real device or the CSV maps before shipping.** Machine-friendly CSVs exist: `files:products:extensions_gateyways:extensions:modbus_maps:extensions_modbus_maps_csv.zip`, `en:files:products:patrons_modbus_maps_csv.zip`, `files:products:neuron:modbus_maps:neurons_modbus_maps_csv.zip`, `files:products:axon:axons_modbus_maps_csv.zip` — I could not unzip these with `web_fetch`, but **these ZIPs are the single best machine-readable source for the full register maps** and you should grab them.

### 6.3 Bus limits and physical layer **[V]**
- **Max devices per line: 32** — stated for Neuron ("One line can communicate with up to 32 devices, using the Modbus RTU protocol", `en:hw:02-neuron`) and Axon ("up to 32 devices with its total length being up to several hundred meters", `en:hw:01-axon`).
- Supported speeds on Patron/Neuron/Extension RS485: 2400, 4800, 9600, 19200, 38400, 57600, 115200 bps.
- **Edge RS-485 is much wider**: 50 baud up to **3 000 000 baud** (`en:hw:004-edge:11-technical-parameters`).
- Terminator: built-in switchable **120 Ω** (`RS485-END` / `S-END`). Patron/Neuron have **560 Ω / 560 Ω** pull-up/pull-down; **Extensions have none** — so the master end provides bias.
- Isolation: Extensions 1.5 kVAC pulse; Patron/Neuron 1000 V isolation, ±15 kV ESD.
- Wiring guidance **[V]** (`en:hw:04-extensions:01-first-steps`): shortest possible runs; strict **serial (daisy-chain) topology**; shielded cable, preferably 0.8 mm J-Y(ST)Y twisted pair or FTP CAT6; shields grounded on one side only, to the cabinet ground, **never** to the device ground point; choose the lowest adequate baud rate for the EMC environment.
- 1-Wire limits **[V]**: up to **15 sensors** per bus; **100 m** max total length (Axon) / **200 m** (Unipi 1.1) with a suitable 1-Wire hub; 2- or 3-wire connection. xG18 provides 8× 1-Wire channels but **only for DS18B20** sensors.

### 6.4 Timing considerations **[I]**
The KB gives no Modbus RTU inter-frame/timeout guidance and no per-transaction latency figures **[GAP]**. What is documented and constrains your polling loop:
- AI conversion times: **60 µs** V/I but **400 ms** for resistance on Patron/Neuron sections 2–3; **200 ms** on xS5x; **100 ms** on Edge. Polling a resistance AI faster than its conversion time is pointless.
- xG18 has a per-channel **measuring interval in seconds** (default 2 s) — 1-Wire temps are inherently slow.
- MWD timeout default 2500 ms, min recommended > 100 ms — your poll period must be comfortably below the configured MWD timeout for every section, and remember that on FW ≥6.28 *config* reads do not count as MWD activity.
- EVOK 3 explicitly improved this area: "**Modbus RTU durability has been improved. Loss of communication with one device will not affect the functionality of the entire bus**" and "Added support to communicate with more Modbus TCP servers" (EVOK README) — i.e. per-device fault isolation on a shared RTU bus is an expected behaviour of a 3.x-compatible implementation.

---

## 7. Things you should watch out for when building the replacement

1. **32-bit values are word-swapped (CDAB).** Counters (uint32) and AI floats (float32) both span 2 registers.
2. **RS485-config and Modbus-address registers are not at fixed offsets** — they shift with DI/AI count (§4.3).
3. **Two different AI abstractions** coexist on the same unit (section 1 two-mode `mode_voltage_current` vs sections 2/3 six-mode `mode`), and **S5xx inverts the rule**. EVOK 3 unified "mode and range into one parameter" — match that.
4. **AO on xS51 is raw 0..4000; AI on xS5x is float32 in engineering units.** No single scaling rule.
5. **DirectSwitch blocks normal DO writes**; needs a ForceOutput dance whose register address the KB does not publish.
6. **Neuron loses its RS485 config on section restart; Patron does not.**
7. **ULED values are cached** across the Modbus/sysfs boundary — pick one and stick to it.
8. **1-Wire is not on Modbus.** It's OWFS/owserver, DS2482 on I²C, with `owpower` for bus reset.
9. **Firmware 5.x boards exist and need an "upgrade" (`-U`) not an "update" (`-P`)**; their register layout may differ.
10. **Debian 13 vs 12 vs 11 change paths, tool locations, and available APIs.** `unipiid` is 13+ only; `extcomm` is gone on 13.
11. **Gate has no I/O** — EVOK on Gate exists only to reach Extensions.
12. **Unipi 1.1 is a completely different animal**: no coprocessor firmware, no sysfs support, Modbus via `unipi-one-modbus` on **port 50200**, GPIO/I²C underneath.

---

## Appendix A — URLs successfully read

Unipi KB (HTML):
- https://kb.unipi.technology/en:00-start?redirect=1
- https://kb.unipi.technology/en:sw:02-apis
- https://kb.unipi.technology/en:sw:02-apis:01-evok
- https://kb.unipi.technology/en:sw:02-apis:02-modbus-tcp
- https://kb.unipi.technology/en:sw:02-apis:04-sysfs
- https://kb.unipi.technology/en:sw:02-apis:05-unipiid
- https://kb.unipi.technology/en:sw:04-unipi-firmware
- https://kb.unipi.technology/en:sw:04-unipi-firmware:05-update-firmware
- https://kb.unipi.technology/en:hw:004-edge
- https://kb.unipi.technology/en:hw:004-edge:02-description-of-io
- https://kb.unipi.technology/en:hw:004-edge:02-description-of-io:01-description-of-di
- https://kb.unipi.technology/en:hw:004-edge:05-downloads
- https://kb.unipi.technology/en:hw:004-edge:06-peripherals:01-rs485
- https://kb.unipi.technology/en:hw:004-edge:06-peripherals:09-other
- https://kb.unipi.technology/en:hw:004-edge:11-technical-parameters
- https://kb.unipi.technology/en:hw:007-patron
- https://kb.unipi.technology/en:hw:007-patron:description-of-io
- https://kb.unipi.technology/en:hw:007-patron:description-of-io:02-description-of-do
- https://kb.unipi.technology/en:hw:007-patron:description-of-io:04-description-of-ai
- https://kb.unipi.technology/en:hw:007-patron:downloads
- https://kb.unipi.technology/en:hw:007-patron:portmap
- https://kb.unipi.technology/en:hw:007-patron:technical-parameters
- https://kb.unipi.technology/en:hw:01-axon
- https://kb.unipi.technology/en:hw:01-axon:downloads
- https://kb.unipi.technology/en:hw:02-neuron
- https://kb.unipi.technology/en:hw:02-neuron:description-of-io
- https://kb.unipi.technology/en:hw:02-neuron:downloads
- https://kb.unipi.technology/en:hw:02-neuron:portmap
- https://kb.unipi.technology/en:hw:02-neuron:technical-parameters
- https://kb.unipi.technology/en:hw:025-gate
- https://kb.unipi.technology/en:hw:03-unipi11
- https://kb.unipi.technology/en:hw:03-unipi11:description-of-io
- https://kb.unipi.technology/en:hw:04-extensions
- https://kb.unipi.technology/en:hw:04-extensions:01-first-steps
- https://kb.unipi.technology/en:hw:04-extensions:communication-and-addressing-of-module
- https://kb.unipi.technology/en:hw:04-extensions:description-of-io
- https://kb.unipi.technology/en:hw:04-extensions:downloads
- https://kb.unipi.technology/en:hw:04-extensions:technical-parameters
- https://kb.unipi.technology/en:hw:05-sensors:iaq
- https://kb.unipi.technology/en:automation:02-glossary
- https://kb.unipi.technology/en:automation:mwd-hidden

Modbus register maps (PDF, read in full):
- .../unipi-extension-xs11-modbus-map.pdf
- .../unipi-extension-xs51-modbus-map.pdf
- .../unipi-extension-xs52-modbus-map.pdf
- .../unipi-extension-xs53-modbus-map.pdf
- .../unipi-extension-xs54-modbus-map.pdf
- .../unipi-extension-xg18-modbus-map.pdf
- https://kb.unipi.technology/_media/files:unipi-plc-comparison-en.pdf (mostly compute-module/marketing comparison; per-model I/O counts are graphic ticks and did not extract)

Other:
- https://github.com/UniPiTechnology/evok
- https://github.com/UniPiTechnology/unipi-tools
- https://evok.readthedocs.io/en/latest/
- https://evok.readthedocs.io/en/latest/configs/evok_configuration/
- https://evok.readthedocs.io/en/latest/configs/hw_definitions/
- https://evok.readthedocs.io/en/latest/circuit/

## Appendix B — Failures and gaps

**Fetch failures / unreadable content:**
- `https://kb.unipi.technology/_media/en:files:products:patron_m527_modbus_map.xlsx` → returned `[binary data]`. **All PLC Modbus maps (Patron, Neuron, Axon, Edge) are XLSX and are unreadable via `web_fetch`.** Only Extension maps exist as PDF.
- `https://kb.unipi.technology/en:hw:007-patron:description-of-io:01-description-of-di` returned an **empty body** on first attempt (the parent `description-of-io` page worked; I used the Edge DI page for equivalent content).
- Image-only tables I could not read: Neuron model overview (`en:hw:tabulka-neuron-en.png`), Extension model overview (`en:hw:extensions_table.png`), Patron model overview, Edge **part-number decoder** (`004-edge:product_number_description.png`), Edge E410 block diagram, sections/sizes diagram.
- ZIP archives of machine-friendly CSV register maps (Patron/Neuron/Axon/Extension) could not be opened — **strongly recommend downloading these manually; they are the definitive machine-readable register source.**

**Documented gaps in the KB itself:**
- No published register addresses for the **storage-life** registers (only names).
- No published address for the **ForceOutput** register referenced by the DirectSwitch warning.
- The term **"SysP"** appears nowhere in the KB or in any register map — the 1000+ band is only described as "configuration (registers 1000–1100)". If EVOK's code uses "SysP", it is an internal name with no KB counterpart.
- `platform_family` numeric IDs are only published for **Edge (6)** and **Patron (7)**; Neuron/Axon/Gate values are not stated.
- The internal CPU↔coprocessor bus is never named in KB prose; SPI is established via `fwspi` and the `unipi-tools` README.
- No Modbus RTU timing/inter-frame guidance, and no per-model AI/AO/DI/RO counts in machine-readable form on the KB (only in datasheets and the XLSX maps).
- Unipi 1.1's Modbus unit-id / register map is not documented on the pages I read.agentId: a6a24ac45b9205841 (use SendMessage with to: 'a6a24ac45b9205841', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 376967
tool_uses: 62
duration_ms: 497426</usage>