# 01 — System architecture

## 1. Scope

This file states the shape of the daemon: what kinds of component exist, how an instance of one is hosted regardless of where it runs, and the seams that keep those two questions independent of each other. It is deliberately silent on the concrete — how a specific driver polls a specific bus, what a specific api's wire format looks like, how configuration is parsed — which is 02's, 03's, 06's and 13's job, and further down, the numbered files under each. Read this file first; nothing later is allowed to contradict it.

## 2. Two component kinds, no third

Every running piece of evok-node is a **driver**, an **api**, or **main** — and main is not a third kind, it orchestrates the other two and never appears in a request path.

- **A driver owns exactly one transport endpoint** — a bus, a socket, a line, the filesystem, a process-exec surface. It polls or listens, holds the only in-memory copy of what it knows, answers queries from that memory, and describes itself through introspection (§6). System configuration and user data are drivers too: their transport is the filesystem and a database file instead of Modbus, and that is the only difference that matters.
- **An api is a stateless translator** between the internal message bus and one public protocol. It holds no device state and caches no readings. Whatever it does hold — subscriptions, sessions, a schema cache — is rebuilt on restart, never a second copy of what a driver already owns.
- **main parses config, spawns, supervises and reloads** — drivers and apis, not itself. It sits on no request path: no client request and no scan result ever passes through main's own code.

Anything that looks like it needs a third kind is a driver whose transport happens not to be Modbus.

## 3. Placement

Where a driver or an api actually executes is a configuration property of that instance, not a property of its code. Two placements exist:

| Placement | Runs | Default |
|---|---|---|
| `worker_thread` | a Node `worker_thread` | yes |
| `child_process` | a separate OS process | — |

A component's own code is written once and is correct under either; only the runner hosting it (§4) differs. This is possible only because nothing may cross the driver↔api boundary except serialisable data — no callbacks, no class instances, no `Buffer`s, no shared mutable state — and both placements enforce that by construction: each gets its own event loop, sharing none with `main` or with any other instance. Moving a component between the two is therefore a config change, never a rewrite.

There used to be a third placement, `single_thread`, running inside `main`'s own event loop — removed because it could not offer the one guarantee the other two give for free: a module's own bug stays contained to that module. `single_thread` depended on every component sharing that loop honouring non-blocking discipline voluntarily; a single forgotten `await` or an uncaught exception could take down every driver and api at once, `main`'s own orchestration included. `worker_thread` costs a few megabytes of isolate overhead per instance in exchange — measured, not assumed, at roughly 3 MB per instance beyond a shared-heap baseline for a representative dependency load — which is cheap next to that risk.

## 4. The runner

A **runner** is what turns a driver or api module into a running instance: it constructs the module, wires its messaging to whatever channel the chosen placement provides, and enforces the same lifecycle — construct → configure → run → reload → drain → stop — regardless of which of the three placements it is. The runner lives in `main`; it is main's hosting mechanism, not a fourth component kind, and it is what main actually spawns. `main` never statically imports a driver or an api module — the runner resolves and loads one at start, by id, from the manifest.

The runner's job stops at hosting. What each lifecycle step must guarantee for a driver versus an api, and how the three placements each implement the channel underneath it, is 02's job.

## 5. The messaging boundary

Everything a driver and an api exchange is one of three shapes: a **request** (read, write, invoke, introspect, subscribe), a **response** to one, or an **event** (a driver pushing readings, a topology change, a health flip). All three travel in an envelope carrying a correlation id, an origin and a deadline — the deadline is part of the envelope, not a per-call-site afterthought, so nothing on this boundary can wait forever.

The concrete envelope schema, its versioning, and the introspection payload shape are 03's.

## 6. Endpoints and addressing

An **endpoint** is anything inside a driver that can be addressed: a single channel (a relay, a temperature reading), a structured reading with no single-scalar shape (a network status block), or a callable with an effect (`invoke` — a discovery scan, say). What unifies these is not their shape but that each is one addressable, introspectable thing the driver chooses to expose. A driver does not force everything it has into a channel just because that is the most common shape.

An **address** is `<driverId>:<tail>`. The tail is owned by the driver that issued it and opaque to everyone else — nothing outside that driver parses it. A tail names what it addresses inside that driver: usually one endpoint, but it may also carry an endpoint-specific selector (a value versus its counter), a sub-operation (setting a debounce rather than reading it), or name several endpoints at once. The tail's grammar is entirely the driver's to define; 03 is where a concrete grammar gets specified, per driver class.

**Introspection is a driver describing itself**, not only listing its endpoints: its type, its configuration, its capabilities, and the endpoints it has. It is always reachable — every driver answers it — and it is how an api discovers what a driver offers without knowing the driver exists at build time. What exactly an endpoint declares about itself — kind, data type, which operations it supports — is 03's job to define; this file only requires that the declaration exists and that an api can act on it generically.

One split is worth stating at this level, because it is what makes "generically" possible at all rather than a hope: **kind is open** — any driver, built-in or plugin, can introduce one nobody else has — while the small vocabulary of value types a `kind` is built from is closed. A generic api acts on that closed vocabulary and never switches on `kind` itself, which is what lets a driver the api's author never heard of still render and validate correctly the first time.

