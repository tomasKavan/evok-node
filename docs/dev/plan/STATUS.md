# Status

**Updated:** 2026-09-26 · **Milestone:** [M3 — development documentation](roadmap.md) ·
**Version:** unreleased

!! Present state only. What changed and when is what git is for; milestone sequence is in [`roadmap.md`](roadmap.md).

**No implementation code exists.** Every package entrypoint is a placeholder export.

## Done

**M1 — Research.** [`docs/dev/research/`](docs/dev/research/README.md) is the knowledge base: EVOK 3.x API surface, Unipi hardware model, config and hw-definition formats, upstream bug archaeology (29 condensed findings from ~90 raw), client compatibility matrix, latency budget, test-kit design, and the register-map corpus imported and indexed under [`docs/modbus-reg-map/`](../modbus-reg-map/README.md).

**M2 — Repo scaffolding.** npm workspaces over thirteen packages; a shared strict TS base; vitest in workspace mode with coverage floors wired and switched off; `pr` and `main` CI workflows with actions pinned by SHA; eslint with the type-checked config; `dependency-cruiser` carrying the layering DAG. `npm run build`, `test`, `lint` and `layering` each exit 0 — 27 modules, 13 edges, no violations.

## In progress

**M3 — development documentation.** [`docs/dev/design`](/docs/dev/README.md), sections 2 - 6. 
- Root README.md is finalized, TBD at URLs which is uknown at the moment.
- Dev docs README.md is finalized. Documentaiton has rules.
- AGENTS.md has generic rules and some roles defined, but some role's reading paths and instructions for specific roles are yet TBD.
- 02 §4 designed `plugin-sdk` — published types (`ModuleDescriptor`, `ModuleInstance`, `InstanceContext`) and the runtime guard (`isModuleDescriptor`) a plugin author builds against, and that `main` checks a loaded module with. **Not yet scaffolded** — `packages/plugin-sdk` does not exist, and `.dependency-cruiser.cjs` does not yet carry its edges: `main`, `driver-onboard`, `driver-extension`, `api-nextgen`, `api-compat` and `driver-kit` all depend on it. Coder work, not started; this is a note so it isn't lost before then.
- 07 designed the Modbus transport engine (`ModbusTransport`), its eight raw pass-through endpoints, and the standalone driver wrapping them. **Package rename pending** — `01 §11`'s table now names it `modbus-kit`, but `packages/modbus` still exists on disk under the old name; the rename needs to land in the same change as `.dependency-cruiser.cjs`. That same file also needs a new edge, `modbus-kit` → `driver-kit`, for `CallOutcome` (05a §3.5) — not yet in `WORKSPACE_DEPS`. Coder work, not started; this is a note so it isn't lost before then.
- 05 split into `05-Drivers` (the generic driver contract) and `05a-Driver-kit` (the `driver-kit` package) — cross-references in 02/03/06/07 updated to point at 05a where the content moved.
- 11 designed the system driver (`driver-system`) — host/version facts, loads, network, a process snapshot, and additive log reads. Read-only in v1; no write endpoint exists on any driver yet, so a settable label and any restart/reboot method are left open.
- 12 designed the DALI driver (`driver-dali`) — pluggable `dali-controller` backends (manifest kind, mirroring 07a's binder/handshake pattern), the built-in `dali-foxtron-ASCII` controller, raw bus access, the stored gear/group model and its cache strategy (deliberately sparse — see 12 §9), and the short-address commissioning workflow. **New package `line-kit` introduced** — a protocol-agnostic serial/TCP byte transport shared with `modbus-kit`; 07 §2/§3 amended so Modbus RTU builds on it instead of wrapping `serialport` a second time. **Not yet scaffolded** — `packages/driver-dali` and `packages/line-kit` don't exist yet, and `.dependency-cruiser.cjs` doesn't carry their edges. Coder work, not started; this is a note so it isn't lost before then.
- 10 designed the 1-Wire driver (`driver-onewire`) — `owserver` only, no `/sys/bus/w1`; xG18 excluded as a plain RTU extension. No `devices:` in config: sensors are discovered (`discover`), then explicitly adopted (`store`/`remove`) into `driver-kv-store`'s namespace for this instance, per 05a §3.6. Chip identification reuses research/13's definition envelope with `identifies.familyCode`; features resolve to existing generic kinds (`unipi.temp`, `unipi.humidity`, `unipi.ai`) rather than new ones. `autogen.py` now emits two files, `autogen-onboard.yaml` and `autogen-onewire.yaml` — 08 §3 amended accordingly (not yet edited into 08 itself). Scan loop reuses 04 §5.2's `scheduleRepeating` and 07a's cache/`readAt`/`stale` pattern; auto-throttles and rate-limit-logs rather than overrunning. **Not yet scaffolded** — `packages/driver-onewire` does not exist, nor does the `onewire/` subtree under `packages/hw-definitions/definitions/`. Coder work, not started; this is a note so it isn't lost before then.

## Next

**Not yet defined.** M3 defines it. No milestone numbers past M3 exist, and none should be
invented.
