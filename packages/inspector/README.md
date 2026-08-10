# `@evok-node/inspector`

Web UI: status display with filtering, sorting and search, control, configuration, and status
rendered on PLC layout drawings. A read-only status view lands after M4; the full SPA replacing
`evok-web-jq` is post-1.0.

**Must not depend on:** `core`, `modbus`, `hw-definitions`, `server`, `simulator`, `rig`.
`CLAUDE.md` rule 1 names this package explicitly: public API only. Depends on `protocol`.

The constraint is the point, not an inconvenience — a UI that can reach into core stops being proof
that the API is sufficient, and the API being sufficient is what lets anyone else build a UI. How
much of this ships inside 1.0 is an open question in [docs/GOALS.md](../../docs/GOALS.md) §Open.
