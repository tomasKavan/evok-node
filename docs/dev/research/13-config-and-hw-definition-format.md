# Our own hardware-definition format

**Status: a proposal, not in force.** This file is the format specification that
[`to_revision/0014`](to_revision/0014-hardware-definitions-and-inventory-are-ours.md) points at; that
file carries the decision and the rejected alternatives. §8's upstream changes have been **applied** — it
is kept as the record of what moved and why.

> **Correction, 2026-08-18.** This header read *"accepted 2026-08-13 as ADR-0014, which supersedes
> ADR-0007."* The ADR set was dissolved rather than re-locked on that date, so nothing here is accepted:
> the format is decided when `dev/02` and `dev/07` decide it. See
> [`to_revision/README.md`](to_revision/README.md).

Premise: **we own our definitions and our own inventory generation, and depend on no Unipi package for
either.**

---

## 1. Namespaces

Two roots, **disjoint** — not layered, not merged, no precedence rules, no per-field provenance:

```
ours    <pkg>/definitions/<transport>/<vendor>/<device>.yaml                  ours, overwritten on upgrade
custom  /etc/evok-node/hw_definitions/custom/<transport>/<vendor>/<device>.yaml   theirs, never touched
```

A definition is named by its **id**, and every reference to a device — in config or in generated
inventory — names that id. Shape follows research/12's config sketch:

```yaml
# /etc/evok-node/config.yaml
drivers:
  PLC:
    type: onboard
    autogen: true                                        # main loads /etc/evok-node/autogen.yaml,
                                                         # which supplies transport and devices both

  PLC2:                                                  # the same driver, configured by hand
    type: onboard
    transport: { kind: modbus-tcp, host: 127.0.0.1, port: 502 }
    autogen: false
    devices:                                             # allowed only when autogen is false;
      - { unit: 1, definition: modbus/unipi/brain-s107 }  # `unit` and `definition` are the only keys
      - { unit: 2, definition: modbus/unipi/e4ai4ao4di5ro }

  EXT:
    type: extension                                      # always declared; autogen is not allowed
    transport: { kind: modbus-rtu, port: /dev/ttyNS0, baud: 19200, parity: none }
    units:
      xS11: { unit: 1, definition: modbus/unipi/xs11 }
      WM:   { unit: 7, definition: custom/modbus/acme/wm-3f }
```

`/etc/evok-node/autogen.yaml` is written by our own `run.d` plugin script (§7) and names the same
definition ids in the same shape, so `main` loads one or the other and the driver sees no difference.

Two rules fall out, both **config-parse checks needing no handshake** — the same class as the three
in research/12 §Validation, and they belong in that list:

- `autogen: true` is **exclusive**: `devices:` or `transport:` on the same driver is a configuration
  error, not a precedence rule. The generated file supplies both, so "which one won?" — the question
  ADR-0006 exists to never ask again — cannot arise.
- `autogen:` is allowed **only on `onboard` and `onewire`** — the two the generator emits sections
  for. On any other driver it is a parse error, not a silently ignored key.

This implies one rename against research/12's sketch: `model: xS11` becomes
`definition: modbus/unipi/xs11`. `model` was EVOK's word for a `hw_definitions` filename; ours is an
id in a namespace, and the two are not the same thing.

Consequences worth stating plainly:

- We never merge, so an operator who needs one field changed in a definition of ours **copies the
  whole file into `custom/` under a new id** and points config at it. That is the only escape hatch,
  and it is deliberate: it cannot drift silently against our upgrades, because it is a different
  device as far as the daemon is concerned.
- `check-definitions` prints the id and the root, and nothing else about provenance is needed.
- Ours may be overwritten by `apt` freely; nothing an operator wrote can be lost by an upgrade.

**`custom` is a reserved top-level segment** — `custom/modbus/acme/wm-3f`, not
`modbus/custom/wm-3f` — so "never touched by us" is visible in every id, not only in the path on disk.
An id is exactly the relative path under its root, in both roots:

```
modbus/unipi/xs11          →  <pkg>/definitions/modbus/unipi/xs11.yaml
custom/modbus/acme/wm-3f   →  /etc/evok-node/hw_definitions/custom/modbus/acme/wm-3f.yaml
```

