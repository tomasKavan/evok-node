# evok-node design

## Why replace EVOK rather than patch it

EVOK works, and patching it would have been cheaper than replacing it. We didn't, because its known defects ([research/04](../../research/04-known-bugs-and-lessons.md), 29 findings) are dominated by **state** problems, not wrong algorithms: discovery that runs once and misses a slave powered on later, a register cache shared between two slaves, one dead bus stalling every client, a 32-bit counter torn across two register reads. Patches narrow one symptom while the architecture keeps generating new ones — a decade of EVOK's commit history bears that out.

So we inherit neither the design nor the interface. Everything is ours to shape so these failures aren't representable in the first place.

## Goals

EVOK is a load-bearing part of Unipi's FOSS stack. It is also a decade of accumulated fixes with a long tail of open, known defects and limited maintainer attention. **evok-node replaces it as the PLC runtime on Unipi hardware, without the known defects.** It does not keep EVOK's API: clients use evok-node's own APIs.

EVOK is very low-level and narrow focused system. It's focus is on Unipi HW (PLCs, extensions and some sensors). Everything else is not supported must be drived by other libraries and daemons. If you connect M-Bus device or DALI gate, you'll endup with setting up many channels and openning multiple ports. **evok-node offers comfortable way how all devices connected to Unipi PLC can be plugged and offered thru one channel**.

Reliability and separation is big topic in evok-node. Modularized architecture with possibility to dedicate compute heavy or foreign drivers or API to separate threads and processes makes sure the API won't crash or stale. Considering drivers as in memory copy of HW state helps with query reliability.

**Home automation is built in.** The home driver assembles home devices — lights, covers, sensors — from other drivers' endpoints or from Matter devices, and runs rules between them. They are exposed through the Home API, the Home UI and a Matter bridge.

Integrated web interface is here to determine holistic state of connected devices, including configuration and logs, and provide simple means to configure devices without need to touch CLI.

A mobile/desktop shell app hosts the inspector and the home control UI, for several users and several PLCs.

evok-node publishes nodejs client package allowing developers to consume the WS API.

### Hardware scope

- **1.0 supports Patron, Neuron, Unipi 1.1, Extensions, Gate, 1W sensors and Air quality sensor.** Same as EVOK 3.
- **Edge is a fast follow after 1.0**
- **Axon is dropped** — support was discontinued on EVOK side. 
- **`Iris` is disregarded** - we don't know, what it is.

### Replacing EVOK

`evok-node` installs instead of `evok` — the packages conflict. EVOK configuration is not migrated: autogen ([basics/01 §3.1](../basics/01-Package.md)) generates the hardware configuration, the rest is configured again.

### Non-goals

- EVOK API compatibility (any version) and EVOK config migration.
- A free-form flow editor (Node-RED style). Rules are composed from predefined rule kinds (12b) in the UI, not wired as flows.
- Node-RED nodes.
- IEC 61131-3 programming (ladder, ST) — Mervis' domain.
- Timeseries storage of readings.
