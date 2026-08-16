# `@evok-node/main`

Parses config, validates it, spawns and supervises drivers and APIs, handles reload. **On no request
path, ever.**

What it validates is resource exclusivity, because nothing else sees enough config to: two drivers on one
transport endpoint, two APIs on one listen port, an api's `drivers:` list naming a driver that does not
exist. All at parse time, before anything binds — which is finding 2.7's fix.

Fatal at boot, non-fatal on reload: at boot it exits non-zero with the reason; on reload it keeps
running the current configuration and reports the rejected one.

**Must not statically import:** any concrete driver or api. They are resolved from config through a
manifest — without that, `main` has an import edge to everything and "not a conduit" is unenforceable.
Checked in `.dependency-cruiser.cjs`.
