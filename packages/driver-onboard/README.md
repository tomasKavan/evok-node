# `@evok-node/driver-onboard`

The controller's own I/O — sections 1..3 — reached by Modbus TCP to `unipitcp` on `127.0.0.1:502`. EVOK
never speaks SPI and neither do we.

Named `onboard` rather than `plc` because the whole box is the PLC and extensions attach to it, so "the
PLC driver" would read as covering everything (ADR-0002).

Registration is declarative from config; reachability is a state, retried forever. A device absent at
startup is still registered — finding 2.1.

**Must not depend on:** any api, `main`, another driver.
