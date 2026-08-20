# 11 — System driver

> **Memo, not content.** What belongs in this file, and what it gets written from. Written during
> [M3](../plan/roadmap.md); do not implement against a memo.

**Job:** host facts and logs, exposed through the same driver contract as hardware.

**Covers**

- **Why this is a driver.** It acts, it holds state, and making it a special case inside `main` or the
  APIs is how the two-kinds rule rots.
- **Logs:** which ones, how they are read and tailed without blocking, retention, and what is exposed
  to whom.
- **TBD — system configuration and identity.** Which host facts we expose (versions, uptime, network,
  firmware, disk) and which are readable versus settable. Filesystem access and process execution live
  here, which makes the **security surface** the interesting part of this file rather than an aside.
- **Permissions.** This driver can do more damage than a relay. State the boundary explicitly, and
  what an API is allowed to ask it for.

**Inputs:** research/01 (EVOK's system endpoints) · [`GOALS.md`](../GOALS.md) non-goals

**Open:** most of it. Post-1.0 unless the compat surface forces part of it earlier — check research/01
for what EVOK exposes that a client might already depend on.
