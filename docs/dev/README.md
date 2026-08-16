# Development documentation

**How evok-node is built, and why it is built that way.** This is what implementation is written
against. Read order and precedence: [`CLAUDE.md`](../../CLAUDE.md).

Every file here is currently a **memo** — a short statement of what belongs in it and what it will be
written from. No design content yet; that is [M3](../plan/roadmap.md), in progress. A memo is not a
decision, so do not implement against one.

## Relation to the other docs

| | Answers |
|---|---|
| [`GOALS.md`](../GOALS.md) | what we are for, and what is out of scope |
| [`rules/`](../rules/) | how we work — code, testing, docs, git |
| **`dev/` (here)** | **how the system is built** |
| [`research/`](../research/README.md) | what EVOK and the hardware actually do |
| [`plan/`](../plan/README.md) | what we do next |

Which of them wins is in [`CLAUDE.md`](../../CLAUDE.md). The part that matters while writing here:
research is the **input**, and a dev doc may **reject, narrow or reinterpret** a finding — that is a
decision rather than an error, but it says so and links the finding, so nobody later "fixes" it back
(RD-8).

Dev docs carry **no rule numbers**; how to cite one is in [`CLAUDE.md`](../../CLAUDE.md), and RD-8 is
the rule for writing them.

The [suspended ADRs](../research/to_revision/README.md) are the main other input. They record
reasoning that mostly still stands but is **not in force**; M3 decides which of them come back.

## Files

Numbered in reading order, not priority. Concepts first, then drivers, then APIs, then tooling.

| | File | Job |
|---|---|---|
| 00 | [Intro](00-Intro.md) | what evok-node is, how it relates to EVOK, how to use these docs |
| 01 | [System architecture](01-System-architecture.md) | main, drivers, APIs, plugin kinds, spawning, the runner |
| 02 | [Configuration](02-Configuration.md) | structure, parsing, validation, reload, resource reservation |
| 03 | [Internal messaging](03-Internal-messaging.md) | the driver↔API contract, introspection, signalling |
| 04 | [Storage kit](04-Storage-kit.md) | persistence available to modules |
| 05 | [Common services](05-Common-services.md) | everything else drivers and APIs may use |
| 06 | [Drivers](06-Drivers.md) | driver concepts common to all of them |
| 07 | [Modbus driver](07-Modbus-driver.md) | the shared Modbus ancestor and the hw-definition format |
| 08 | [Onboard driver](08-Onboard-driver.md) | the controller's own I/O, over TCP to `unipitcp` |
| 09 | [Extension driver](09-Extension-driver.md) | Unipi extensions and accessories over RTU |
| 10 | [1-Wire driver](10-Onewire-driver.md) | the 1-Wire bus, discovery, chip plugins |
| 11 | [System driver](11-System-driver.md) | logs and host facts as a driver |
| 12 | [Driver plugins](12-Plugin-driver.md) | writing a third-party driver |
| 13 | [APIs](13-APIs.md) | API concepts common to all of them |
| 14 | [Compat API](14-Compat-API.md) | the EVOK 3.x surface, done right |
| 15 | [Nextgen API](15-Nextgen-API.md) | our own WS + HTTP surface |
| 16 | [Inspector UI](16-Inspector-UI.md) | the SPA served by nextgen |
| 17 | [Driver plugins in the nextgen API and the UI](17-Plugin-driver-to-Nextgen-API-and-UI.md) | making a plugin driver visible end to end |
| 18 | [API plugins](18-Plugin-API.md) | writing a third-party API |
| 19 | [Simulator](19-Simulator.md) | simulating each component for tests |
| 20 | [Test rig](20-Test-rig.md) | the physical rig, its tooling, and CI |
| 21 | [Tooling and Package](21-Tooling-and-package.md) | helpers tooling and application packaging and distribution |

## Writing these

**RD-8** is the rule; read it before writing a dev doc. Beyond it: RD-1 still applies — the
non-obvious **why**, not the what — and one concern per file. If two files want the same paragraph,
one of them is wrong (RD-6).