Nothing we ship may be named `custom/…`, which is what makes the two namespaces provably disjoint
rather than disjoint by convention: a loader that sees a `custom/` id looks in exactly one root, and
an id without that prefix looks in exactly the other.

An id resolves to **either a file or a directory** — a directory when the model has several firmware
variants (§2.2), and both forms existing for one id is a load-time error. Config names the id in either
case; the variant is chosen at handshake and never written by an operator.

## 2. Envelope

Transport-neutral header, transport-specific body, so `onewire/` and `system/` slot in later without
a format revision.

```yaml
schema: 1                     # our format version; we own it, so it changes only when we change it
id: modbus/unipi/xs11
transport: modbus
vendor: unipi
device: xs11
name: "Unipi Extension xS11"

identifies:                   # how a detected or configured device resolves to this file
  models: ["xS11"]            # what unipiid / os-configurator reports
  boardCodes: []              # two-hex-digit codes, for onboard sections: "00", "0A", "13"
  minFirmware: 0x0600         # lowest firmware this file is valid for — see §2.2
  hardwareId: null            # holding 1004 — the board's own answer. null until measured (§2.1)

evokCompat:                   # migration + api-compat only; never read on a request path
  model: xS11                 # the /etc/evok/hw_definitions filename this replaces

provenance:                   # how this file was authored — a record, not a rebuild recipe (§4.3)
  sources:
    - docs/modbus-reg-map/extensions/Extension_xS11/*.csv
    - docs/evok-hw-definitions/xS11.yaml
  authoredAt: 2026-08-13
  reviewedBy: tomas
  verifiedOnRig: false
```

### 2.1 Identity check — is the thing at unit 3 really what config claims?

**The problem.** RS-485 has no discovery. When config says `unit: 3, definition: modbus/unipi/xs11`,
that is an unverified claim by whoever wrote the config. Wire an xS51 at unit 3 instead and nothing
tells us: we poll xS11 addresses on an xS51 and write to coils that mean something else on that board.
That is the wrong-relay failure class arriving through a typo rather than through a bank-stride bug.

**The fix.** Ask the board what it is at handshake, and refuse to start on disagreement. Every Unipi
board answers the same identification block at holding **1000–1009**, on every family
(research/06 §2.2), so this works everywhere and costs one read. Two mechanisms, strongest first:

**`identifies.hardwareId` — holding 1004.** Identifies the board directly. This is the real check, and
we use it wherever we know the value.

**`census` — holding 1001/1002.** The channel counts the definition was written for, compared against
what the board reports:

| Reg | bits 0–7 | bits 8–15 |
|---|---|---|
| 1001 | number of DIs | number of DOs |
| 1002 | bits 0–3 internal RS485 lines · bits 4–7 AOs | bits 8–15 AIs |

```yaml
census: { di: 12, ro: 13, ai: 0, ao: 0 }        # xS11, checked against 1001/1002 at handshake
```

**Why both, and not just the hardware ID.** Unipi documents register 1004 but publishes no
Hardware-ID-to-model table anywhere in `docs/modbus-reg-map/`, so the values are only learnable by
reading them off a physical board. We can generate a census for all ~40 models from the maps today
without touching hardware; we can generate a hardware-ID match for the handful we own. So census is the
check that works on the models we will never see — which is most of the supported set (ADR-0008).

Census is the weaker test: two different models can have identical channel counts, and it infers
identity rather than reading it. It is a sanity check, not proof. Where `hardwareId` is present it is
authoritative and census is redundant confirmation; where it is null, census is all we have.

Either mismatch is a **refusal to run**, not a warning, naming the unit — because every address the
definition computes from that point on is suspect. That is research/03 §4 validation rule 5, and these
two fields are what make it checkable.

**Promotion path, no extra trip work.** `capture-trip.md` line 68 already collects 1000/1001/1002/1003/1004
per unit id. Every unit we touch fills in one more `hardwareId`, so models move from census-only to
identified over time. A definition with a null `hardwareId` is normal, not incomplete.

Two wrinkles for whoever implements it: EVOK counts relays in 1001's **DO** byte, so a definition
declaring `RO` features has to know its `ro:` count is checked against the DO field; and research/06
§2.3 is a **correction** — 1002's bit order is documented backwards in `02-hardware-model.md` §3.3 and
in the raw appendix, both of which need an RD-7 note in the PR that implements this.

