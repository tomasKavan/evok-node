# ADR-0002 — Internal addresses are driver-qualified, and the tail belongs to the driver

- **Status:** Proposal, **not in force** — the set was dissolved 2026-08-18, see [README](README.md). Was: Accepted.
- **Date:** 2026-08-12
- **Refs:** docs/research/12-modularisation.md · docs/research/01-evok-api-surface.md §2 · ADR-0001

## Context

With N drivers instead of one core, an address must say which driver owns it. EVOK's flat namespace is
qualified already, but by a different key: circuits are `<device_name>_<NN>`, where `<device_name>` is
the config key — the section number for onboard I/O (`2_01`), the extension's name for extensions
(`xS11_02`). 1-Wire has no `device_name` at all; the circuit *is* the ROM id. EVOK also keeps `dev`
and `circuit` as separate fields, so `di_2_01` is not an EVOK identifier.

## Decision

**`<driverId>:<driver-defined tail>`**, case-sensitive, e.g. `PLC:DI.2.01`.

- The part before `:` matches a driver id from config. Driver ids are YAML map keys, so uniqueness is
  free, and are constrained to `[A-Za-z0-9_-]+` at parse — an id containing `:` or `.` makes parsing
  ambiguous, and that is unfixable later.
- **Everything after `:` belongs to the driver.** Not a fixed `TYPE.section.channel` grammar: a
  1-Wire tail is a ROM id with no type or section, a system driver's is a path, and a driver may
  answer at more than one level.
- **Convention, not grammar:** a driver exposing relay and digital I/O uses uppercase `DI`, `DO`,
  `RO`, `AI`, `AO`, `LED` in the tail. The messaging layer cannot enforce what it does not parse, so
  the enforceable part lives elsewhere — an endpoint's **type is a closed enum in the introspection
  descriptor** (ADR-0003), where a schema can check it and an exhaustive switch can depend on it.

Routing needs no table: `api-nextgen` resolves a driver by parsing, and uniqueness within a driver is
local to its own address tables (RC-18). Brands `DriverId` and `Address` in RC-1; `Circuit` is
retained for EVOK's `2_01` and is `api-compat`-only.

## Consequences

Makes easy: a driver with an address shape nobody anticipated; routing without lookup; `main` needing
no global namespace, so startup is single-phase (ADR-0001).

Makes hard: projection to EVOK's flat space now needs a real table rather than a string transform.
`api-compat` derives `(dev, circuit)` from `(driver type, endpoint type, tail)`, and Unipi drivers
accept one convention for it — the tail must be mechanically projectable (`PLC:DI.2.01` → `2_01`,
`EXT:DI.xS11.02` → `xS11_02`). Non-Unipi drivers carry no such obligation; compat's table simply has
no entry for them.

**Rejected:**

- **A fixed `<driverId>:<TYPE>.<rest>` grammar** with `TYPE` from a closed enum. A system driver's
  `netconf` and a 1-Wire ROM id have no type token, and forcing one is a fiction. The checking was
  kept by moving the enum into the descriptor, which is strictly better: a field can be validated, a
  substring cannot.
- **Case-insensitive internal addresses** — mixed conventions compared deep in the stack is finding
  3.5's failure mode. Case mapping is an explicit step in compat's projection.
- **Deriving compat's `dev` by lowercasing the internal type.** It works for 6 of EVOK's 20 canonical
  device keys and fails on the other 14 (research/01 §2). A shortcut that is right 30 % of the time
  and passes every obvious test is worse than no shortcut. The projection is a table, and an
  asymmetric one: 9 alt-names accepted on input, canonical keys only on output, except 1-Wire sensors
  which emit `temp`.
