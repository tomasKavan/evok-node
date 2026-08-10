# `@evok-node/hw-definitions`

Unipi model descriptors, our definition overlays, and the generated address tables. Holds the
**single audited address function** — the one place the `/16` bank stride and the `%16` bit mask
exist (`CLAUDE.md` rule 8). Never derive an address from a loop counter anywhere else.

Definitions are validated at load and then frozen: `readonly` types and frozen at runtime, per load
rather than once per process, because continuous re-discovery is the fix for upstream finding 2.1.
Multi-register values must lie wholly inside one register block with one frequency; violating
definitions are rejected rather than repaired.

**Must not depend on:** `core`, `server`, `client`, `inspector`, `simulator`, `modbus`. It describes
where a value lives, and never reads one. Depends on `protocol` only.