### 2.2 Firmware variants — several files per model, closest floor wins

**How EVOK solves this: it doesn't.** Its schema has exactly two top-level keys,
`modbus_register_blocks` and `modbus_features` (research/03 §4) — no version field, no matcher. One
file per model, applied to whatever answers at that unit id. Register 1000 *is* the firmware version,
but EVOK surfaces it only when a definition happens to declare a `REGISTER` feature covering it,
appearing as a generic circuit like `1_1000` for a human to read. Nothing branches on it. So both known
forks go unhandled: FW 5.x boards, which exist in the field and whose register layout may differ, get
the 6.x-shaped definition anyway (research/02 §6), and the MWD behaviour change at 6.26 → 6.28 is
invisible (research/02 §4.8). Nothing observable in EVOK depends on a firmware field, so everything
here is additive and cannot break the compat surface.

**Decision.** A model may have **several definition files, each declaring the minimum firmware it is
valid for.** At handshake the driver reads the board's firmware and selects the file with the
**highest `minFirmware` that is still ≤ the board's version** — the closest floor.

A multi-variant model is a **directory**; a single-variant model stays a single file. Both forms
resolving the same id is a load-time error:

```
modbus/unipi/xs11        →  …/definitions/modbus/unipi/xs11.yaml          single variant
modbus/unipi/xs51        →  …/definitions/modbus/unipi/xs51/0600.yaml     minFirmware 0x0600
                            …/definitions/modbus/unipi/xs51/0628.yaml     minFirmware 0x0628
```

Config always names the **model** id, never a variant — `definition: modbus/unipi/xs51`. Which file
was chosen is a diagnostic, reported by `check-definitions` and in the driver's handshake log, never
something an operator has to write.

**Compare firmware as the raw uint16, not as a decimal string.** The sysfs form is
`[0-9A-F].[0-9A-F][0-9A-F]` (research/02, `/run/unipi-plc/by-sys/iogroup*/firmware_version`) — the
digits are **hex**, so "6.28" is `0x0628`, and a version like `6.2A` exists in that space and parses
as neither a decimal nor a float. Register 1000 hands us the uint16 directly; keep it that way,
compare integers, and render for humans only at the edge.

Two consequences worth naming:

- **The lowest `minFirmware` across a model's files is its floor.** A board below it means we have no
  definition that claims to describe it: refuse to run, naming the board's version and the oldest
  variant we hold. That subsumes the startup floor check research/02 §6 and research/04 lesson 35
  propose separately, so it is one mechanism rather than two (RD-6).
- **Ordering at handshake matters.** Read 1000/1003/1004 first, resolve the variant from 1000, *then*
  run §2.1's identity and census checks against the file that was selected. Checking a census before
  knowing which variant applies would assert against the wrong expectations.

### 2.3 One address space: section-local, as EVOK uses

The register-map CSVs give two columns, `Via Unit 0` and `Via Unit N`. **Definitions carry
section-local (`Via Unit N`) addresses only** — the space EVOK already uses, so our generated files and
the stock ones describe the same numbers and can be diffed against each other, and one board type gets
one definition regardless of which slot it occupies. That is what makes `identifies.boardCodes`
coherent.

For the record, since it is not written down anywhere else: EVOK addresses each section at its own unit
id — `autogen.yaml` emits `slave-id: 1, 2, 3` with `model: "00"` / `"13"` (research/03 §2) and the
matching definition files start at register 0. Unipi 1.1's `slave-ids: [0]` is not a counterexample: it
has no sections and no board firmware, so unit 0 is simply its own address (research/02 §12).

The aggregate space is therefore **driver-level addressing, not definition data**: one offset inside the
single audited address function (RC-17), never a second column in 40 files.

```
viaUnit0 = local + 100 × (N − 1)
```

Measured across every 2- and 3-section Neuron, Axon and Patron model in the corpus, and it applies to
coils and to the 1000-block alike — section 2's Firmware Version sits at 1100.

It is also **lossy**, which is why it stays out of the definitions: on the L527's section 1, 14 of 98
registers have no unit-0 address at all — local 100, 500–516 and the 2000 reserved range, the ones that
would collide with the next section's base. Exactly one is `Basic`: local 504, `RS485 ModBus Timeout`.
A driver in unit-0 mode must refuse those rather than compute a plausible-looking wrong address.

