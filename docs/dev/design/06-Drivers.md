# 06 — Drivers

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** what every driver must be, whatever it talks to. The concepts 07–12 specialise rather than
restate.

**Covers**

- **The three obligations: do not block · do not throw · hold the device model in memory.** Each
  needs its own paragraph saying what it means at the edges, because each is easy to honour in spirit
  and violate in practice.
- **Why in-memory state is the driver's job and not the API's.** One owner per truth, and the read
  path never touches the bus.
- **"No value yet" is not "value 0".** Clients depend on the distinction; it has to survive the whole
  way out through 03 to 14 and 15.
- **The scan loop as a contract:** cadence, prioritisation, write-versus-read ordering, and what is
  allowed to fall behind first under load.
- **Failure model:** degradation levels, what is reported when a device is unreachable, circuit
  breaking, recovery. Fatal is reserved — enumerate exactly what qualifies.
- **Lifecycle:** construct → configure → handshake/identify → run → reload → drain → stop.
- **Introspection is a driver responsibility**, and driver-qualified addressing is its consequence.
- **Writes:** acknowledgement semantics, idempotence, and precisely what the caller is promised.

**Inputs:** research/05 · research/08 · [`rules/packages/drivers.md`](../rules/packages/drivers.md)
(RPG-DRV-\*) · to_revision/0001, 0002
