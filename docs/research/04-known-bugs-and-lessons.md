# Known bugs, failure modes, and the design rules they imply

Condensed from [`appendix/raw-bug-archaeology.md`](appendix/raw-bug-archaeology.md), which
has the full ~90 findings with commit hashes, issue numbers and quotes. Evidence base:
1045 commits (2016 → 2025-09), all 153 GitHub issues, the open PRs, the pinned pymodbus
fork, and ~19 Unipi forum threads plus third-party client trackers.

**Correction to the appendix:** it lists the "aliases saved 5 minutes after change" claim as
unverified. It *is* verified — `AliasTask.SAVE_TIME = 300` in `evok/evok.py` and
`docs/configs/aliases.md`. The atomicity problem in `save_aliases` is separately confirmed.

**Meta-observation worth internalising.** The bug tail is dominated by *state* problems,
not algorithm problems: one-shot initialisation, cache aliasing, torn multi-word reads,
unbounded queues, swallowed exceptions, and payload shapes that vary by code path. A
TypeScript implementation gets most of these for free **if** the domain is modelled with
discriminated unions, `readonly`, exhaustive switches and one canonical event envelope — and
gives them all straight back if the boundaries are `any`.

**Second meta-observation.** Upstream's maintainers know. Issues #164 (async init), #192
(hot-plug), #153 (per-device TCP session), #201 (validity flag + timestamp), #74 (bus
contention), #131 (address-conflict detection), #209 (>16 channel addressing) are all
**open**, authored largely by them. That set is a production-hardening to-do list written by
people who have run this for a decade. Build them in from day one.

---

## Severity tier 1 — actuates the wrong physical output

| # | Finding | Evidence |
|---|---|---|
| 1.1 | **>16-channel addressing is wrong.** `val_reg` is not advanced by the bank stride and `RO`/`DO`/`LED` ignore `start_index`, so on a 28-relay Neuron M403 circuits `_01…_12` silently drove **relays 17–28**. | #209, #195, `[V-src]` |
| 1.2 | **Modbus TID overflow.** pymodbus matched a response to an *arbitrary* pending request whenever the transaction id wrapped to 0 (`if not tid:`), i.e. every 65 536 transactions. Symptom: plausible-looking wrong values, never a crash. EVOK now permanently pins a one-commit personal fork. | `martyy665/pymodbus@566cd7d`, `96cb8e1` |
| 1.3 | **Shared register cache between slaves.** `copy()` instead of `deepcopy()` meant every slave on a bus shared one value array — one device's readings appeared as another's. | `80c95f1` |
| 1.4 | **Torn 32-bit counters.** The low and high words are two independent cache lookups; they are only coherent if both live in the same register block with the same `frequency`, which the definition format does not enforce. | `[V-src]` |

**Rules.**

1. One audited address function per feature type:
   `(blockBase, channelIndex) → {registerAddress, bankOffset, bitMask, coilAddress}`, with
   `floor(i/16)` and `i % 16` in exactly one place, plus a table-driven test per hardware
   model. Never derive an identity from a loop counter.
2. **Assert global uniqueness at startup** — duplicate circuit ids, or two circuits mapping
   to the same coil/(register,bit), is a fatal config error, not a warning.
3. Own the request↔response correlation: `Map<number, PendingRequest>` with `has()`
   semantics, and a property test that crosses the `0xFFFF → 0` boundary.
4. Hardware definitions are **immutable** (`readonly`, frozen, types generated from the
   schema). Per-device mutable state can then never be aliased.
5. Multi-word values must be read from **one atomic block snapshot**; validate that at
   definition load and reject violating definitions.

---

## Severity tier 2 — the service stops working and needs a restart