## 3. Blocks — ours, not EVOK's

Block layout is a **performance contract**, not a hardware fact (research/03 §4), and per
research/08 it is one of only three latency levers we have. So we choose it ourselves rather than
inheriting EVOK's, and the loader enforces research/03 §4 rule 2: every multi-register value lies
wholly inside one block with one period.

```yaml
blocks:
  - id: io
    type: holding
    start: 0
    count: 3
    rate: fast              # named rates resolve against config, not hardcoded seconds
  - id: counters
    type: holding
    start: 3
    count: 24
    rate: medium
```

## 4. Features — worked examples

### 4.1 `xS11` — a single-section extension

Real addresses, from `Extension_xS11-Registers-group-1.csv` and `-Coils-group-1.csv`:

```yaml
features:
  - kind: DI
    count: 12
    eventable: true
    value:
      reg:  { addr: 0, encoding: bool, bitOffset: 0 }   # register 0, bits 0–11
      coil: 13                                          # same bits as coils 13–24
    counter:
      reg:  { addr: 3, encoding: uint32 }               # 2 registers ⇒ stride 2
    debounce:
      reg:  { addr: 1010, encoding: uint16 }
      unit: us
      scale: 100                                        # register counts 100 µs steps
    directSwitch:                                       # each exists as a register bit and as a coil
      enable:
        reg:  { addr: 1022, encoding: bool, bitOffset: 0 }
        coil: 1007
      polarity:
        reg:  { addr: 1023, encoding: bool, bitOffset: 0 }
        coil: 1019
      toggle:
        reg:  { addr: 1024, encoding: bool, bitOffset: 0 }
        coil: 1031

  - kind: RO
    count: 13
    eventable: true
    value:
      reg:  { addr: 1, encoding: bool, bitOffset: 0 }   # readback, register 1 bits 0–12
      coil: 0                                           # actuation, coils 0–12

  - kind: WD
    count: 1
    value:
      reg:  { addr: 2, encoding: uint16 }               # "Group MasterWatchDog (MWD) Status"
```

Four things the format does that EVOK's cannot:

1. **Bit position is explicit** (`bit` + `bitStride`) instead of implied by `1 << (i % 16)`. The bank
   stride is then derived by the one audited address function (RC-17), and the generated tables of
   ADR-0012 assert it. This is the fix for finding 1.1 at the format level, not the code level.
2. **One signal, keyed by access path.** A field is a dictionary: an optional `reg`, an optional `coil`,
   at least one of them, plus whatever attributes that field needs. Uniqueness is structural — a YAML
   key cannot repeat, so "at most one register and one coil" needs no validation rule and no ordering
   convention. The driver reads through the **register**, since one transaction covers twelve channels
   (the performance contract of §3), and writes through the **coil** when one exists, because writing a
   single channel through a bit-mapped register is a read-modify-write across all twelve and two
   concurrent single-channel writes clobber each other. EVOK's `val_reg` + `val_coil` are separate fields
   with no stated relationship, which is what let `_01…_12` read the right register while writing coils
   116–127.

   An address is either an object or, when nothing but the address is needed, the bare number:
   `coil: 13` means `coil: { addr: 13 }`.
3. **`eventable` is per feature**, declared rather than inferred.
4. **Register count comes from `encoding`, not from a hand-written width.** The closed encoding set maps
   1:1 onto the corpus's own `Data Type` column — `uint16` ← `Word`, `uint32` ← `DWord`,
   `float32` ← `Real`, and `bool` + `bitOffset` ← `MixedBits` with a `Start Bit Nr.` — so the generator
   transcribes rather than interprets. Note `encoding` describes the **channel's value**, not the
   register's storage class: the register holding twelve DIs is `MixedBits`, but each channel is a `bool`.

**No `access` field.** Writability follows from `kind`, which is a closed enum in `@evok-node/messaging`
(ADR-0003) — `DI` and `AI` are read-only, `RO`/`DO`/`LED`/`AO` are writable — so a definition cannot
contradict it or drift from it. The interesting case confirms the rule rather than breaking it: the DI's
coil mirror is read-only in the map even though coils are normally writable, and no write can ever reach
it because `DI` itself is read-only.

