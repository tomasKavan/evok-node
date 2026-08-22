# evok-node — design notes and open questions

Not a plan yet. This is the set of decisions the research surfaced, so the actual design
session starts from a shortlist rather than a blank page.

---

## 1. Shape of the thing

The research suggests a layered split that maps cleanly onto the failure modes in
`04-known-bugs-and-lessons.md`:

```
┌─ api/            REST · JSON · Bulk · WebSocket · Webhook · JSON-RPC   (compat surface)
│                  + local IPC transport (§5)
├─ core/           device registry · lifecycle state machine · event bus · alias store
│                  command queue per device · one canonical event envelope
├─ hw/             hardware-definition loader (schema-validated, frozen)
│                  address computation · register codecs · per-model tests
├─ transport/      Modbus TCP client · Modbus RTU client (queue-owned, timing-gated)
│                  OWFS client · circuit breakers · per-bus supervisors
└─ platform/       unipiid / sysfs identity · autogen equivalent · doctor checks
```

The load-bearing idea: **the API layer never touches hardware**. It reads the registry's
current state and enqueues commands. That one boundary retires #190, #141 and #199's
architecture complaints at once.

Probably will be change during design.

## 2. Decisions to make before writing code

### 2.1 Compat fidelity — bug-for-bug or fixed?

Twelve doc↔code discrepancies and roughly a dozen outright broken endpoints are catalogued
in `01-evok-api-surface.md` §9. Proposal: **fix, with an opt-in `compat` block** in config
for the handful of shape differences a real client might depend on:

```yaml
compat:
  emitGlobDevId: false          # v2-era field, absent in 3.0.6 but present in docs
  wsAlwaysArray: true          # false ⇒ reproduce the object/array inconsistency
  legacyErrorStatus: true      # true ⇒ HTTP 404 for every error, like EVOK
```

Everything genuinely broken (bulk `group_*`, static 1-Wire sensors, RPC method signatures,
`register` events, alt-name filters) gets implemented correctly with no flag — no working
client can depend on a `TypeError`.

Specific deployed clients to stay compatible with: 
- Node-RED (`node-red-contrib-unipi-evok`), 
- Home Assistant integrations and 
- `evok-web-jq` (touch very little: `/rest/all`, `/rest/wd`, `/rest/run`,`/rest/device_info`, WS).

### 2.2 HTTP framework