## 7. Sharing a driver-owned resource

A resource one driver owns — a transport, a KV namespace — can be shared by other drivers that should not each hold a client of their own on it. It stays owned by exactly one driver, and every other driver reaches it through that owner, over the same request/response mechanism used everywhere else (§5). This is driver-to-driver messaging, and it is the only sanctioned kind — drivers do not otherwise depend on each other.

What the owning driver manages differs by resource, and that is the point of putting it there rather than in every caller. A **transport driver** arbitrates and routes: it owns a serial line, a TCP socket, an owserver connection, and resolves races between whichever device drivers share it — an air-quality sensor and an AC controller on one RS-485 line, written as separate plugins, say. A device driver on that line declares, in its own config, which transport driver it shares and its own address on that transport: addressing is the device driver's concern, arbitration is the transport driver's. A **KV-store driver** (06) manages no races at all; it separates callers by namespace, derived from the caller's own `Origin` (03 §2) — never something the caller states itself, so one caller can never reach into another's space by mistake or otherwise.

This is still the two-kind model: an owning driver is a driver like any other, distinguished only by what it exposes to other drivers, not by being a new kind. 07 has the concrete shape for Modbus; 06 has it for the KV store.

## 8. Non-blocking as a structural rule

Nothing on the driver↔api boundary may block: an api's query is answered from a driver's in-memory state, never from a live bus read, so a slow answer means the driver is genuinely wedged rather than that the bus was slow this once.

This now holds structurally rather than by convention: every instance has its own event loop (§3), so a blocked promise or a slow handler wedges only that instance, never `main` and never another. `main` still has no logic here — it reads config and hands each component to the runner its config names, nothing more. The two remaining placements are not equally isolated, though: both share one OS process, so a native-code crash — a bug in a serial-port binding's C++ layer, say — takes the whole process down regardless of which thread it happened on; only `child_process`'s own separate process survives that. Choosing it over `worker_thread` for a component whose transport leans on native code, or that does genuinely heavy computation, is the config author's call; 13 says what "heavy" means for an api and 06 for a driver.

## 9. APIs choose their drivers

An api declares which driver ids it consumes; it is wired to those and nothing else — wiring is configuration, not discovery. What it does with a driver it does not recognise is the api's own business: skip it, not refuse the whole config.

How open or fixed a given api's declared set is, and what it does with a driver outside it, is that api's own business to state — 14 and 15 are where each concrete api answers this.

## 10. Extension points

evok-node can be extended without changing its own code, at two different levels.

**A new component** is a driver plugin or an api plugin — each a manifest-loaded module, hosted by a runner (§4) exactly like a built-in driver or api, because nothing in §2 through §9 distinguishes "built-in" from "plugin".

**New content inside an existing driver** does not add a component. A new device or register-map definition extends what a driver already understands — 09 has the concrete mechanism for driver-extension — and a driver may also ship its own additions to the nextgen api and the inspector UI, beyond what generic introspection already exposes (17). Both stay inside the driver that declares them and leave §2's two kinds untouched.

## 11. Package ↔ component mapping

| Package | Role |
|---|---|
| `module-sdk` | The module contract and the wire contract in one place: `ModuleDescriptor`, `ModuleInstance`, `InstanceContext` and the runtime guard a loaded module is checked against (02 §4); the envelope, addressing, methods and error kinds a module speaks through it (03); the common services every instance receives through `InstanceContext` — `Logger`, `Clock`, `Deadline`, the scheduler (04); and the endpoint-type vocabulary a driver and an api both need — `Codec`, the three `EndpointType` shapes, and the built-in catalog (05). Depends on nothing of ours — root of the DAG. Published to npm, like `client`, for third-party plugin authors. |
| `hw-definitions` | Platform facts — device/model definitions, generated inventory, address resolution. Depends on nothing but the module contract; never resolves a `kind` against a real `DeviceType` (07a §2). |
| `modbus-kit` | The Modbus transport (07), *and* `hw-modbus-kit` (07a) — the binder that turns a `hw-definitions`-resolved definition into bound `driver-kit` devices for `driver-onboard`/`driver-extension`. The two stay in separate source subpaths; the package boundary no longer separates them. |
| `main` | Orchestration: config, the runner, spawn, supervise, reload. |
| `driver-kit` | Shared driver machinery: scan scheduling, the endpoint dispatcher (`bind`/`unbind`/`attach`), handshake. |
| `driver-onboard` | The transport driver for the controller's own onboard I/O. |
| `driver-extension` | The transport driver for one RS-485/TCP (modbus) extension line. |
| `api-nextgen` | The open, evok-node-native api. |
| `api-compat` | The fixed EVOK 3.x projection. |
| `simulator` | Test-only stand-in for hardware transports. |
| `client` | TS client retargeting `api-nextgen`'s schema. |
| `ui` | The inspector SPA, served by `api-nextgen`. |
| `rig` | The hardware-in-the-loop test instrument, deliberately outside the messaging graph. |

The complete set of permitted edges between these packages is `.dependency-cruiser.cjs`'s `WORKSPACE_DEPS` table — that file, not this one, is what a build actually enforces. A driver not yet built (`driver-onewire`, `driver-system`, `driver-kv-store`) is still one of the two kinds above, never a third.