**Every stride is derived from `encoding`; omitting it means "derive".** `uint32` is two registers, so
consecutive channels sit two apart; `uint16` one; `bool` one bit, which is what makes a separate
`bitStride` unnecessary; a coil is one bit, so `coilStride` defaults to 1. No model in the corpus needs an
override yet, but an explicit `stride` / `bitStride` / `coilStride` stays available for one that pads.
ADR-0012's generated tables assert the resolved address per channel, so a wrong derivation fails CI
rather than a relay.

**Every field has the same shape, and that includes `mode`.** A feature is `kind`, `count`, `eventable`,
and a set of named fields — `value`, `counter`, `debounce`, `duty`, `prescaler`, `mode` — each of which is
`{ reg?, coil?, …attributes }`. Field-specific semantics are siblings of the addresses rather than buried
inside them, so `debounce` carries `unit` + `scale`, `mode` carries `options`, and nothing needs a wrapper.
`mode` stops being a special case: it is a field with a register and an `options` attribute.

**Scaling is `unit` + `scale`.** The debounce register counts 100 µs steps, so `unit: us, scale: 100`,
drawing on the same `unit` vocabulary the mode options already use — `V`, `mA`, `ohm`, `none`, plus
`us`/`ms`. A key naming its own target unit would need a new key per unit (`scaleToUs`, `scaleToMs`,
`scaleToOhm`) where this needs none, and a plain `scale: 100` avoids a wrapper level that carries nothing.

**`encoding` is mandatory on a register address, with no default.** A default would mean a generator that
drops the field reads half of every `float32` and `uint32` value while being silently right on the majority
of fields that *are* `uint16`, so nothing would catch it — and ADR-0012's generated tables assert addresses,
not widths, so CI would not either. This is ADR-0003's reasoning for `effect` (RC-29): an author can
misdeclare a field but cannot omit it. Coils carry no `encoding`: a coil is one bit by construction.

Note the DirectSwitch base differs per model — 1022/1023/1024 on the xS11, 1014/1015/1016 on the xS51, and
1016/1017/1018 in the published doc example that matches neither (research/01 finding 7). All three xS11
registers are confirmed against `Extension_xS11-Registers-group-1.csv`. One more reason the maps are the
source and the docs are not.

### 4.2 Board `00` — the Brain, and per-channel modes

Board code `00` is the controller's own section 1. Addresses below are from
`Patron_S107-Registers-section-1.csv` and `-Coils-section-1.csv`. Worth knowing before reading it: the
**Neuron S103 and Patron S107 section-1 maps are identical** in every `Basic` row except four extra
`Storage` registers on the Neuron, so one definition genuinely serves both families — which is why
EVOK ships a single `00.yaml` and why `identifies.models` is a list.

```yaml
id: modbus/unipi/brain-00
identifies:
  models: ["S103", "S107", "M103", "M203", "L203", …]   # every controller whose section 1 is a Brain
  boardCodes: ["00"]

census: { di: 4, do: 4, ai: 1, ao: 1 }

features:
  - kind: DI
    count: 4
    eventable: true
    value:
      reg:  { addr: 0, encoding: bool, bitOffset: 0 }
      coil: 4
    counter:
      reg:  { addr: 8, encoding: uint32 }

  - kind: DO
    count: 4
    eventable: true
    value:
      reg:  { addr: 1, encoding: bool, bitOffset: 0 }
      coil: 0
    pwm:
      duty:
        reg: { addr: 16, encoding: uint16 }
      prescaler:
        reg: { addr: 1017, encoding: uint16, perSection: true }
      cycle:
        reg: { addr: 1018, encoding: uint16, perSection: true }

  - kind: LED
    count: 4
    value:
      reg:  { addr: 20, encoding: bool, bitOffset: 0 }
      coil: 8

  - kind: AI
    count: 1
    eventable: true
    value:
      reg: { addr: 3002, encoding: float32 }               # CSV "Real" ⇒ 2 registers
    mode:
      reg: { addr: 1024, encoding: uint16 }                # "Analog Input Configuration (U/I)"
      options: [ … ]                                      # ⚠ values not in the CSVs — see below

  - kind: AO
    count: 1
    value:
      reg: { addr: 3000, encoding: float32 }
    mode:
      reg: { addr: 1019, encoding: uint16 }                # "…Configuration (U/I/R-measure)"
      options: [ … ]                                      # ⚠ values not in the CSVs — see below
```

