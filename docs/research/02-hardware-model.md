# Unipi hardware model

Condensed from the full research report in
[`appendix/raw-hardware-research.md`](appendix/raw-hardware-research.md), which carries the
per-page citations and the complete register tables. Read that when you need an exact
address; read this for the shape of the domain.

---

## 1. The one thing that matters most

**EVOK never speaks SPI, I²C or sysfs. It is a Modbus client, full stop.** `[V]`

- On a Unipi controller, the I/O boards are reached over **Modbus TCP to
  `127.0.0.1:502`**, served by the `unipitcp` daemon (older images: `unipi_tcp_server`),
  which owns the SPI link to the section coprocessors. Unit-id = **section number**.
- On Unipi 1.1 / Lite the equivalent daemon is `unipi-one-modbus` on **port 50200**.
- Extensions are reached over **Modbus RTU** on an RS-485 line.
- **1-Wire is not on Modbus at all** — it goes through OWFS/`owserver` (TCP 4304), with a
  DS2482 I²C bridge underneath and a Modbus coil for bus power.

So evok-node needs exactly two hardware transports (Modbus TCP client, Modbus RTU client)
plus an optional OWFS client. Everything else — SPI, sysfs, `unipiid` — is *identity and
diagnostics*, not a data path.

---

## 2. Product families

| Family | Compute | I/O organisation | Status |
|---|---|---|---|
| **Patron** (S/M/L, `x_x7`) | i.MX 8M Mini, 1 GB / 8 GB eMMC | 1–3 **sections**, each an STM32 coprocessor | current |
| **Neuron** (`x_x3`) | Raspberry Pi 3B/3B+/4B + microSD | 1–3 sections, STM32 each | current |
| **Axon** (`x_x5`) | Allwinner H5 | 1–3 I/O groups, STM32 each | **discontinued** |
| **Edge** (E410/E411/E412/E413) | Unipi compute module | slot/card system, not sections | current, newest |
| **Gate** (G100/G110) | ARM A53 600 MHz | **no local I/O** | current |
| **Unipi 1.1 / Lite** | RPi via GPIO ribbon | GPIO + I²C, no coprocessor firmware | legacy |
| **Extensions** (xS11, xS51–54, xG18, …) | STM32 only | external RS-485 modules | current |
| **Sensors** (IAQ RW/RLW) | — | RS485 RTU / TCP / Wi-Fi | current |

Size ⇒ section count on Neuron/Axon/Patron: **S = 1, M = 2, L = 3**. Section **0** is
special — all sections are reachable through unit-id 0 using
**`address + ((unitId - 1) × 100)`**. `[V]` — see [`06-register-maps.md`](06-register-maps.md)
§2.1 for the exact rule and its exclusions.

Model code `<Size><CC><F>` where `F` = family digit (**3** Neuron, **5** Axon, **7**
Patron) and `CC` is a shared I/O-configuration code, `x6x` = LTE variants. **[I]** — the
pattern holds across all three published model lists but the KB never states the rule.
Do not build a parser on it.

Sections are **independent failure domains**: own master watchdog, own NVRAM default
config, own reset. Model them as such.

---

## 3. Identity and self-description

Three layers, and evok-node needs all three for different purposes.

### 3.1 Host-side: `unipiid` (Debian 13+) `[V]`

`unipiid -d` populates `/run/unipi-plc/unipi-id/` with world-readable text files:

```
product_description  product_model      product_model_full  product_version
product_serial       product_code       product_family      product_options
platform_family      platform_id        mainboard_description
mainboard_id         uboard_id          api_version         fingerprint
```

- `platform_family`: **Edge = 6, Patron = 7**. Neuron/Axon/Gate values not published `[GAP]`.
- `platform_id` raw = `(series << 8) | family` **[I]**, consistent with both published samples.
- `product_code` = `#SKU;model_full_version;serial#` and equals the 2D DataMatrix on the label.
- **`fingerprint`** — recomputed every boot, changes whenever the hardware configuration
  changes. This is the correct cache-invalidation key for a generated device tree.
- Two independent `api_version` counters exist (`unipiid` returns `2`; sysfs
  `unipi-id/api_version` returns `1.1`). Both docs say to check the version before use.

### 3.2 Per-section: sysfs `[V]`

