# 10 — 1-Wire driver

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** the 1-Wire bus as a driver like any other.

**Covers**

- **Access path on Unipi OS:** what we read, what owns the bus, and the host configuration that has to
  be right before anything works.
- **Topology:** masters, and the xG18 case where a 1-Wire master arrives *over RTU* — a driver whose
  transport is another driver's problem, or not, and that has to be decided.
- **Discovery.** Sensors arrive and depart at runtime, so **the endpoint set is not static** — the
  first real departure from the Modbus model, and the main reason this file is not a section of 07.
  How discovery reconciles with declared config.
- **Autogen** of endpoints from discovered chips.
- **Chip and data-type plugins:** adding a chip family without touching the driver.
- **Timing reality:** 1-Wire is slow. How the scan loop reflects that without blocking anything else.

**Inputs:** research/02 · research/03 · research/01 (EVOK's 1-Wire surface) · the xG18 map

**Open:** whether devices that are discovered but not configured are exposed by default, and what a
disappeared-but-configured sensor reads as.
