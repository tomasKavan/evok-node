# `@evok-node/driver-extension`

Unipi extensions (xS11, xS51, xG18, …) over Modbus RTU. **One instance per RS-485 line** — a driver owns
exactly one transport endpoint, which is what stops two of them contending for `/dev/ttyNS0` (ADR-0008,
G-7).

Owns t3.5 pacing, per-device quarantine and bus scheduling. Backoff must not reset on any single success
— finding 4.2.

**Must not depend on:** any api, `main`, another driver.
