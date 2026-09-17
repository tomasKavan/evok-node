# `@evok-node/hw-definitions`

What the hardware *is* — **our** hardware definitions, the product-id → board-code model descriptors, and
the generated `(model, section, kind, channel) → (register, bitOffset, coil)` tables.

Definitions are ours and ship with this package; nothing is read from `/etc/evok` at runtime, and no Unipi
data package is a dependency. Definition ids are paths — `modbus/unipi/xs11` — and the operator's
own live under `/etc/evok-node/hw_definitions/custom/`, a disjoint namespace with no merge. Format:
[research/13](../../docs/research/13-config-and-hw-definition-format.md).

The one audited address function lives here, with the `/16` bank stride and `%16` mask in exactly one
place. Frozen per load, not once per process (RCD-4). A multi-register value must lie wholly
inside one block at one frequency, checked at load (RPG-DMB-1).

**Must not depend on:** any driver, any api, `modbus`, `main`. Loaded and validated by `main`; the types
and tables are consumed by drivers.
