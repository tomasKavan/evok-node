# EMO-R8 — no register map in the source

[`modbus-reg-map/extensions/Extension_EMO-R8.pdf`](../../modbus-reg-map/extensions/Extension_EMO-R8.pdf)
is the Unipi KB page `en:hw:03-unipi11:extension`, saved 2026-08-13. It
**contains no Modbus register map**: no register addresses, no coil addresses, no data types. Two pages,
and page 2 is a single sentence. So no CSV can be derived from it, and none has been invented.

## What it does document

8× Finder 36.11.9.005.4011 relay (250 V~ / 10 A, or 30 V⎓ / 10 A), 2× I²C port, 2.1 mm DC jack needing
5 V⎓ / 0.6 A, and 3 jumpers setting the address. Up to 7 modules on one Unipi 1.1.

**Addressing** — the jumper table, which is the useful part, because it gives the Modbus unit id:

| A2 | A1 | A0 | I²C hex | I²C dec | Modbus unit | note |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0x20 | 32 | 0 | reserved for the relay on Unipi 1.1 itself |
| 0 | 0 | 1 | 0x21 | 33 | 1 | free |
| 0 | 1 | 0 | 0x22 | 34 | 2 | free |
| 0 | 1 | 1 | 0x23 | 35 | 3 | free |
| 1 | 0 | 0 | 0x24 | 36 | 4 | free |
| 1 | 0 | 1 | 0x25 | 37 | 5 | free |
| 1 | 1 | 0 | 0x26 | 38 | 6 | free |
| 1 | 1 | 1 | 0x27 | 39 | 7 | free |

Modbus access needs Unipi Base OS ≥ 12 or Mervis OS ≥ 2.6.5.10, and on GNU/Linux it must be enabled
first — the page points at `/etc/unipi-id/README.md` on the device.

This corroborates `60-evok-autogen.sh`, which emits `{slave-id: <slot>, model: EMO-R8}` for card device
code `0018` on the `UNIPI1` family.

## Where the register map has to come from

Three candidates, in order of preference:

1. **EVOK's shipped `EMO-R8.yaml`** — a capture-trip artefact, and it must exist for EVOK to drive these
   at all. Note it will not be on the Patron build of `evok-unipi-data`; it needs a Unipi 1.1 unit.
2. **A different Unipi KB page or map file** than the one saved here.
3. **Measurement**, if we get an EMO-R8 on the rig.

**Do not assume it matches Unipi 1.1's built-in relays.** [`modbus-reg-map/1_1/unipi-11-modbus-map.xlsx`](../../modbus-reg-map/1_1/unipi-11-modbus-map.xlsx)
documents
8 relay outputs at holding register 1 bits 0–7 and coils 0–7, and an EMO-R8 is also 8 relays — but that
is the map of the *base board* at its own unit id, and nothing in either source says the extension
mirrors it. It is a plausible guess and exactly the kind of plausible guess that drives the wrong relay.