```
/run/unipi-plc/by-sys/iogroup[1-3]/sys_board_name      # errors if unit ID unknown
/run/unipi-plc/by-sys/iogroup[1-3]/sys_board_serial
/run/unipi-plc/by-sys/iogroup[1-3]/firmware_version    # [0-9A-F].[0-9A-F][0-9A-F]
/run/unipi-plc/by-sys/rs485-N/tty                      # serial line aliases
/run/unipi-plc/unipi-id/...                            # unipiid output
/run/unipi_stats/{cycles_used,good_blocks,power_cycles,vendor_1..3}
```

The wording *"returns error if the board has an unknown unit ID and it is not possible to
determine the board name"* is the clearest evidence that a numeric board-type ID is read
from the coprocessor and looked up in a table. `[V]`

`/dev/extcomm/Y/X` serial aliases are **deprecated and removed on Debian 13** — use
`/run/unipi-plc/by-sys/rs485-N/tty`. `[V]`

### 3.3 On the coprocessor: identification registers `[V]`

Verified identical across the Extension maps **and** the Neuron/Patron/Axon/Edge maps now in
`docs/modbus-reg-map/` — see [`06-register-maps.md`](06-register-maps.md) §2.2:

| Holding reg | Content |
|---|---|
| **1000** | Firmware Version (uint16) |
| **1001** | bits 0–7 = number of **DIs**, bits 8–15 = number of **DOs** |
| **1002** | bits 0–3 = internal **RS485 lines**, bits 4–7 = **AOs**, bits 8–15 = **AIs** |
| **1003** | Firmware ID |
| **1004** | **Hardware ID** — the board-type discriminator |
| 1005–1006 | PCB serial number (uint32) |
| 1007 | Interrupt Mask (PLC) / Reserved (Edge) — semantics undocumented |
| 1008 | Section/Group MWD timeout (ms), RW |
| 1009 | MCU VRef |

> **Corrected 2026-07-27.** An earlier revision of this file (and the raw hardware appendix)
> had register 1002's fields in the reverse order — that reading came from a text-extracted
> PDF whose columns were scrambled. The Edge XLSX spells the bit ranges out explicitly and
> the table above is authoritative.

This is enough to **cross-check a hardware definition against the physical board at
startup** — read 1001/1002 and assert the DI/DO/AI/AO counts match the definition. EVOK
does not do this. We should: it converts "wrong `model:` in config" from a silent
wrong-register catastrophe into a startup error.

---

## 4. Register-map conventions

### 4.1 Address bands `[V]`

Both the coil space and the holding-register space are split:

| Band | Coils | Holding registers |
|---|---|---|
| **I/O data** | 0 … ~30 (one per RO/DI/ULED) | 0 … ~35 (bit-packed RO/DI/ULED words, AI/AO values, 32-bit counters) |
| **System / config** | 1000 … ~1042 | 1000 … ~1030 |

Note the term **"SysP"** appears nowhere in Unipi documentation — if you find it in EVOK
code or forum posts it's an internal name. `[GAP]`

### 4.2 Encoding `[V]`

- 16-bit: **big endian (AB)**.
- 32-bit (`uint32` counters, `float32` AI values): **mid-little endian (CDAB)** — i.e.
  **word-swapped**. Getting this wrong yields plausible-looking garbage.
- Types seen: `uint16`, `int16`, `uint32`, `float32`, `MixedBits`.
- EVOK's own code confirms the convention:
  `BinaryPayloadBuilder(byteorder=Endian.BIG, wordorder=Endian.LITTLE)`. `[V-src]`

### 4.3 The xS11 map as archetype `[V]`

Holding: `0` MWD status bits (0=enable, 1=reboot detected) · `1` RO bitmap · `2` DI
bitmap · `3,5,…,25` DI counters (uint32, writable) · `31` ULED bits · `32` synchronised
RO · `33` synchronised RO locks · `1000–1009` identification · `1010–1021` per-DI
debounce (unit **100 µs**) · `1022/1023/1024` DirectSwitch enable / invert / toggle ·
`1027` RS485 config · `1028` Modbus address.

Coils: `0–12` RO · `13–24` DI (read-only) · `25–27` ULED · `1000` MWD reset indication ·
`1002` **reset group MCU** · `1003` **save running config as startup config** ·
`1007+` DirectSwitch enable/polarity/toggle per DI.

### 4.4 ⚠ The system registers float `[V]`

| Model | Debounce | DS en/pol/tog | AI mode regs | RS485 cfg | Modbus addr |
|---|---|---|---|---|---|
| xS11 | 1010–1021 | 1022/1023/1024 | – | **1027** | **1028** |
| xS51 | 1010–1013 | 1014/1015/1016 | 1019–1022 | **1023** | **1024** |
| xS52/53/54 | 1010–1013 | 1014/1015/1016 | 1017–1024 | **1025** | **1026** |
| xG18 | – | – | 1010–1017 (interval s) | **1018** | **1019** |