**Modelling per-channel mode sets.** The requirement is research/06 §2.7: on the Edge the mode enum is
per model *and* per channel — 0–10 V on AI1–3, 0–2.5 V on AI2–3, 4–20 mA on AI2–3, 90–2000 Ω on AI4–5
only. Proposed shape, with the channel restriction living on the **option** rather than on the channel:

```yaml
  - kind: AI
    count: 5
    mode:
      reg: { addr: <base>, encoding: uint16 }
      default: 0
      options:                                                    # mandatory, non-empty
        - { code: 0, unit: none }
        - { code: 1, unit: V,   range: [0, 10] }                   # no `channels` ⇒ all of them
        - { code: 2, unit: V,   range: [0, 2.5],   channels: [2, 3] }
        - { code: 3, unit: mA,  range: [4, 20],    channels: [2, 3] }
        - { code: 4, unit: ohm, range: [90, 2000], channels: [4, 5], conversionTime: 100ms }
```

An option is `code`, `unit`, `range`, and optionally `channels`. Notes on each:

- **`options` is mandatory and non-empty whenever `mode` is present.** There is no placeholder value and
  no third state: either we know the enum and the feature offers mode switching, or `mode` is absent and
  it does not. A model whose enum we have not sourced is a definition we cannot write yet.
- **`unit` from a closed set** — `V`, `mA`, `ohm`, `none` — living in `@evok-node/messaging` beside the
  other closed enums (ADR-0003). `none` is the off/disabled code, which keeps every option the same
  shape rather than special-casing code 0.
- **`range` is a numeric pair, not a string.** `[0, 10]` rather than `"0..10V"`, because the driver can
  then reject an out-of-range AO write against the *currently active* mode. A string range cannot be
  checked, only displayed.
- **`channels` restricts the option, not the channel.** It is how the hardware documents it, it keeps a
  uniform device short — omit it and every channel gets the option — and it does not repeat the enum five
  times. The inverse shape carries identical information at five times the size. A mode write for a
  channel not listed is refused, in the same spirit as §2.1's census.
- **`code` is separated from meaning.** `code` is what goes in the register; `unit` + `range` is what we
  expose. The compat surface projects its own EVOK mode strings through its own table, so no EVOK
  vocabulary enters the definition (G-3, ADR-0003).
- **`conversionTime` hangs off the option**, since it is the resistance mode that is slow, not the
  channel. That is the "conversion-time hints for resistance AI" ADR-0007 wanted.

**The `BAO` type disappears.** EVOK needs a distinct `BAO` feature for the Brain's AO because that AO
can also measure resistance (`val_reg` + `mode_reg` + `res_val_reg`). Here it is an ordinary `AO` whose
options happen to include `resistance` — register 1019 is literally
"Analog Output Configuration (U/I/**R-measure**)". One less feature kind, and the special case becomes
data.

**`perSection: true` is an attribute of the address**, not a container. Section and group are the same
thing: research/06 §2 verified that each model's `-section-N` and `-group-N` exports are **byte-identical
except** that "Section MasterWatchDog" is spelled "Group MasterWatchDog" — pure terminology, no data
difference. `section` is already the house word (CLAUDE.md, G-5, ADR-0001), and an extension is one
section, so `perSection` reads correctly on an xS11 too: the setting covers the whole device.

The alternative, `stride: 0`, is arithmetically honest — `reg + i × stride` then resolves every channel
to the same register — but it puts four channels on one address, which is precisely the shape RC-18's
fatal-on-duplicate-registration exists to catch. We would be special-casing the check that protects us
from the worst bug in the corpus, and it is indistinguishable from a generator emitting a wrong stride.

One implementation consequence: a `perSection` address registers **one** endpoint, not `count` of them,
so RC-18 must see it as one. This is a real distinction rather than tidiness — EVOK puts `pwm_ps_reg`
and `pwm_c_reg` in the feature block beside per-channel `pwm_reg`, so an API built on it reports success
for a request that silently moved three other outputs.