EVOK's single-threaded Tornado loop is implicated in several findings. Node's event loop has
the same property, so the mitigation is architectural (§1), not framework choice. Candidates:
`fastify` (fast, schema-first with JSON Schema — which pairs well with the fact that EVOK's
own POST validation *is* JSON Schema, so upstream's `schemas.py` transcribes almost directly),
or `node:http` + a small router to keep dependencies near zero on an embedded target.

Leaning: **fastify** for the schema-first alignment and built-in serialisation speed, unless
install footprint on a 1 GB Neuron argues otherwise.

### 2.3 Modbus library, or our own?

Finding 1.2 (TID overflow) argues for owning the transaction correlation. Options:

- `modbus-serial` — most used, wraps `jsmodbus`; needs auditing for correlation and for
  RTU inter-frame timing.
- Write our own framing over `node:net` / `serialport`. Modbus RTU/TCP is a small protocol;
  the parts we care about (correlation, t1.5/t3.5, per-transport queue, typed error union)
  are exactly the parts libraries get wrong.

Leaning: **own framer over `serialport`/`net`**, with a conformance test suite against a
simulated slave and, ideally, against `unipitcp` on a real unit. This is a few hundred lines
and it is the reliability core of the product.

### 2.4 1-Wire: OWFS or direct?

EVOK depends on `asyncowfs` against `owserver` and inherits its failure modes (#101, #200,
#30, worker deaths). Alternatives: talk to the DS2482 via the kernel's `/sys/bus/w1`, or
implement the owserver protocol ourselves.

Constraint: OWFS presence is what `unipi-os-configurator` keys the `OWFS` config section on,
and Mervis OS explicitly must not have OWFS installed. Proposal: **support owserver for
compatibility, treat it as an optional dependency whose absence is a one-line warning and a
`degraded` bus**, and keep a `/sys/bus/w1` backend behind a config switch.

### 2.5 Autogen: consume or generate?

Consume `/etc/evok/autogen.yaml` when present (compat requirement) **and** implement our own
generator so we don't hard-depend on `unipi-os-configurator`. Inputs: `unipiid` files,
per-section sysfs, and holding registers 1001/1002/1004 as a cross-check. Cache key:
`unipiid fingerprint`.

### 2.6 Hardware definitions: reuse EVOK's, or extend?

Reuse the format verbatim (compat requirement) but add:

- a strict schema with generated TS types,
- optional fields we need and EVOK lacks: bank stride hints, expected DI/DO/AI/AO census for
  cross-checking against registers 1001/1002, per-feature `eventable`, conversion-time hints
  for resistance AI,
- a `definitionVersion` so we can migrate ours without breaking theirs.

Unknown fields in a definition must be a **warning**, never a hard failure — Unipi will add
fields.

## 3. Data model sketch

```ts
type Health = 'unknown' | 'probing' | 'online' | 'degraded' | 'offline';

interface Reading<T> {
  value: T | null;      // null ⇒ never read / invalid
  readAt: number | null;
  stale: boolean;       // age > expected poll period × k
}

interface DeviceState {
  id: string;           // stable, opaque
  kind: DeviceKind;     // 'di' | 'do' | 'ro' | 'ai' | 'ao' | ...
  circuit: string;      // EVOK-compatible circuit string
  aliases: string[];
  bus: string;
  slaveId: number;
  health: Health;
  // ...kind-specific, discriminated on `kind`
}

type Frame =
  | { v: 1; type: 'change';   ts: number; seq: number; changes: DevicePayload[] }
  | { v: 1; type: 'snapshot'; ts: number; seq: number; changes: DevicePayload[]; resynced?: boolean }
  | { v: 1; type: 'pong';     ts: number; seq: number }
  | { v: 1; type: 'error';    ts: number; seq: number; error: ApiError };

type TransportResult =
  | { ok: true;  registers: readonly number[] }
  | { ok: false; kind: 'modbusException'; code: number; name: string }
  | { ok: false; kind: 'timeout' | 'io' | 'notConnected' | 'framing' };
```

`DevicePayload` is the EVOK-compatible wire shape (`01-evok-api-surface.md` §4), derived from
`DeviceState` by a projection function — so the internal model can be richer than the
compatibility contract without leaking.

## 4. Testing strategy

1. **Simulated Modbus slave** per hardware model, seeded from the definition, driving the
   full device tree in-process. Every hardware-facing test runs against it.
2. **Table-driven address tests** per model: for each feature, assert
   `(circuit) → (register, bit, coil)` against a hand-checked table. This is the direct
   antidote to finding 1.1.
3. **Codec golden tables** per register type including negatives, boundaries, NaN and
   word-swap cases.
4. **Property test across the TID boundary** — 200 000 transactions, assert every response
   matches its own request.
5. **Golden transcripts from a real EVOK 3.0.6** (`GET /rest/all`, per-type GETs, a WS
   session, a webhook capture) replayed against evok-node with identical seeded registers;
   deep-equality modulo a documented allowlist.
6. **Upstream's own `examples/test_*.py`** run unmodified as acceptance tests.
7. **Fault-injection suite**: dead slave, slave that answers late, slave returning an
   exception PDU, bus that disconnects mid-transaction, owserver down, slow WS client, WS
   client that never reads. Each has a named assertion about *observable API behaviour*
   (device marked offline, error returned, others unaffected), not just "doesn't crash".
8. **Load test in CI**: N clients × M Hz change rate, assert bounded RSS, bounded p99
   latency, and zero lost counter increments.
9. Validate our responses against upstream's `Evok_API_OAS.yaml` in CI, with an explicit
   divergence allowlist.

## 5. Low-level local transport (post-v1, but design for it now)

The observation from the brief: running HTTP/WS to talk to a process on the same machine is
overkill for low-latency control. Options, roughly in order of increasing coupling:

| Option | Latency | Notes |
|---|---|---|
| **Unix domain socket, length-prefixed msgpack/CBOR** | ~tens of µs | Same protocol semantics as WS, no HTTP framing, no TCP stack. Easiest win, language-agnostic. |
| **Unix socket + shared-memory ring for state** | ~µs | Readers mmap a snapshot region and poll/futex; writes still go over the socket. Good fit for "read all inputs at 1 kHz". |
| **In-process library import** | zero IPC | Consumer *is* the Node process; the API server becomes an optional plugin. Best latency, worst isolation — a consumer crash takes the I/O layer with it. |

Design implication for v1: **the core must be usable without the API layer.** If `core/`
exports a clean programmatic interface (`registry.get(circuit)`, `registry.set(circuit, v)`,
`registry.on('change', cb)`) and every API is a thin adapter over it, then all three options
above are additive later. If the API layer owns state, none of them are.

Second implication: the event envelope and command schema should be **transport-agnostic and
serialisation-agnostic** from the start — define them as TS types with a codec boundary, not
as "the JSON we happen to send over WS".

**Open question:** what is the actual latency target, and is it *end-to-end* (physical input
edge → consumer reaction) or just IPC? The hardware side dominates: a 50 Hz scan is 20 ms,
and even a 500 Hz scan is 2 ms — an order of magnitude more than any IPC choice. If the goal
is genuine sub-millisecond reaction, the answer is likely **DirectSwitch in firmware** (§4.7
of `02-hardware-model.md`) or event-driven reads, not a faster socket. Worth settling before
optimising the transport.

## 6. Things we should deliberately do better than EVOK

Beyond the 40 rules in `04-known-bugs-and-lessons.md`, these are product-level:

1. **`doctor` command** — the single highest-value operability feature, given how much of
   Unipi's support load is diagnosis.
2. **`/diagnostics` and `/metrics`** endpoints (§4.35, §4.38).
3. **Definition linter** (`evok-node check-definitions`) usable offline against a
   `hw_definitions` directory.
4. **Declarative interlocks** in the device layer (§4.39).
5. **First-party TypeScript client** with reconnect and resubscribe (§4.40).
6. **A simulator mode** — run the whole stack against simulated hardware with no PLC present.
   Makes the project developable by anyone and is the backbone of the test suite anyway.

## 7. Decisions taken (2026-07-27)

### 7.1 Hardware scope for v1: **everything the maps cover**

Patron, Neuron, Axon, Edge, Unipi 1.1 / Lite, Extensions. Consequences that must be designed
in from the start rather than bolted on:

- **The hardware-definition format must be extended beyond EVOK's** — see
  [`06-register-maps.md`](06-register-maps.md) §2.7. Required additions:
  - **per-channel** mode sets (Edge: AI1 voltage-only, AI4/AI5 resistance-only), not one set
    per feature block;
  - **per-model mode enums** (Edge uses 4–20 mA and 90–2000 Ω where the PLC families use
    0–20 mA and 0–1960 Ω / 0–100 kΩ);
  - **unit-0 devices** alongside per-section ones (Edge ULED lives at register 3998 / coils
    3000–3002 on unit 0; storage-life 4000–4005 and Edge's LTE band 4200–4203 likewise);
  - a `definitionVersion` so ours can evolve while still loading Unipi's verbatim.
- **Unipi 1.1 needs a config-reapply-on-boot path.** Its map states outright:
  *"configuration is not permanently saved, set on each power-on."* No save-config coil, no
  board firmware, Modbus on **port 50200** via `unipi-one-modbus`. Model it as a family
  capability flag (`persistsConfig: false`) rather than a special case sprinkled through the
  code.
- **Capability flags, not family conditionals.** The forks we know about:
  `persistsConfig`, `hasMasterWatchdog`, `serialConfigSurvivesSectionRestart` (false on
  Neuron, true on Patron), `hasUnitZeroAggregate`, `aiAbstraction: 'two-mode' | 'six-mode'`,
  `hasBoardFirmware`. Derive them from the definition + identity, never from a model-name
  regex.
- Axon is discontinued — support it because the maps are there and the register model is the
  same as Neuron's, but it gets no special engineering effort.

### 7.2 Packaging: **library first, service second**

The npm package is the primary artifact; the systemd service is a thin wrapper around it.
This makes §5's "core must be usable without the API layer" a *structural* requirement rather
than an aspiration, and it defers the apt/coexistence question until there's something worth
installing.

Implications:

- `core/` exports the programmatic interface (`registry.get/set/on`) and has **no dependency
  on the API layer**. Enforce with a lint rule or separate package boundaries.
- Every API (REST/JSON/WS/webhook/RPC) is an adapter package or subpath, individually
  omittable.
- Config loading is a library concern too — accept a config object, not just a file path, so
  embedders don't need `/etc/evok`.
- Defer: apt packaging, systemd unit naming, whether we can `Conflicts: evok`.

### 7.3 Latency: **defer the low-level transport**

API-only for v1, with `core/` decoupled so a unix socket, shared-memory snapshot or
in-process mode is purely additive. Rationale: a 50 Hz scan puts you 20 ms from the hardware,
which dominates any IPC choice by an order of magnitude.

Worth an early spike regardless: **`Interrupt Mask` (register 1007)**, named on every PLC map
with no documented semantics. If it enables interrupt-driven reads, it changes the polling
architecture — and it's the only plausible route to genuine sub-millisecond reaction short of
pushing logic into firmware via DirectSwitch.

### 7.4 Hardware verification: device available, model TBC

Checklist to run once the device is identified — these are the only remaining items that
cannot be closed from documentation:

| # | To verify | Why it matters |
|---|---|---|
| 1 | `RS485 Configuration` register: baud + parity bit encoding | Reconstructed table is `[I]`; only `14 = 19200` is verified. Needed to configure extension buses programmatically. |
| 2 | Is `Synchronised DO/RO` + `Lock` the DirectSwitch write path? | No `ForceOutput` register exists in the corpus. Without this, a DirectSwitch-claimed output can't be written at all. |
| 3 | `Interrupt Mask` (reg 1007) semantics | §7.3. |
| 4 | `(Internal) RS485 Full Mode Configuration` (reg 100) + `RS485 TERMIOS` band (500–503) | Programmatic serial-line setup. Per-section only, not reachable via unit 0. |
| 5 | Behaviour of a unit-0 aggregate read spanning sections | Confirms the `+100×(n-1)` optimisation is safe, and what happens when one section is unhealthy. |
| 6 | Board firmware version vs the map's `v1.0` label | FW 5.x boards may not match the maps at all. |
| 7 | Golden transcripts from stock EVOK 3.0.6 on the same unit | The compatibility test oracle (§4.5). **Capture these before replacing anything.** |

Item 7 is time-sensitive: capture the transcripts while the device still runs stock EVOK.

## 8. Some decisions

Some decisions were made during considerations. But these might not be final. Design docu is definite source.

### 8.1 Debian 12 **and** 13

Both supported. The identity layer therefore needs a fallback chain, because `unipiid` is
Debian-13-only:

| Fact | Debian 13 | Debian 12 fallback |
|---|---|---|
| Unit identity | `/run/unipi-plc/unipi-id/*` (`unipiid -d`) | sysfs `iogroup[1-3]/sys_board_name`/`sys_board_serial`, plus `/etc/evok/autogen.yaml`'s `device_info` |
| Cache key | `unipiid fingerprint` | hash of (board names + serials + firmware versions) |
| Serial lines | `/run/unipi-plc/by-sys/rs485-N/tty` | same, plus deprecated `/dev/extcomm/Y/X` |
| `unipitcp` binary | on `$PATH` | `/opt/unipi/tools/unipitcp` |
| Disable 1-Wire | Modbus coil only | sysfs `iogroup[N]/ow_power_off` also works |

Rule: identity is a **provider interface** with `unipiid`, sysfs and register-based
implementations, tried in that order, each reporting its confidence. Never branch on Debian
version inline.

### 8.2 Compatibility baseline: Node-RED + Home Assistant

Full analysis in [`07-client-compatibility.md`](07-client-compatibility.md) — 22 hard
requirements, and a list of surface no client touches. Headlines:

- `emitGlobDevId` **dropped** — no client reads it.
- `wsAlwaysArray` and `legacyErrorStatus` **kept**. Note neither is really "legacy":
  always-array *repairs* two clients that crash on EVOK today, and non-2xx-on-error is a live
  requirement of `unipi-mqtt` (checks `status_code == 200`) and the vendor web UI.
- Two flags **added** by the findings: `batchEvents: false` (evok2mqtt hard-indexes `[0]`, so
  batching silently drops events) and `acceptAliasPrefix: true` (repairs Unipi's own v3
  Node-RED node, which still sends v2 `al_<alias>`).
- **Deployment requirement**: something must answer on **:80**. HA's `evok-ws-client`
  hardcodes `ws://<ip>/ws` with no port option, so without an nginx-equivalent front end our
  stated HA baseline cannot be configured at all.
- **Strict integers out, liberal in**: three clients compare emitted `value` to the integer
  `1` and fail silently otherwise, while HA and pimatic *write* `"1"` as a string.

### 8.3 ⚠ Hardware scope needs one more decision

"All models supported by EVOK v3" and "everything the maps cover" are **not the same set**.
EVOK 3's README claims exactly: *"NEURON, PATRON, GATE and Unipi 1.1 devices including
Extension modules"*.

| Family | Claimed by EVOK v3 | Maps in repo | Notes |
|---|---|---|---|
| Neuron | ✅ | ✅ | |
| Patron | ✅ | ✅ | |
| Gate | ✅ | n/a | **no local I/O** — EVOK on Gate exists only to reach extensions |
| Unipi 1.1 / Lite | ✅ | ✅ | no board firmware, no NV save, Modbus on port 50200 |
| Extensions | ✅ | ✅ | |
| **Axon** | ❌ dropped in v3 | ✅ 18 models | discontinued; register model ≈ Neuron |
| **Edge** | ❌ not mentioned | ✅ 4 models | newest product line; not claimed by EVOK anywhere on the KB either |

So the intersection is Neuron + Patron + Gate + Unipi 1.1 + Extensions. **Edge is the
interesting question**: it's the current flagship, its maps are the best-documented in the
corpus, but EVOK doesn't claim it and it's structurally different (slot/card system, unit-0
ULED, per-channel AI modes, 4–20 mA / 90–2000 Ω ranges).

Also unresolved: `evok/config.py:79` names a family **`Iris`** (`[Neuron, Patron, UNIPI1,
Iris]`) that appears in no public product line. `unipi-tools`' README also lists "Neuron,
Axon, Patron, Iris". Possibly an internal/OEM name, possibly Edge's codename. Worth asking
Unipi.

**Decided:** **v1 = Patron + Neuron + Unipi 1.1 + Extensions + Gate** (Gate falls out for free
— it is extensions only, no local I/O). **Edge is a fast follow-up to 1.0.** **Axon is
dropped** — its map CSVs stay in the repo as free cross-check data for the Neuron register
model, but no support is claimed and no hardware is needed. `Iris` is disregarded.

Important consequence of "Edge as fast follow": the **overlay format must be designed now**
for Edge's requirements (per-channel mode sets, unit-0 devices, per-model mode enums) even
though Edge *definitions* ship later. Deferring the format would mean a breaking overlay
change in the first minor release.

### 8.4 Modbus: use a library, wrap the broken layer

Agreed — and adopted as a **general project rule**: *where a widely-used, tested, actively
maintained library exists, prefer it; isolate it behind an interface so it can be replaced.*

The library survey (July 2026) is unambiguous about one thing: **no JS library has the
pymodbus TID-correlation bug.** That was the main reason to consider writing our own, and it
evaporates. But the survey found a *different* bug of equal severity in every mature library:

> **Stale-frame desync after a timeout.** The RX buffer is never flushed. Request A times out;
> A's response arrives late; request B is written; the framer finds A's stale frame — valid
> CRC, matching unit id, matching function code, same expected length — and **returns A's data
> as B's response.** For a polling loop hitting the same registers this is silent stale data,
> not an error.

Verified present in `modbus-serial` and `jsmodbus@4.0.10`; fixed only in a private fork
(`@zandor300/jsmodbus`, which flushes on timeout) and in `njs-modbus` (which flushes before
every request — the stronger discipline).

**Decision: `modbus-serial` as the PDU/transport layer, behind our own port interface, with a
subclassed `RTUBufferedPort`.**

Why `modbus-serial`: only mature option that is simultaneously actively maintained (8.0.25,
2026-03-20), on current `serialport ^13`, has real field mileage (~29k weekly downloads, 88
dependents), and has the best **post-match validation** of any library — it checks unit id,
function code, expected length *and* CRC after matching. `jsmodbus` has the better architecture
(real 1-in-flight queue, loud `OutOfSync` rejection) but has published nothing to npm since
2023-12-21 with a 20-month-unanswered release request; adopting it means vendoring a dev branch,
at which point we own the code anyway.

**What our wrapper must supply. All load-bearing, none optional:**

1. **A per-port async mutex** — per physical bus, not per client or per slave. Non-negotiable:
   `modbus-serial` has no queue at all, and `_unitID`, `_port._id`, `_port._cmd` are single
   mutable slots that a second overlapping request destroys. This is exactly our multi-extension
   scenario (issue #475/#540 upstream).
2. **RX flush before every request.** No public API exists; the supported extension point is to
   subclass `RTUBufferedPort` and pass the instance to `new ModbusRTU(port)` (ports are
   duck-typed on `open/close/write/isOpen` + `_transactionIdRead/_transactionIdWrite`).
3. **Strict unit-id + function-code gate** in the subclass, refusing any frame that doesn't
   match the outstanding request, and **CRC validated before consuming bytes** from the buffer.
4. **t3.5 inter-transaction pacing** in the mutex release path (`38.5/baud` s, floor 1.75 ms
   above 19200). No library except `njs-modbus` implements it; upstream issue #455 has been open
   with zero comments for four years. This also removes the whole "add `sleep()` to make it
   work" class of problem — and is precisely the ailment EVOK's
   `await asyncio.sleep(0.00005)  # TODO: THIS IS HOTFIX !!! REMOVE IT !!!` was treating.
5. **Our own outer deadline** on every request (`Promise.race`). `modbus-serial`'s
   `_cancelPendingTransactions()` clears timers **without rejecting**, so `destroy()` leaves
   in-flight promises permanently unsettled (#547, open 29 months).
6. **Our own reconnect supervisor.** Do not trust `isOpen()` (#383) or the `close` event (#591);
   drive liveness from consecutive-failure counts.
7. **Retry with backoff at the wrapper level** — there is none in the library (#304/#418).
   Retry idempotent reads only; **never** blind-retry FC5/6/15/16.
8. **Cap outstanding TCP requests below 256** — the TID table has only 256 slots and overwrites
   silently. Free once (1) exists.

For **Modbus TCP: use the library as-is.** MBAP framing is length-prefixed and unambiguous, the
TCP path is correct, and 8.0.25 fixed split-segment handling (#602).

Corroboration worth knowing: `node-red-contrib-modbus` (the dominant Node-RED Modbus package)
depends on a *private fork* of `modbus-serial` fetched by URL, and the official ioBroker adapter
replaced both libraries with an in-house implementation in Oct 2025. Two of the largest
industrial JS consumers independently concluded the shared libraries weren't good enough — which
is exactly why the wrapper list above is not paranoia.

Read `njs-modbus`'s `RtuProtocolLayer` as a design reference for the framing FSM. **Do not copy
it** — it is BUSL-1.1, not open source.

### 8.5 Node.js 24 (current Active LTS)

Node **24** is Active LTS as of July 2026 (EOL 2028-04-30); 22 is in maintenance, 26 becomes
LTS in October 2026. Target 24, keep the code 26-clean, and don't use anything that would
block a 26 bump.

### 8.6 `Interrupt Mask` — dropped, as suggested

Verified: **EVOK never touches register 1007** (`grep -rni "interrupt\|1007" evok/ docs/` →
no hits), and the register is named but undocumented in every map. Leaving it out. Recorded in
[`06-register-maps.md`](06-register-maps.md) §4 as a curiosity to revisit only if a
latency requirement ever justifies it — and per
[`08-latency-and-scan-budget.md`](08-latency-and-scan-budget.md), it wouldn't help extensions
anyway, since their latency is serial wire time.

### 8.7 Latency: 16 ms is the floor, and it's physics

The measured 16 ms for a full xS11 read is **almost exactly the wire time of one 10-register
Modbus RTU transaction at 19200 8N1** (17.2 ms computed). Worked out in
[`08-latency-and-scan-budget.md`](08-latency-and-scan-budget.md). Consequences:

- Software is irrelevant at this scale — which retroactively confirms §7.3.
- The levers are **baud rate** (115200 gives a 4.2× improvement), **block layout**, and
  **per-bus scheduling**.
- Correct t3.5 gaps cost ~2 ms/transaction at 19200. Mandatory, not optional.
- The counter-as-change-detector idea is sound, with a price: on an xS11 the 12 counters are
  24 registers, so polling them at full rate roughly **triples** cycle time. Put them in a
  medium-frequency block and expose a `pulsesSinceLastRead` delta.

### 8.8 Front end: nginx stays

We do **not** ship a `:80` listener. evok-node listens on `:8080` exactly as EVOK does, and
nginx in front remains a documented deployment requirement — the stock `evok` nginx site works
unchanged since our port and paths match. We ship a reference site file for from-scratch
installs.

Two things this makes load-bearing (detail in
[`07-client-compatibility.md`](07-client-compatibility.md) §5): the WebSocket must produce
traffic well inside nginx's `proxy_read_timeout 180`, and **integration tests must run through
the proxy**, since the HA baseline only ever talks to `:80`.

### 8.9 Test hardware

Available: **Patron M527, S167-LTE, L527, Gate** (+ xS11). Full coverage analysis in
[`09-test-hardware-coverage.md`](09-test-hardware-coverage.md). The headline:

> **Every model with more than 16 channels of one type is a Neuron** (M303/L303: 30 DI;
> M403/L403: 28 RO). No Patron has more than 16 of anything. So the available hardware
> **cannot reproduce our highest-severity bug class** — it must be covered by the simulator and
> table-driven address tests generated from the map CSVs, and the eventual Neuron purchase
> should be an **M403 or L403** specifically.

The L527 is the richest unit: 3 sections (so unit-0 aggregate addressing), both AI
abstractions, and **exactly 16 DI on section 3** — the bank boundary without crossing it.
The Gate is the zero-local-I/O case and the cleanest RS-485-only rig.

### 8.10 HTTP layer: fastify

Decided. Its JSON-Schema-first design maps almost 1:1 onto EVOK's own `schemas.py`, so the POST
validation transcribes directly, and schema-driven serialisation is a good fit for the
invariant-envelope requirement.