**There is no fixed offset for the RS485-config and Modbus-address registers.** Any code
that hard-codes 1023/1024 breaks on xS52/53/54. These must come from the hardware
definition.

### 4.5 AI / AO modes `[V]`

Two different AI abstractions coexist on the same unit:

- **Section 1** (except S5xx models): 2 modes — `0` = Voltage 0–10 V, `1` = Current
  0–20 mA. 12-bit, 10 µs conversion.
- **Sections 2/3 and S5xx**: 6 modes — `0` Off, `1` Voltage 0–10 V, `2` Voltage 0–2.5 V
  (xS53/54: 0–2 V), `3` Current 0–20 mA, `4` Resistance 0–1960 Ω 3-wire (xS52/54:
  75–2000 Ω), `5` Resistance 0–100 kΩ 2-wire (xS52/54: 1–20 kΩ). 16-bit V/I, 24-bit R.
- xS52 has its own 3-value enum; xS53 its own 4-value enum.

AO: `0` Voltage 0–10 V, `1` Current 0–20 mA, `2` Resistance 0–2 kΩ. Section-1 AO (AOR) can
also *measure* resistance — on S-size units that is the only way to measure resistance.
Sections 2/3 AO are voltage-only.

Scaling is **not uniform**: xS5x AI values are `float32` already in engineering units,
while xS51 AO is a raw `0..4000` ↔ `0..10 V` count. EVOK's `AnalogOutput.set_value`
hard-codes `value / 0.0025` clamped to 4095. `[V-src]` Do not assume one scaling rule —
drive it from the definition's `modes[].range` and a per-type codec.

Conversion times constrain polling: **60 µs** for V/I, but **400 ms** for resistance on
Patron/Neuron sections 2–3, 200 ms on xS5x, 100 ms on Edge. Polling a resistance AI faster
than that is wasted bus time.

### 4.6 PWM `[V]`

Modelled by `pwm_reg` (duty), `pwm_ps_reg` (prescale), `pwm_c_reg` (cycle). Patron DO: up
to 16-bit, 200 kHz; saved default is duty 0, resolution 4800 ⇒ 10 kHz. Edge DO is far
slower: max switching 500 Hz / 8-bit, PWM recommended ≤ 200 Hz.

Duty is *derived* from frequency and prescaler — the trio must be computed and written as a
unit and re-read after restart. Upstream fixed the PWM frequency formula twice.

### 4.7 DirectSwitch `[V]`

Firmware-level DI→DO/RO coupling, configurable **only between matching-numbered DI and
DO/RO in the same section**. Modes: Copy, Inverse copy, Switch (toggle on rising edge),
Block.

**Critical API trap:** *"If DirectSwitch is applied to an output, it is not possible to
write onto output (DO) in a regular way. Instead, you need to set the ForceOutput register
to TRUE for approx. 1 second."* The `ForceOutput` register address is **not published**
anywhere `[GAP]`; the "Synchronised RO / Synchronised RO Lock" pair at holding 32/33 is a
plausible candidate **[I]**. Needs verification on hardware.

### 4.8 Master watchdog (MWD) `[V]`

Per section / per module. Registers: enable bit (holding 0 bit 0), timeout ms (holding
1008), reboot-detected bit (holding 0 bit 1), reset-indication coil 1000. Default timeout
**2500 ms**, max 65535, "strongly recommended > 100".

Semantics: starts after the first I/O read or write; every action refreshes it; on expiry
the section MCU **reboots into the saved default configuration**.

Behaviour forks that must be handled explicitly:

- **FW ≤ 6.26**: any valid communication refreshes the MWD. **FW ≥ 6.28**: reading the
  *configuration* no longer starts/refreshes it. A polling design that relies on config
  reads keeping the MWD alive works on one and not the other. `[V]`
- **Neuron**: a section restart **resets the RS485 line config to defaults** — you must
  reconfigure the serial line after any section restart. **Patron**: config is in
  non-volatile memory and survives. `[V]`
- After enabling the MWD you must save the default config *before the timeout expires*,
  or the MWD reboots the section into a config with MWD disabled.

The poll period must be comfortably below the configured MWD timeout for **every** section
— and a dead peer must never starve a healthy section's poll slot (this is exactly how
issue #123 dropped outputs on a healthy device).

MWD ≠ the Edge hardware watchdog (GPIO27 pulse / GPIO26 cold reboot, fixed ~10 s window).