**⚠ The mode enums are not in the CSVs.** Patron/Neuron/Axon exports carry the mode *register* (1019,
1024) and no legal values. Only the XLSX families — Edge and Unipi 1.1 — ship a `Description` sheet with
enumerations (research/06 §2.7, §2.8). So for every CSV-only model the values must come from EVOK's
shipped `hw_definitions` `modes{}` or from measurement on the rig, which is why the capture trip's copy
of the stock definitions still matters even though we never read them at runtime.

**And omitting `mode` is not a way out.** EVOK's `00.yaml` declares `modes` and its API exposes AI/AO
mode switching, so shipping board `00` without the enum is a compat regression, which G-3 forbids. The
elided `options` above is therefore a **blocker on this model**, not a documented degradation — the values
have to be sourced before `00` ships. That is what makes open question 1 a decision rather than a
preference.

## 5. How the definitions get written, and what is still open

### 5.1 Produced once, by agent, from two sources — then reviewed and measured

**Decision.** The definitions are a **one-time transcription**, done by an agent from **both** the
register-map CSVs *and* EVOK's shipped `hw_definitions`. No generator script. Tomas reviews the result by
hand, and the rig tests every model we physically have.

Why two sources rather than the maps alone: the CSVs carry addresses but **not the AI/AO mode enum
values** (§4.2), and EVOK's `modes{}` is the only place those exist for CSV-only families. Since G-3 makes
the enums mandatory — EVOK exposes AI/AO mode switching on board `00`, so shipping that model without them
is a compat regression — the stock definitions are a **prerequisite**, not a cross-check. Board `00` cannot
be written before the capture trip retrieves them.

**The disagreements are the valuable output.** Two independent descriptions of the same hardware, both
from Unipi, will not match everywhere — research/01 finding 7 already caught the published DI example
contradicting the real xS51 map. The agent must **report every disagreement between a CSV and the
corresponding stock definition rather than silently pick one**, and each one gets resolved on the rig where
we own the board, or recorded as unverified where we do not. That list is likely to name real upstream
defects.

**What replaces the CI drift check.** ADR-0012's address tables stay exactly as they are — generated by
script from the CSV corpus, re-run in CI. They now serve a second purpose: CI asserts that every address a
*definition* resolves matches the table derived independently from the map. So the definitions are
hand-maintained source with an automated equivalence check against a script-generated artefact, which is
the safety property the drift check was for. Two derivations of the same facts have to agree.

Consequences to accept up front:

- **A shared blind spot remains**: both derivations read the same CSVs, so a wrong CSV passes both.
  ADR-0012 already records this ("the corpus becomes ground truth"); EVOK's definitions narrow it, since a
  map error that the stock definition does not share shows up as a disagreement.
- **No regeneration path.** When Unipi ships a new model or corrects a map, someone repeats the exercise.
  Mitigation: check in the procedure — the prompt, the source list, the review checklist — so it is
  repeatable rather than remembered. That is the substitute for a script, and it costs almost nothing now.
- **Hand review is the acceptance gate**, so the output has to be reviewable: one model per file, stable key
  order, and `provenance` citing the CSV rows and the stock definition each feature came from. Optimising
  for reviewability is the house rule (CLAUDE.md, RG-5).
- **The rig covers what we own, not everything.** "All models on the rig" means all models we have; ADR-0012
  exists precisely because most of the supported set cannot be bought. Everything else rests on the
  equivalence check plus the §2.1 census refusal at runtime.

### 5.2 Still open

1. **Volatile configuration.** Unipi 1.1's Description sheet says configuration is not persisted and
   must be re-applied on every power-on (research/06 §2.8). Does the definition declare
   `reapplyOnBoot: true` per feature, or is that driver policy?
Settled: `/etc/evok-node/autogen.yaml` lives in the config root alongside `config.yaml`, as EVOK's
did. It is written by our `run.d` script and never by the daemon, so G-5's "never the daemon" clause
holds. G-5's platform-facts row is what needs correcting, and it needs more than wording — see §8.

## 6. The corpus — all of it, in one pass

**No staging.** A partial corpus is a daemon that refuses to run on hardware it does not describe, so
"first models" is not a useful milestone: every model is written in the §5.1 pass.

