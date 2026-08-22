


-- note: to review & rework

| Package | Purpose |
|---|---|
| [`messaging`](packages/messaging) | the internal driver↔API contract: envelopes, introspection schemas, codecs, deadlines |
| [`hw-definitions`](packages/hw-definitions) | our hardware definitions, model descriptors, generated address tables |
| [`modbus`](packages/modbus) | transport: framing, correlation, timing, circuit breakers |
| [`main`](packages/main) | the daemon: config, validation, spawn, supervise, reload |
| [`driver-kit`](packages/driver-kit) | shared driver runtime: scan loop, reading state, handshake, introspection |
| [`driver-onboard`](packages/driver-onboard) | the controller's own I/O sections, over Modbus TCP |
| [`driver-extension`](packages/driver-extension) | Unipi RTU extensions, one instance per RS-485 line |
| [`api-nextgen`](packages/api-nextgen) | our WebSocket + HTTP surface. Owns its public schema |
| [`api-compat`](packages/api-compat) | the EVOK 3.x surface. Owns the projection table |
| [`simulator`](packages/simulator) | Modbus slave simulator generated from the register-map corpus |
| [`client`](packages/client) | first-party TypeScript client |
| [`ui`](packages/ui) | the web SPA, over the public API only |
| [`rig`](packages/rig) | hardware-rig control service. Private, sysfs only |


**Covers** - also to review, just notes

- **The one-shot migration tool.** Reads `/etc/evok/config.yaml` and `/var/lib/evok/alias.yaml` and
  writes ours. A separate binary, never the daemon; a pure function over two file formats, so it is
  fixture-testable. What it warns about when it cannot represent something, and that it leaves
  `/etc/evok` pristine (`GOALS §The drop-in guarantee`).
- **Debian package and installation.** `Conflicts: evok`, `Depends: nginx`, the `:80` site conflict,
  `postinst`, which `run.d` directory to install into, and rollback. Several of these are facts we do
  not have yet — see Open.
- **The repo toolchain**, and why each piece is load-bearing rather than taste: npm workspaces with
  `tsc -b` project references, Node 24, `dependency-cruiser` as the layering guard, `npm run verify`.
  `to_revision/0013` proposes the set; this file decides it.
- **What is deliberately not here:** the test instruments. `dev/19` and `dev/20` own the simulator and
  the rig, and RT-15 keeps them out of the daemon's dependency graph entirely.

from GOALS.md - to review, probably will go also to user docu

6. **G-7 — evok and evok-node never run at the same time.** Not a policy: two processes cannot both own `/dev/ttyNS0` and connect to the same Modbus TCP server. Startup preflight refuses to start if evok is active or the ttys are held — loudly, and **naming the conflicting unit** — rather than racing for the port and failing unexplainably.

-- from former ADRs

- Using of npm workspaces and @evok-node/ namespace:
**npm workspaces.** No second package manager, no build orchestrator. Thirteen packages under
`packages/`, published as `@evok-node/<name>`; `rig` is `private: true` and never published (RC-11).
Builds are `tsc -b` over the root `tsconfig.json`'s project references.

**The consequence that makes this an ADR rather than a preference:** npm workspaces give every package a
flat `node_modules`, so an import a package never declared resolves anyway. `tsc -b` does not close the
hole either — a cross-package import with no project reference builds green as long as the target's
`dist/` exists, which it does after any earlier build (verified empirically; see the comment at the top of
`.dependency-cruiser.cjs`). So **`dependency-cruiser` is load-bearing, not a nicety**: without it RC-10 is
unenforceable and ADR-0001's "nothing imports `main`" is aspirational. The DAG is stated once, in that
file, which also asserts each `package.json` agrees with it.