### 4.9 Counters and debounce `[V]`

32-bit, 0 … 4 294 967 295, wraps to zero, **writable** (write 0 to reset). Rising edges
only. Max input frequency **10 kHz**, min pulse 20 µs. Debounce unit is **100 µs**
(value 10 = 1 ms); factory 50 = 5 ms; 0 = disabled.

Because counters are lossless and events are not, **counter fidelity is what lets us shed
change events under load**. Guarantee it.

### 4.10 ULED `[V]`

Bitmap register plus individual coils, and a sysfs `brightness`. Documented warning: the
Modbus view of ULED is **cached together with the ULED coils** — mixing Modbus and sysfs
access returns incorrect values. Pick one path (Modbus) and stay on it.

---

## 5. Extensions on RS-485

Factory/SW defaults: **address 15, 19200 bps, 8N1**. `[V]`

Configuration precedence, and it is a real trap: `[V]`

> HW switch configuration is read **only at module startup**. It is applied only when **at
> least one** address switch is ON. If **all** address switches are OFF, the SW
> configuration is used instead.

DIP switch addressing yields 1–7 (or 1–15) and **parity = EVEN**, while the SW default is
address 15 and **parity = NONE**. Moving a module between the two changes its parity.

SW config range: address **1–254**, 2400–115200 bps.

Baud-rate register encoding — only `14 = 19200` is verified; the rest is ordered
inference **[I]** and must be checked before shipping:
`11=2400, 12=4800, 13=9600, 14=19200, 15=38400, 4097=57600, 4098=115200`.

Bus limits: **32 devices** per line, several hundred metres. Strict daisy-chain topology,
shielded twisted pair, shield grounded one side only. Built-in switchable 120 Ω
terminator; Patron/Neuron provide 560 Ω bias, **Extensions do not** — the master end
supplies it. Edge RS-485 supports 50 baud … 3 Mbaud.

The KB gives **no** Modbus RTU inter-frame or timeout guidance `[GAP]`. Derive t1.5 / t3.5
from the baud rate per the Modbus spec and enforce them with real timestamps — upstream's
50 µs `asyncio.sleep` hotfix is an event-loop yield, not bus turnaround.

1-Wire: up to **15 sensors** per bus, 100–200 m with a hub. xG18 gives 8 channels but
DS18B20 only.

---

## 6. Firmware and OS facts worth encoding

- Firmware lives on the I/O boards; exists on everything **except Unipi 1.1**. Package
  `unipi-firmware6`; tools in `/opt/unipi/tools/` (`fwspi`, `fwserial`, `fwi2c`).
- `fwspi -u <n>` — `-u` is the **board Modbus address = section number**. Direct proof
  that section number and Modbus unit-id are the same thing. `[V]`
- **FW 5.x → 6.x needs an "upgrade" (`-U`) not an "update" (`-P`)**; 5.x boards exist in
  the field and their register layout may differ. Read and check firmware version at
  startup and warn below a known-good floor.
- Debian generation matters: `unipiid` is **13+ only**; `extcomm` aliases removed on 13;
  the sysfs `ow_power_off` method of disabling 1-Wire removed on 13 (use the Modbus coil).
- Relevant paths: `/etc/evok/{config.yaml,autogen.yaml,hw_definitions/}`,
  `/var/lib/evok/alias.yaml`, `/etc/default/unipitcp`,
  `/etc/unipi-one-modbus.d/1-modbus.yaml`, `/run/unipi-plc/`, `/etc/nginx/sites-available/evok`.
- OWFS: preinstalled with EVOK, manual on Base OS, **never** install on Mervis OS.

---

## 7. Per-family gotcha summary

1. 32-bit values are **word-swapped** (CDAB).
2. RS485-config and Modbus-address registers are **not at fixed offsets**.
3. **Two different AI abstractions** on one unit, and S5xx inverts the rule.
4. AO raw counts vs AI engineering units — no single scaling rule.
5. **DirectSwitch blocks normal DO writes**; the ForceOutput register is undocumented.
6. **Neuron loses RS485 config on section restart; Patron doesn't.**
7. ULED values are cached across the Modbus/sysfs boundary.
8. **1-Wire is not on Modbus.**
9. FW 5.x boards need a different flash path and may differ in layout.
10. Debian 11/12/13 change tool paths and available APIs.
11. **Gate has no I/O** — EVOK on Gate exists only to reach Extensions.
12. **Unipi 1.1 is a different animal**: no board firmware, no sysfs, Modbus on port
    **50200**, GPIO/I²C underneath.