That is more tractable than the map corpus suggests, because **definitions are keyed by board type, not by
controller.** The maps hold 54 model directories and 10 standalone files — 18 Axon, 14 Neuron, 10 Patron, 6
extension directories plus 4 extension PDFs, 4 Edge, 2 Unipi 1.1 — but a Neuron L523's three sections are
boards `00`, `13`, `13`. Collapsed, the corpus is roughly:

| group | definitions |
|---|---|
| controller board types | `00`, `01`, `07`, `08`, `09`, `0A`, `0F`, `13` |
| extensions | `xS10`, `xS11`, `xS30`, `xS40`, `xS50`, `xS51`, `xS52`, `xS53`, `xS54`, `xG18` |
| Edge | `E410`–`E413` |
| legacy and cards | `UNIPI11`, `UNIPI11LITE`, `EMO-R8`, Iris card models |
| sensors and generic | `IAQ-TH`, `IAQ-THC`, `CUSTOM_MODBUS_DEVICE` |

Around thirty files, not sixty. Note the last two groups exist **only** in EVOK's `hw_definitions` — no
register map covers them — which is the second reason §5.1 needs both sources rather than the maps alone.

**Two families are already unblocked.** Edge and Unipi 1.1 ship XLSX `Description` sheets carrying the mode
enumerations and factory defaults the CSV exports drop (research/06 §2.7, §2.8), so their definitions can be
written now, without waiting for the capture trip. Everything CSV-only waits on the stock `modes{}`.

Which models to review hardest, and where the rig earns its keep:

| model | what it stresses | measurable |
|---|---|---|
| `xS11` | bit-mapped DI/RO, DI counters, DirectSwitch as register *and* coil | yes |
| `13` (E4AI4AO4DI5RO) | AI + AO mode registers, the `BAO` resistance case | yes, L527 |
| `00` | every feature kind at once — DI, DO, PWM, LED, AI, AO | yes |
| `E410` | per-channel mode enums at their worst — 4–20 mA and 90–2000 Ω on some channels only | not yet |
| `UNIPI11` | unit-0 addressing, port 50200, volatile config (§5.2) | no |
| `07` / `0A` | the discontinued high-density boards — 28 RO, 30 DI, the bank arithmetic | never (ADR-0012) |

## 7. Where `autogen.yaml` comes from

One generator, three entry points, no hard dependency on any Unipi package:

| entry point | when | inputs |
|---|---|---|
| our `run.d` plugin script | os-configurator detects a hardware change, early boot | env vars it sets |
| our `postinst` | install and upgrade | self-read |
| daemon start | fingerprint mismatch, or file absent | self-read |

The hook alone is insufficient: `run-parts` fires **only** when os-configurator detects a change, so a
fresh `apt install` with unchanged hardware would never generate anything. Hence `postinst`. And
`postinst` must not call `os-configurator -f` — that tool may reboot the machine, which is what
ADR-0006 already refused to do during `apt install`.

Because `autogen: true` supplies the transport as well as the devices, the generator has to resolve
the onboard endpoint itself: `/etc/default/unipitcp`'s `LISTEN_PORT` and `LISTEN_IP`, defaulting to
`127.0.0.1:502`, and `50200` with unit-id 0 on Unipi 1.1 — the same resolution evok's script performs.

Env vars are authoritative when present, but not sufficient alone: evok's own script shells out to
`unipiid card_description.<slot>` for Iris cards, because `CARDS` carries only `<code>__<slot>`. The
self-read path prefers `/run/unipi-plc/unipi-id/` over the `unipiid` binary, so the `unipi-os-configurator`
package is an opportunity, never a requirement.

**Two hook directories to handle:** upstream's README documents `/usr/lib/unipi/run.d`; Debian 12
builds have been seen with `/opt/unipi/os-configurator/run.d`. `postinst` installs into whichever
exists and skips silently if neither does — the standalone path still works.

Inventory knowledge we own outright, replacing what evok hardcodes in `60-evok-autogen.sh`: the
product-id → ordered board-code table (~40 entries), and the family-code map
(`1: UNIPI1, 2: Gate, 3: Neuron, 6: CM40, 7: Patron, 15: Iris`). Both become model descriptors in
`hw-definitions`. Traps in the original not to inherit: string-slicing `UNIPI_PRODUCT_ID` for the
family code, a bare `except` that prints "Device not recognized!" and exits 0, and silently dropping
an Iris card whose model has no definition.