| # | Finding | Evidence |
|---|---|---|
| 2.1 | **Discovery is a one-shot startup step.** A device absent at startup is never registered, even after it reconnects. This single choice generates a decade of downstream reports (`'NoneType' has no attribute 'do_scan'`, "Invalid device circuit", "no boards detected after apt upgrade") and the community's `@reboot sleep 200 && service evok restart` culture. | #192, #164, PR #193 (draft), `[V-src]` |
| 2.2 | **One unreachable slave blocks every bus and every client.** Device I/O runs inside the WebSocket message handler; a pymodbus timeout/teardown hang stalls everything behind it. On recovery the whole backlog fires at once, **replaying stale commands onto physical outputs**. | #190 — and the merged "fix" (`950a9e3`) addressed an unrelated `IndexError`, so treat the behaviour as still present in 3.0.6 |
| 2.3 | **Unbounded WebSocket send buffering.** `write_message` is never awaited; a slow client grows the buffer without limit and write failures become unretrieved futures. A wind sensor on a DI killed the whole API — `service evok restart` *and* nginx restart didn't recover it, only a reboot. | #141, `[V-src]` |
| 2.4 | **Closing the last WebSocket can stop Modbus polling** for devices with `scan_enabled: false`, and nothing restarts it. REST then serves an indefinitely stale cache with no staleness marker. Made worse by webhook handlers sharing the same client registry. | `[V-src]` |
| 2.5 | **One missing 1-Wire sensor froze all sensors** — the working sensor's value and timestamp stopped refreshing entirely. Also: the 1-Wire worker process dying while EVOK stayed up, serving frozen temperatures for days. | #101, #30, forum |
| 2.6 | **A failing register block discards the whole scan pass**, including changes already observed from earlier blocks, because `do_scan` uses `try/finally` with no `except`. | `[V-src]` |
| 2.7 | **Crash-loop on config errors.** Port conflicts and missing EEPROM data caused systemd restart storms presenting as 100 % CPU; fixed in the **unit file**, not the program. | #43, forum |

**Rules.**

6. **Discovery is continuous and supervised; the device tree is hot-mutable.** Every
   configured device has a lifecycle (`unknown → probing → online → degraded → offline`),
   appears in the API *always* with its state, is re-probed on backoff while offline, and
   registers idempotently. Emit `device.online` / `device.offline`. This is the single
   highest-leverage item in the whole report.
7. **Device I/O never runs in a socket handler.** Accept → validate → enqueue → return a
   correlation id; a per-device worker executes. Per-bus isolation so an RS-485 stall cannot
   touch a TCP device.
8. **Commands expire.** Every queued write carries a deadline; on timeout it is rejected to
   the client, never replayed. Replaying a 40-second-old "close relay" is a safety issue.
9. **Backpressure by design.** Bounded per-client queue; on overflow degrade to a coalesced
   last-value-wins snapshot with `resynced: true`. Never buffer without limit, never drop
   silently. Load-test N clients × M Hz in CI with assertions on RSS and latency.
10. **Polling policy is a property of the device, never of who is listening.** Explicit
    per-device modes: `poll(hz)` / `onDemand(ttl)` / `event`.
11. **Per-block and per-device error isolation** — always emit the changes you did observe;
    a partial read degrades coverage, never truth. One missing sensor can never stall the
    others.
12. **Buses are supervised children** with their own lifecycle, restart-with-backoff, error
    counters, and API-visible state. A dying bus worker must never be silent.
13. **Two error classes, two behaviours.** Config/dependency errors: validate everything up
    front, report *all* of them with file and JSON pointer, exit non-zero **once**,
    self-rate-limit restarts. Runtime hardware errors: stay up, mark offline, keep retrying.

---

## Severity tier 3 — silently wrong or unusable API behaviour

