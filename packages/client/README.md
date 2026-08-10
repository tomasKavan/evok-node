# `@evok-node/client`

First-party TypeScript client for the evok-node API: typed calls, typed events, and the same zod
schemas the server validates against, so a shape change breaks the client at compile time rather
than in the field.

Lands after M4, since it consumes the public API and would otherwise be built against a moving
target.

**Must not depend on:** anything but `protocol`. Not `core`, not `server`, not `modbus` — a client
that reaches into the daemon's internals stops being a test of the public surface, which is most of
what it is for. It must run in a browser and in Node, so nothing OS-specific either.
