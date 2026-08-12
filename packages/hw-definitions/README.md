# `@evok-node/hw-definitions`

What the hardware *is* — `autogen.yaml`, `hw_definitions/*.yaml`, our overlays, and the generated
`(model, section, kind, channel) → (register, bitOffset, coil)` tables.

The one audited address function lives here, with the `/16` bank stride and `%16` mask in exactly one
place (RC-17). Frozen per load, not once per process (RC-4). A multi-register value must lie wholly
inside one block at one frequency, checked at load (RC-19).

**Must not depend on:** any driver, any api, `modbus`, `main`. Loaded and validated by `main`; the types
and tables are consumed by drivers.
