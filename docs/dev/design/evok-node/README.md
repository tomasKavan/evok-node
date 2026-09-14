# evok-node design

## Why replace EVOK rather than patched it

EVOK works, and patching it would have been cheaper than replacing it. We didn't, because its known defects ([research/04](../../research/04-known-bugs-and-lessons.md), 29 findings) are dominated by **state** problems, not wrong algorithms: discovery that runs once and misses a slave powered on later, a register cache shared between two slaves, one dead bus stalling every client, a 32-bit counter torn across two register reads. Patches narrow one symptom while the architecture keeps generating new ones — a decade of EVOK's commit history bears that out.

So we inherit the interface, not the design. Clients can't tell the difference; everything behind the compat API is ours to shape so these failures aren't representable in the first place.

## Goals

EVOK is a load-bearing part of Unipi's FOSS stack. It is also a decade of accumulated fixes with a long tail of open, known defects and limited maintainer attention. **evok-node is a drop-in replacement that addresses the known defects.**

We are offering EVOK's *interface* as a compatibility (compat) api, but we are not inheriting the EVOK *design*. Compat API is first-class citizen, won't be deprecated until EVOK 3 is.

EVOK is very low-level and narrow focused system. It's focus is on Unipi HW (PLCs, extensions and some sensors). Everything else is not supported must be drived by other libraries and daemons. If you connect M-Bus device or DALI gate, you'll endup with setting up many channels and openning multiple ports. **evok-node offers comfortable way how all devices connected to Unipi PLC can be plugged and offered thru one channel**.

Reliability and separation is big topic in evok-node. Modularized architecture with possibility to dedicate compute heavy or foreign drivers or API to separate threads and processes makes sure the API won't crash or stale. Considering drivers as in memory copy of HW state helps with query reliability.

Integrated web interface is here to determine holistic state of connected devices, including configuration and logs, and provide simple means to configure devices without need to touch CLI.

evok-node publishes nodejs client package allowing developers to consume nextgen API.

### Goals for later versions

TBD - ACL and auth on next gen API

### Hardware scope

- **1.0 supports Patron, Neuron, Unipi 1.1, Extensions, Gate, 1W sensors and Air quality sensor.** Same as EVOK 3.
- **Edge is a fast follow after 1.0**
- **Axon is dropped** — support was discontinued on EVOK side. 
- **`Iris` is disregarded** - we don't know, what it is.

### Drop-in replacement

Users have option to convert their current EVOK configuration to evok-node and run compat API with it. It allows very smooth transition from EVOK to evok-node.

### Non-goals

- EVOK v2 compatibility.
- A visual flow editor.
- NodeRED nodes.
- Replacing Mervis, or being a general-purpose PLC runtime.
- Timeseries storage of readings.
