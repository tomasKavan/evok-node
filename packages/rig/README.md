# `@evok-node/rig`

Hardware-rig control service for tier-1 tests. Runs on the test-host Patron, drives the loopback
wiring through **sysfs only**, and answers `rig reset` and `rig loopback verify`. Private; never
published.

**Must not depend on:** any workspace package, and no Modbus client — RC-11. The
instrument must not share code with what it measures. A rig that used our own transport would report
green when both the rig and the code under test were wrong in the same way, which is the one failure
a hardware test exists to catch.

Wiring lives in `rig.yaml`, with placeholder addresses in the repo; a test that hardcodes a channel
number is a bug. Blocked on the second Patron M527.