| # | Finding | Evidence |
|---|---|---|
| 3.1 | **Failed writes returned `success: true`.** pymodbus returns `ExceptionResponse` as a *return value*, not a raise; EVOK treated "illegal data address" as success. Took three commits to make errors exist at all — and the resulting check is `type(x) in exception_classes`, an exact-type test any subclass slips through. | #183, `07b5dc9`, `66f874b`, `f2db299` |
| 3.2 | **Write responses return the pre-write value.** "Evok returns the last read values… after the writing is finished, reading is not performed immediately." | #122, #125 (both open) |
| 3.3 | **`ds_mode` never returns to `Simple`** — the decode assigns `Inverted`/`Toggle` but has no branch for "both bits clear", so the previous value persists. Reported as unfixable-in-the-field in #121, still latent at HEAD. | #121, `[V-src]` |
| 3.4 | **Payload shape has never been invariant.** WS `full` returns an object where events return arrays; 1-Wire events bypass the array wrapper; `register` devices never emit events at all (#214); the `relay→ro` / `input→di` / `unit_register→data_point` renames broke every downstream integration. Third-party clients crash with `message.forEach is not a function`. | #71, #214, #44, #36, #72, `node-red-contrib-unipi-evok#8`, `pimatic-unipi-evok#12` |
| 3.5 | **Alt-name filters silently match nothing.** `{"cmd":"filter","devices":["input"]}` is accepted and matches zero devices. The shipped default `webhook.device_mask: ["input","wd"]` has the same problem. | `[V-src]`, #214 |
| 3.6 | **Webhooks never fire for 1-Wire** — a `TypeError` from iterating a dict as a list, swallowed by `devents`' bare `except: pass`. | `[V-src]` |
| 3.7 | **No keepalive, no close reasons, no subscription echo.** Users send `cmd:all` every 60 s as a heartbeat — a full-state dump abused as a ping. Filter state is lost on reconnect with no way to tell. | forum, `[V-src]` |
| 3.8 | **Value-conversion bug tail**: negative AI values (twice), NaN producing **invalid JSON** on the wire, resistance returned as int, PWM frequency formula fixed twice, secondary AI (index > 0) not computed for WS, inverted AO on Unipi 1.1. | `1cdcbb3`, `fe83cd0`, `8822a41`, `348c88b`, `a1b1666`, #95 |
| 3.9 | **Aliases are not durably written.** Truncate-then-write with no temp file or rename; no flush on shutdown, so up to 5 minutes of changes are lost on a clean restart. | `[V-src]` |
| 3.10 | **Bulk `group_queries`/`group_assignments` are broken** (Python `map` objects handed to `json.dumps`); `global_device_id` filters on an attribute no class defines. | `[V-src]` |

**Rules.**

14. **Transport results are discriminated unions**:
    `{ok:true, registers} | {ok:false, kind:'modbusException'|'timeout'|'io'|'notConnected', ...}`.
    A protocol-level error response **is a failure**. Normalise library error taxonomies at
    the adapter boundary; never exact-type-check them.
15. **Total decode functions.** `decode(registers) => State`, exhaustive over a discriminated
    union, every branch returning a value. No in-place mutation with implicit fall-through.
16. **One codec layer** for sign extension, scaling and endianness, with a golden table per
    register type (`i16`, `u16`, `i32`, `u32`, `float32`, fixed-point) including negatives
    and boundaries. "No valid value" is `null` / `{valid:false}` in the type system so it can
    never serialise as `NaN`.
17. **One invariant event envelope from every source**:
    `{v, type: "change"|"snapshot"|"pong"|"error", ts, seq, changes: Device[]}` — `changes`
    always an array, even for one device. Validate outbound frames in dev/test builds.
18. **Monotonic `seq` per connection** plus an explicit `resync`/`snapshot` command. Then
    coalescing under load is safe and gaps are client-detectable.
19. **Protocol ping/pong on a timer**, close codes with reasons, echo the effective
    subscription on connect and after every change, and **reject unknown filter values
    loudly**. "Accepted but ineffective" is the worst failure mode for a subscription API.
20. **Normalise identifiers once, at ingress**, into a canonical internal form. In TS make
    the filter a `Set<DeviceKind>` over a union type so a raw string cannot enter.
21. **Eventability is not opt-in per feature parser.** Derive it from the registry, or make
    `eventable` a required field — #214 designed out of existence.
22. **Write responses reflect reality**: read back the affected registers, or return
    `202` + `pending: true` + a confirming event.
23. **Staleness is part of the data model.** Every reading carries `value`, `readAt`, `age`,
    `stale`; every device and bus carries an explicit lifecycle state. This is open issue
    **#201** verbatim, and it retires #30, #101 and the frozen-temperature reports in one
    move.
24. **Counters get `width`, `wrapAt`, and a server-computed monotonic `bigint` total** so
    clients never implement wrap arithmetic — and so shed change events remain recoverable.
25. **Durable user data**: temp file + `fsync` + atomic rename, synchronous on change or a
    bounded documented flush window **plus flush-on-shutdown**. Unresolvable aliases are
    retained as diagnostics warnings so a later hardware change re-binds them.
26. **REST and WS share one command schema and one handler**, or the WS surface rots (it
    already has: aliases cannot be set over WS).
27. **Stable opaque ids** decoupled from labels (`{id, kind, family, busPath, label,
    aliases[]}`), a versioned API path, and old type names retained as documented aliases
    for one major version.
28. **No bare catch on the event path.** Log-and-count with dedup.
29. **Decide auth and origin policy on day one** (#149 is still open, and `check_origin`
    returns `true` unconditionally).

---

## Severity tier 4 — operability

| # | Finding | Evidence |
|---|---|---|
| 4.1 | **RS-485 timing was never modelled.** "Fixed dead-time generation on RS485" was landed, reverted the same day, then re-landed (2019). The current shipped workaround for multi-device RTU instability is `await asyncio.sleep(0.00005)  # TODO: THIS IS HOTFIX !!! REMOVE IT !!!` — on an **unmerged branch**, released only as a `.test.` apt package. A user reports it was insufficient. | #210, `757da36`, `879151f`/`78f707b`/`47bcae6` |
| 4.2 | **Backoff is defeated by partial recovery.** `scan_errors` resets to 0 on any success, so a marginal bus flaps `Slowing down` / `Communication is back` forever and backoff never engages. | `[V-src]`, #210 log |
| 4.3 | **A dead peer starved a healthy device's watchdog.** With 3 of 6 devices gone, an xS11's 2.5 s hardware MWD fired and dropped its outputs. | #123 |
| 4.4 | **Timeouts and reconnect were tuned by trial and error**: RTU timeout shipped at **4 s** before being cut to 1 s; RTU auto-reconnect had to be *re-added* after being lost; an **unbounded** `while not connected: sleep(0.001)` busy-wait existed for six months and still exists on the RTU path with a bare `# TODO`. | `710b4fa`, `b53a4ed`, `2a5a4d7`, `66f874b` |
| 4.5 | **Idle CPU ~16.6 % of a core** on an RPi 3B+ with one board and one DS18B20. On-demand reads: "not currently planned". `scan_frequency: 0` yields a **10 kHz** poll loop. | #199, `[V-src]` |
| 4.6 | **Diagnosability was an afterthought.** Tracebacks were only added behind a debug flag in 2024. `evok.log` grew uncontrollably (#66, #93) and v2 cleared it on boot. A missing `owserver` produces a 60-line nested `ExceptionGroup` whose one actionable fact is `ECONNREFUSED 127.0.0.1:4304`. In #212 the real fault was a *downstream* service crash-looping on a GPIO conflict, surfaced only as `[Errno 111]`. | #114, #66, #93, #200, #212 |
| 4.7 | **Ten consecutive commits in one day titled "Fix autodetection nginx"** — install-time platform detection by trial and error. | `105d95d`…`fab6b9a` |
| 4.8 | **Interlocks were left to clients.** A third-party author reports burning out relay outputs by driving a cover's up/down relays together. | `marko2276/ha-unipi-neuron` |

**Rules.**

30. **Explicit RS-485 timing**: t1.5 / t3.5 gates computed from baud rate, enforced against
    real timestamps on the port object, configurable per bus. No microsecond `sleep` hacks.
31. **Serialise per transport, structurally** — a request queue owned by the connection so a
    frame *cannot* bypass it. RTU needs it for bus arbitration, TCP for transaction
    correlation. (Upstream's TCP client creates a lock and never acquires it.)
32. **Circuit breaker with hysteresis and a bus time budget**: track
    `consecutiveFailures`, `lastSuccessAt`, `state: healthy|degraded|quarantined`; require
    *N consecutive* successes to close; decay rather than zero the error count; add jitter.
    A quarantined slave gets one probe per interval and never consumes healthy devices'
    slots.
33. **Every wait has a deadline.** No unbounded connection-flag polling — await a
    connection-state promise.
34. **Reject nonsensical config at load.** `scan_frequency: 0` is an error or an explicit
    `mode: onDemand`, never a 10 kHz loop.
35. **Ship `evok-node doctor` / `GET /diagnostics`**: config schema, port availability,
    required `/dev` and `/run/unipi-plc` nodes, kernel modules and overlays, board firmware
    vs a known-good floor, owserver reachability, exclusive bus ownership — pass/fail per
    check. Unipi's maintainers re-typed this checklist into forum posts for years; it belongs
    in the binary.
36. **Name the failing dependency**: *"1-Wire disabled: owserver unreachable at
    127.0.0.1:4304 (connection refused); is owserver running?"* — raw stack behind a debug
    flag.
37. **Structured logs** (JSON with `bus`, `device`, `circuit`, `errorKind`), per-key rate
    limiting and dedup, periodic rollups, size-capped rotation, never truncate on boot.
38. **Metrics endpoint**: event-loop lag, per-bus transaction rate and latency p50/p99,
    scan-cycle duration, per-slave error counts, WS client count and queue depths, uptime,
    restart count. Makes "high CPU" / "it hangs" answerable in one request instead of a forum
    thread.
39. **Interlocks in the device layer**: declarative mutual-exclusion groups with minimum
    dwell time, plus per-device command serialisation.
40. **Ship a first-party TS client** with reconnect, backoff and automatic resubscribe, so
    integrators stop reinventing it five different ways.

---

## Explicitly *not* established

- **No credible evidence of a memory leak in EVOK.** The "leak-like" reports resolve to
  restart loops (#43) or the unbounded-queue mechanisms above — plausible leak paths, but no
  reporter observed RSS growth. Do not repeat the claim.
- Issue **#212**'s final resolution (page text truncated).
- A forum report of an hourly cron restart on a Neuron 203 + 2×xS30 + xS40 — source page not
  locatable.
