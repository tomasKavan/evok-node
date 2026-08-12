# `@evok-node/hw-definitions`

Unipi model descriptors, our definition overlays, and the generated address tables. Holds the
**single audited address function** — the one place the `/16` bank stride and the `%16` bit mask
exist (RC-17). Never derive an address from a loop counter anywhere else.

Definitions are validated at load and then frozen (RC-4, G-5). Load-time validation is where RC-19
is checked.

**Must not depend on:** `core`, `server`, `client`, `inspector`, `simulator`, `modbus`. It describes
where a value lives, and never reads one. Depends on `protocol` only.
