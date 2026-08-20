
# EVOK (Python) Bug Archaeology — Findings and Design Lessons for `evok-node`

**Scope of evidence.** Full git history of `UniPiTechnology/evok` (unshallowed: 1045 commits, 2016→2025-09, HEAD `47c95c8`, tags up to `3.0.6`); all 153 GitHub issues (27 open / 126 closed) enumerated, ~25 read in full; the 3 open + 60 closed PRs listed; the pinned `pymodbus` fork; and community threads (Unipi forum, HA, third-party clients) gathered by a parallel pass.

**Verification key:** `[V]` = verified against a URL or a commit I read. `[V-src]` = verified by reading the current EVOK 3.0.6 source in the clone. `[I]` = inference/reasoning, flagged as such.

---

## 1. Modbus RTU/TCP transport reliability

### 1.1 The pinned pymodbus fork: the "TID overflow" bug — a silent response/request mismatch `[V]`

EVOK pins a personal fork instead of PyPI (`96cb8e1`, `d4d0f72`, 2024-06-18):

```
-    'pymodbus == 3.5.4',
+    'pymodbus@git+https://github.com/martyy665/pymodbus@fix-tid-overflow',
```

The fork contains exactly **one** commit on top of pymodbus 3.5.4 — `martyy665/pymodbus@566cd7d` "Fix TID overflow", a one-line change in `pymodbus/transaction.py::getTransaction`:

```python
-        if not tid:
+        if tid is None:
```

**Root cause:** pymodbus transaction IDs increment and wrap at 16 bits. When the tid wraps to **0**, `if not tid:` is truthy, so `getTransaction(0)` takes the "no tid supplied" branch and returns `self.transactions.popitem()[1]` — an *arbitrary* pending transaction — instead of looking up tid 0. The response of one request gets matched to a different request.

**Why it matters far more than a one-liner suggests:** EVOK polls continuously, so tid 0 recurs every 65 536 transactions — on a busy PLC, every few minutes to hours. The observable symptom is not a crash but **plausible-looking wrong values** (one register block's data written into another's cache) and spurious errors. It is exactly the kind of bug that produces "sometimes a value is just wrong" reports that never get root-caused. Note also that the fix was never upstreamed and EVOK now permanently depends on a personal GitHub fork of a transitive dependency — a supply-chain and reproducibility liability.

> **Lesson.** Own your Modbus transaction layer, or at minimum own the request↔response correlation. Write the correlation as an explicit map keyed by a `number` with `Map.has(tid)` semantics — never truthiness. Add a property-based test that drives the tid across the 0xFFFF→0 boundary and asserts every response is matched to its own request. Do not pin a fork of a dependency for a core correctness fix; if you must patch, vendor the patch with a test that fails without it.

### 1.2 Modbus TCP requests are **not serialised** — a live bug at HEAD `[V-src]`

In `evok/modbus_unipi.py` (current HEAD), `EvokModbusSerialClient.__block` wraps every operation in `async with self.lock:`. `EvokModbusTcpClient.__block` **creates `self.lock` but never acquires it**:

```python
    def __block(self, operation: Callable):
        async def ret(*args, **kwargs):
            start_stamp = time.time()
            while not self.connected and time.time() - start_stamp < self.__timeout:
                await asyncio.sleep(0.001)
            aret = await operation(*args, **kwargs)          # no `async with self.lock`
```

Combined with issue **#153** (open) — *"Now TCP connections has one bus for all devices in bus. For TCP connection is better create session per device"* `[V]` — every slave on a TCP bus shares one socket with no mutual exclusion. On every Unipi PLC this is the *primary* I/O path: EVOK 3 reaches the mainboard through a local Modbus TCP server (`LOCAL_TCP` → `127.0.0.1:502`/`:50200`, visible in the logs of #199, #212, #214). So concurrent interleaved transactions on the main board's socket are the normal case — which is precisely the condition under which §1.1's tid bug bites.

> **Lesson.** Serialise per *transport*, not per device, and make it structural: a request queue owned by the connection object, so it is impossible to issue a frame without going through it. RTU needs it for bus arbitration; TCP needs it for transaction correlation. Do not rely on a lock that a caller must remember to take.

### 1.3 One bad device stalls the bus, and a 50-µs `sleep` is the shipped workaround `[V]`

Issue **#210** (open, `kratochvil01`): *"Unstable communication on proxied RS485 with multiple devices"* — with one device on `ttyNS*` it is reliable; add a second and it drops out. The attached log shows an endless flap:

```
ERROR:evok:xS11: Error while scanning: 'NoneType' object has no attribute 'close'
WARNING:evok:Slowing down device: 'xS11'
INFO:evok:Communication with device is back: 'xS11'
```

The traceback bottoms out **inside pymodbus** (`client/base.py:206 async_execute` → `close(reconnect=True)` → `transport.py:419 transport_close` → `self.transport.close()` where `transport` is already `None`) — i.e. a pymodbus timeout-teardown race, surfaced through EVOK's wrapper.

The shipped hotfix (`757da36`, 2025-09-10, released as apt `evok=3.0.6~.test.20250910162043*`) is a single line inserted into the RTU lock wrapper:

```python
await asyncio.sleep(0.00005)  # TODO: THIS IS HOTFIX !!! REMOVE IT !!!
```

**Notes.** (a) 50 µs is far below any RTU inter-frame requirement — it is an *event-loop yield*, not a bus turnaround delay; it changes task scheduling enough to dodge the pymodbus race. (b) `757da36` is **not on `main`** (its parent is `main`'s HEAD `47c95c8`), so it lives on an unmerged branch shipped only as a `.test.` package. (c) A user in the thread reports the hotfix alone was insufficient (*"With the delay alone I did not get to keep the modules staying up"*) and that they also had to wrap `transport.py` and the modbus await in try/except.

Related, and telling: `879151f` / `78f707b` / `47bcae6` (2019-04-23) — *"Fixed dead-time generation on RS485 modbus"*, **reverted the same day**, then re-landed. RTU inter-frame timing was fought over and never settled.

> **Lesson.** RS-485 turnaround/inter-frame timing (t3.5, t1.5) is a *protocol requirement*, not a scheduling accident. Implement it explicitly with a real timestamp-based gate on the port (`lastFrameEndNs + t35 > now → wait`), configurable per bus, derived from baud rate. A "sleep 50 µs" workaround with `REMOVE IT !!!` in the comment is the signature of a race being papered over rather than modelled.

### 1.4 Per-device backoff exists but is defeated by partial recovery `[V-src]`

`modbus_slave.py::scan_boards` has a genuinely good idea — exponential backoff plus first-error-only logging:

```python
        except Exception as E:
            if not self.scan_errors:
                logger.error(f"{self.circuit}: Error while scanning: {E}")
                logger.warning(f"Slowing down device: '{self.circuit}'")
            self.scan_errors += 1
        ...
            interval = min(self.scan_interval*(2**self.scan_errors), 120)
```

But `scan_errors` is reset to 0 on **any** successful pass. On a marginal bus that alternates success/failure, the counter never accumulates, backoff never engages, and the log flaps `Slowing down` / `Communication is back` forever — exactly the log in #210. `[I]` on the causal link; the log pattern is `[V]`.

Issue **#123** (closed) is the same theme one level up: *"if not all devices communicate… some writes, e.g. RO, will fail"* and after ~10 s with 3 of 6 devices gone the **hardware master watchdog fired** (2.5 s MWD on an xS11), i.e. an unreachable *peer* caused an output-dropping event on a *healthy* device. The maintainer's fix: *"If a timeout now occurs when reading a modbus registry group, Evok will slow down all groups of that device"* `[V]`.

Issue **#74** (open since ~2018): *"EVOK currently processes Modbus requests and cache updates asynchronously in the main server thread, which can cause delays when using multiple RS485 devices along with a primary Neuron device"* `[V]`.

> **Lessons.**
> - Use a proper circuit breaker with hysteresis: require *N consecutive* successes to close, decay the error count rather than zeroing it, and add jitter. Track `consecutiveFailures`, `lastSuccessAt`, and `state: healthy|degraded|quarantined` per slave.
> - Budget the bus. A slave in `quarantined` gets one probe per backoff interval; healthy slaves keep their scan slot. Never let a dead peer consume the bus's time budget — that is how a hardware watchdog gets starved into firing.
> - Keep the "log once per state transition" idea from EVOK; add a periodic rollup (`N errors in the last 10 min`). Unbounded per-cycle error logging is how #66 filled a disk.

### 1.5 One failing register block discards the whole scan pass — including events already collected `[V-src]`

`ModbusCacheMap.do_scan` iterates register blocks with `try: … finally:` and **no `except`**. An exception on block *k* propagates out of `do_scan`, so blocks *k+1…n* are never read that pass **and** the `changeset` accumulated from blocks *0…k-1* is dropped before `devents.status(proxy)` is reached. Real state changes on healthy registers are silently lost whenever a later block times out.

> **Lesson.** Per-block error isolation. Collect `{ok, err}` per block, always emit the changes you did observe, and report per-block health. A partial read should degrade coverage, never discard already-observed truth.

### 1.6 Timeouts and reconnect were tuned by trial and error `[V]`

- `710b4fa` (2023-11-06): *"zmena Modbus RTU timeout 4s (default) >> 1s"* — the shipped default was a **4-second** blocking timeout, meaning a single dead slave could stall the shared bus lock for 4 s per attempt.
- `b53a4ed` (2024-01-15): *"Znovupridan MB RTU autoreconnect"* — RTU auto-reconnect had to be **re-added** after being lost; the same commit removed a stray `traceback.print_exc()`.
- `2a5a4d7` (2024-02-20) introduced `while not self.connected: await asyncio.sleep(0.001)` — an **unbounded** busy-wait before every TCP operation. `66f874b` (2024-08-28) bounded it with a 1 s timeout. The busy-wait loop still exists in the RTU path at HEAD, with a bare `# TODO` next to it. `[V-src]`
- `80c95f1` (2024-01-04): *"FIX: sdilena cache mapa mezi slave-id"* — `copy(modbus_reg_map)` → `deepcopy(...)`. A **shallow copy meant every slave on a bus shared the same register-value lists**: one device's readings appeared as another's. Classic aliasing bug from reusing a parsed HW-definition dict across device instances.

> **Lessons.** Every wait must have a deadline. Never busy-poll a connection flag — await a connection-state promise. And make loaded hardware definitions **immutable** (`Object.freeze` / `readonly` types, or parse-to-fresh-instance) so per-device mutable state can never be shared by accident; `80c95f1` is a bug TypeScript's `readonly` would have prevented at compile time.

---

## 2. Concurrency and event loop

### 2.1 "Fix websocket blocking requests" (#190 / PR #191) — the real story `[V]`

The issue is far worse than the title suggests. Reporter (the maintainer) `[V]`:
- *"the protocol gets stuck when writing to the device fails"* — the socket stays open, requests are accepted but not executed;
- on recovery, *"Evok then executes all the requests sent and received during the period of protocol inactivity in one moment"* — the whole backlog fires at once, replaying stale commands onto physical outputs;
- *"In the stuck state, Evok does not control even devices on another bus"* — **one unreachable slave blocks every bus and every client.**

Mechanism `[I], well-supported by [V] tracebacks`: `WsHandler.on_message` is `async` and Tornado processes one message per connection to completion; the command path `await func(value)` reaches `client.write_coil` → the shared bus lock → a pymodbus timeout/teardown that can hang. Everything behind it queues.

The merged fix (`950a9e3`) is **one line, and unrelated to blocking**:

```python
-                        if message["devices"][0] == "default":
+                        if len(message["devices"]) and message["devices"][0] == "default":
```

— an `IndexError` on an empty `filter` list. The commit body says *"Fix error while setting empty filter on ws"*. **The headline bug (blocking + backlog replay + cross-bus blocking) was closed by a fix for a different bug.** Treat #190's described behaviour as still present in 3.0.6.

> **Lessons.**
> - **Never let device I/O run inside the socket's message-handling path.** Accept a command, validate it, enqueue it, return a correlation id, and let a per-device worker execute it. WS reads must never await the bus.
> - **Commands must expire.** Every queued write carries a deadline; on timeout it is rejected with an error to the client, not replayed later. Replaying a 40-second-old "close relay" onto real hardware is a safety issue, not just a latency issue.
> - Bound the per-device command queue and coalesce/reject rather than buffer without limit.
> - Isolate buses: a per-bus worker means an RS485 stall cannot touch a TCP device.

### 2.2 WebSocket writes are fire-and-forget with no backpressure — the #141 mechanism `[V-src]` + `[V]`

`evok/evok.py::WsHandler.on_event`:

```python
    def on_event(self, device):
        try:
            if len(self.filter) == 1 and self.filter[0] == "default":
                self.write_message(json.dumps(device.full()))   # not awaited
```

Tornado's `write_message` returns a future; not awaiting it means (a) the send buffer grows without limit for a slow/dead client, and (b) write failures become unretrieved future exceptions. Layered on top, `devents.py` wraps the entire dispatch in a bare swallow:

```python
        def newstatus(device, **kwarg):
            try:
                callback(device, kwarg)
            except:
                pass
```

Issue **#141** `[V]`: a wind sensor on a Unipi 1.1 DI generating rapid edges → *"after a while the evok api goes dead and does not communicate any input changes any more, not only for 1-12 but for all inputs"*; the web UI freezes too; `service evok restart` **plus** `nginx restart` does not recover it — *"reboot is the only way out"*. The reporter's own prescription is the right one: *"evok should suspend sending input changes when websocket (or other webhook) buffers are running full until they are empty again, but not die trying."* It was closed after a fix in a **different** package (`unipi-one-modbus` 0.24.0, a counter bug), with verification by leaf-blower, not by load test — so the backpressure question was never actually answered.

> **Lessons.**
> - Await or explicitly manage every socket write. Track per-client queue depth; on overflow, **drop to a coalesced snapshot** (per-circuit last-value-wins) and set a `resynced: true` flag so the client knows it missed edges — never drop the connection silently, never buffer unboundedly.
> - Counters exist precisely so that dropped edges are recoverable. Guarantee counter fidelity and you are free to shed change events under load.
> - Ban bare `catch {}` on the event dispatch path. Log-and-count with dedup; a silently swallowed delivery error is an outage you will never diagnose.
> - Load-test the fan-out path in CI: N clients × M Hz change rate, assert bounded RSS and bounded latency.

### 2.3 Webhook delivery: unbounded in-flight requests, and it is broken for 1-Wire `[V-src]`

`WhHandler.on_event`:

```python
    def on_event(self, device):
        dev_all = device.full()
        outp = []
        for single_dev in dev_all:                 # <-- outside the try block
            if single_dev['dev'] in self.allowed_types:
```

Modbus events arrive wrapped in a `Proxy` whose `full()` returns a **list**. 1-Wire events do not — `owdevice.py` calls `devents.status(self)` directly, so `full()` returns a **dict**; iterating a dict yields string keys and `single_dev['dev']` raises `TypeError`. `WsHandler.on_event` guards this (`if 'dev' in dev_all: dev_all = [dev_all]`); `WhHandler` does not. The exception escapes the handler's `try` and is swallowed by `devents`' bare `except: pass`. **Net effect: webhooks silently never fire for 1-Wire sensors.** `[V-src]`, `[I]` on "never" (holds for every 1-Wire event path in `owdevice.py`).

Also: `self.http_client.fetch(...)` is never awaited and has no concurrency cap of its own, so a slow webhook endpoint accumulates in-flight requests inside Tornado's client queue. `[V-src]`

Historical: **#91** — webhook POSTs sent a JSON body with `Content-Type: application/x-www-form-urlencoded`; fixed in 3.0.1 (`85dc7e1`). **`0d84318`** (2018) — *"Fixed post failing for webhook events."*

> **Lessons.** One invariant event envelope for *every* source (Modbus, 1-Wire, virtual) — always `{ ts, seq, changes: Device[] }`, never a bare object. Then the fan-out code has exactly one shape to handle and this entire bug class disappears. Webhook delivery gets its own bounded queue, concurrency limit, timeout, retry-with-backoff, and a circuit breaker; a slow subscriber must never influence the scan loop.

### 2.4 Device-type filtering is broken for alias names — a live bug `[V-src]`

`devices.py` defines `devtype_altnames = {'input': 'di', 'relay': 'ro', 'wd': 'watchdog', 'temp': 'sensor', …}`. `WsHandler.on_message` accepts alt-names into the filter:

```python
if (str(single_dev) in num_to_devtype_name.values()) or (str(single_dev) in devtype_altnames):
    devices += [single_dev]
```

…but the filter is later applied against the **canonical** name: `if single_dev['dev'] in self.filter`. So `{"cmd":"filter","devices":["input"]}` is accepted without error and then matches **nothing**. The same normalisation gap exists in `WhHandler` (`single_dev['dev'] in self.allowed_types`) — and the **shipped default config** in issue #214 uses exactly the old names:

```yaml
webhook:
  device_mask: ["input","wd"]
```

So the documented default webhook mask matches zero devices on EVOK 3. `[V-src]` for the code, `[V]` for the shipped config text.

Also in `cmd:all` with `all_filtered: true`, the code compares a **device dict** against a list of type **strings** (`if added_result is not None and added_result in self.filter`) — always false, returning an empty list. `[V-src]`

> **Lesson.** Normalise identifiers **once**, at the parse/ingress boundary, into a canonical internal form; never compare user-supplied strings against internal ones deeper in the stack. Reject unknown filter values loudly (return an error frame) instead of accepting a filter that silently matches nothing — "accepted but ineffective" is the worst failure mode for a subscription API. In TS, make the filter a `Set<DeviceKind>` where `DeviceKind` is a union type, so a raw string cannot enter.

### 2.5 Closing the last WebSocket can stop Modbus polling `[V-src]`

```python
    def on_close(self):
        if ("all" in registered_ws) and (self in registered_ws["all"]):
            registered_ws["all"].remove(self)
            if len(registered_ws["all"]) == 0:
                for neuron in Devices.by_int(MODBUS_SLAVE):
                    neuron.stop_scanning()
```

`stop_scanning()` sets `do_scanning = False` when `scan_enabled` is false. So for devices configured with `scan_enabled: false`, the **last WS client disconnecting stops hardware polling for every Modbus slave**, and nothing restarts it on the next connect (`start_scanning` is only called at startup, `evok.py:528`). REST then serves an indefinitely stale cache with no staleness marker. Additionally, `registered_ws["all"]` mixes `WsHandler` and `WhHandler` objects, so whether this triggers depends on whether webhooks are enabled — an invisible coupling between two unrelated config keys.

> **Lesson.** Polling policy is a property of the *device*, never of who happens to be listening. If you want on-demand polling, express it as an explicit per-device mode with a documented cache TTL, and never mix subscriber types in one registry. Don't tie hardware behaviour to connection counts.

### 2.6 Idle CPU: a 10 kHz poll fallback and no on-demand path `[V-src]` + `[V]`

`ModbusSlave.__init__`:
```python
        if scan_freq == 0:
            self.scan_interval = 0.0001
            # scan_interval cannot be zero!! (slowing down device)
```
`scan_frequency: 0` yields a **0.1 ms** scan interval — a 10 kHz poll loop.

Issue **#199** (closed *not planned*) `[V]`: ~16.6 % of a core at idle on an RPi 3B+ with one board and one DS18B20. Maintainer: *"Evok is never idle, it always reads the data as defined in the config file… you may lower the scan_frequency"*; on-demand reads *"is not currently planned"*. Forum corroboration: EVOK *"is built on the Tornado webserver, which… is primarily single-threaded"*.

Combined with issue **#43** `[V]` — a port conflict caused systemd to restart EVOK immediately and forever, presenting as 100 % CPU; fixed with `StartLimitIntervalSec`/`StartLimitBurst`, i.e. **in the unit file, not the program**.

> **Lessons.** Reject nonsensical config at load time (`scan_frequency: 0` must be an error or an explicit `mode: onDemand`, never a 10 kHz loop). Support three per-device modes: `poll(hz)`, `onDemand(cacheTtl)`, and `event` where hardware supports it. Fail fast and exit non-zero **once** on `EADDRINUSE`/config errors, with the offending port and a hint — and implement your own restart-rate limiting rather than delegating it entirely to systemd. Ship an internal metrics endpoint (event-loop lag, scan latency p50/p99, per-bus transaction rate, WS client count and queue depths) so "high CPU" is answerable in one request instead of a forum thread.

---

## 3. Startup, autodetect, and hot-plug

### 3.1 Discovery is a one-shot startup step — the most consequential architectural flaw `[V]`

Issue **#192** (open): *"If a device is defined in the configuration, a communication test is performed at startup. If this test fails, the device is not registered in the Evok system and is not available even after reconnecting the device."* Repro: configure device → unplug → start EVOK → plug in → device never appears. `[V]`

Issue **#164** (open): *"The current initialization of Evok is synchronous and the steps for switching to asynchronous mode have been performed recently. This solution is of historical origin. It is necessary to modify the initialization cycle… so that it runs asynchronously from the beginning."* PR **#193** ("Rework Evok initialize") is still a **draft**. `[V]`

The code path confirms it: `ModbusSlave.readboards()` catches `ConnectionException`, logs *"No board detected"*, and returns — no retry, no re-registration. `[V-src]`

This single design choice generates a decade of downstream reports: the `'NoneType' object has no attribute 'do_scan'` family (#42, #66, #68, and the forum's most-reported error), *"Invalid device circuit number 1_01"* (#83, #130), Axon/Neuron *"UI not showing input/output status"* (#82), *"no boards detected after apt-get upgrade"* (#51), *"Service should start even when DS2482 is not present"* (#18), and the community's `@reboot sleep 200 && service evok restart` culture.

> **Lesson — the single most important one in this report.** **Discovery is a continuous, supervised, retrying process; the device tree is hot-mutable.** Model each configured device with a lifecycle (`unknown → probing → online → degraded → offline`) and keep probing offline devices on a backoff schedule. Expose every configured device in the API *always*, with its state, so "configured but unreachable" is a first-class, queryable answer instead of an empty list. Registration must be idempotent so a device appearing at t+10 min behaves identically to one present at t=0. Emit `device.online` / `device.offline` events. If this is right, a `sleep 200` cron restart never needs to be invented.

### 3.2 Fatal misconfiguration vs. transient absence are not distinguished `[V]`

`readboards` distinguishes `ConnectionException` (log and continue) from everything else (`logger.exception(str(E)); pass`). But an unsupported model raises `KeyError` inside the same try — so a **typo in `model:`** is logged at the same severity as a cable being unplugged, and the process continues serving an empty device list. `[V-src]`

Forum-verified consequences: `NO NEURON EEPROM DATA DETECTED, EXITING` → systemd `Start request repeated too quickly`; kernel-module skew after `apt upgrade` fixed by `apt-get install unipi-kernel-modules`; a 64-bit-kernel/pigpio mismatch surfacing as *"Invalid device circuit number 1"*; issue #212 where the real failure was the **downstream** `unipi-one-modbus` service crash-looping on `Gpiochip … [Errno 16] Device or resource busy`, which EVOK reported only as `[Errno 111] Connect call failed`. `[V]`

> **Lessons.** Two error classes, two behaviours: **config/dependency errors** → validate everything up front, report *all* of them at once with file/line/JSON-pointer, exit non-zero, never crash-loop. **Runtime hardware errors** → stay up, mark the device offline, keep retrying. Ship a `doctor` / `GET /diagnostics` that checks: config schema, port availability, required `/dev` nodes and `/run/unipi-plc` entries, kernel modules and device-tree overlays, board firmware versions against a known-good floor, owserver reachability, and exclusive bus ownership. Unipi maintainers re-typed this checklist into forum posts for years; it belongs in the binary. When an upstream dependency (local Modbus server, owserver) is down, say **which** dependency by name — never leak a bare `ECONNREFUSED`.

### 3.3 Hardware-definition loading edge cases `[V]`

- `a4ea47a` (2018): *"Fixed incorrect hw_definition being loaded depending on the dictionary order"* — device model resolution depended on **dict iteration order**. A nondeterministic wrong-board-map bug.
- **#167** / `a483945`+`6ba9aaa`: *"HW definitions not found - exception handling"* — a missing definitions folder threw instead of reporting.
- `a633e4a` / **#208**: `DataPoint` register type defaulted to nothing; now defaults to holding register. #208: *"Modbus register type is not documented for modbus_features."*
- **#207** (open): *"Invalid watchdog property name in hw definitions"*; **#206** (open): *"No documentation provided for modbus feature LED."*
- `3cb91d7` / `f0d329d`: `unit_register` → `data_point` rename, with a follow-up commit to *"Repair loading data_point class."*
- `d7fee1e`: *"Fix initialize cache map (checking old hw-conf strukture)"* — version-straddling logic inside the loader.
- `06e759a`: *"Fix ws:all command, alias conf version detection."*

> **Lessons.** Validate hardware definitions against a strict schema at load time and **fail the definition, not the process**, reporting the exact file and field. Resolve models by explicit key, never by iteration order. Version the definition format with a real migration chain and a `--check-definitions` CLI mode. Load definitions into frozen, fully-typed structures (see §1.6) — and generate the TypeScript types from the schema so a `watchdog` property typo is a compile error.

### 3.4 Bank/offset arithmetic: the >16-channel overflow — silently writes the *wrong* relay `[V]`

Issue **#209** (open) with **#195** as sub-issue: *"The implementation uses coils for writing and registers for reading, but it fails to handle cases where the channel index exceeds 16."* A user on a Neuron M403 reports the severe form:

> *"Instead of 28 ROs it showed only 16 visible ROs. Worse the `_01…_12` ROs were silently driving coils 116–127 (relays 17–28), not 1–12. The same latent bug exists in the DO and LED parsers."*

Confirmed in source at HEAD: `parse_feature_di` numbers channels as `counter + 1 + start_index`, while `parse_feature_ro`, `parse_feature_do` and `parse_feature_led` use `counter + 1` with **no offset** and read `board_val_reg` without a `// 16` bank stride — so a second feature block of the same type overwrites the first block's circuit names while retaining the second block's coil addresses. `[V-src]`

**This is the worst bug in the corpus**: a named output silently actuates a *different physical relay*. Open since 2025; issue #195 (L403/M403) since before that.

> **Lessons.** Never derive an identity from a loop counter. Compute `{ registerAddress, bitOffset, coilAddress }` in one audited function from `(blockBase, channelIndex)`, with the bank stride (`Math.floor(i/16)`) and the bit mask (`i % 16`) in a single place, exercised by a table-driven test per hardware model. Then **assert uniqueness**: registering two devices with the same circuit id, or two circuits mapping to the same coil, must be a hard startup error. A silent overwrite in a register map is a wiring fault expressed in software.

---

## 4. Counters, debounce, and state consistency

### 4.1 The 32-bit counter is read as two separate cache lookups `[V-src]`

```python
self.regcountervalue = lambda: self.arm.modbus_slave.modbus_cache_map.get_register(1, regcounter)[0] \
                             + (self.arm.modbus_slave.modbus_cache_map.get_register(1, regcounter + 1)[0] << 16)
```

Two independent cache reads of the low and high words. `do_scan` replaces a block's values atomically (`m_reg_group['values'] = vals.registers`), so the pair is consistent **only if both registers live in the same `modbus_register_blocks` entry**. If a HW definition splits them across blocks — or gives the blocks different `frequency` values, which the format explicitly allows — the words come from different points in time and the counter can jump by ±65536 or move backwards at every low-word wrap. `[V-src]` for the code, `[I]` for the tearing consequence (I could not confirm a definition that splits a counter pair).

Supporting history: `c9fa927` *"Fixed DI counter value handling (32bit modbus value set + schema validation)"`; `2996eb0` *"Fixed maximum int value for DI counter in JSON validation"*; `4de0cd7`/`0a67a8d` counter-mode display fixes; the `unipi-one-modbus` counter bug behind #141; forum: *"once the maximum number of counter is reached it is reset to 0"*, and the counter is **not writable** via REST (`Input instance has no attribute '_regcounter'`), with Unipi directing users to raw Modbus TCP instead. `[V]`

> **Lessons.** Read multi-word values from a **single atomic block snapshot** — validate at definition-load time that every multi-register value lies wholly inside one block with one frequency, and reject definitions that violate it. Publish counters with explicit `width` and `wrapAt`, plus a server-computed monotonic `total` (a `bigint` accumulator that survives hardware wrap) alongside the raw register value; clients should never have to implement wrap arithmetic. If a counter can be reset in hardware, expose it; if not, return `422 unsupported_property` with the reason and the alternative — never leak an internal attribute name (`'_regcounter'`) into an API error.

### 4.2 Write-then-read: the API returns the pre-write value `[V]`

Issue **#122** (open, relabelled *enhancement*): *"When sending a API request to set a debounce, counter, etc., the original value is returned in the API response (tested with WS, REST)."* Maintainer: *"Evok returns the last read values… after the writing is finished, reading is not performed immediately."* Related open request **#125**: *"After writing, trigger reading."* `[V]`

> **Lesson.** A write response must reflect reality: either read back the affected register(s) before responding, or return `202 Accepted` with an explicit `pending: true` and a follow-up event when the read-back confirms. Silently echoing stale state is worse than either. (EVOK does have a `pending` field on relays — apply the concept uniformly.)

### 4.3 Mode state is derived but never cleared `[V-src]`

Issue **#121** (closed): *"If ds_mode is set to any other mode than SIMPLE, it cannot be changed or DS can be turned off completely… After saving the configuration and power cycle the controller and Extension, it still cannot be changed – Q.E.D."* `[V]`

At HEAD, `DigitalInput.check_new_data` recomputes `ds_mode` from the polarity/toggle registers but only ever **assigns** `'Inverted'` or `'Toggle'`; when both bits are clear it leaves the previous value in place, so `ds_mode` never returns to `'Simple'`. `[V-src]` — i.e. a residual form of #121 is still latent despite the closure.

> **Lesson.** Derive state as a **total function** of the registers — one pure `decode(registers) => State` with every branch returning a value, never in-place mutation with implicit fall-through. TypeScript exhaustiveness checking on a discriminated union catches exactly this. Never let cached device state drift from what the hardware says.

### 4.4 Value-conversion bug tail `[V]`

`8822a41` negative `unit_register` values; `fe83cd0` negative Brain AI values; `267be74` *"Fix UnitRegister class (wrong valid mask check and value update system)"*; `1cdcbb3` *"FIX float==NaN (invalid json)"* — a NaN reading produced **invalid JSON** on the wire; `8b5e0d2` resistance returning int instead of float; `a1b1666` *"websocket updates not being computed correctly with secondary AIs with index > 0"*; `84647fb`/`6eadb7d` float register decimal places; `348c88b`/`0d2c654` PWM frequency formula (fixed twice); `c3e77d7` PWM mode/value coupling and *"fixed readout of PWM-related values after Evok restart"*; `0964ca4` *"PWM: Force recalc if frequency is changed"*; `a326d00` *"DO: Fix getting other DOs in same section"*; `95` (Unipi 1.1) analog out inverted (0 ↔ 10 V).

> **Lessons.** Sign extension, scaling, and endianness belong in one tested codec layer with a golden table per register type (`i16`, `u16`, `i32`, `u32`, `float`, fixed-point, BCD), including negative and boundary values. Make "no valid value" an explicit `null`/`{valid:false}` in the type system so it can never serialise as `NaN`. And note the PWM lesson: any register set with *derived* values (duty from frequency and prescaler) must be recomputed as a unit and read back after restart — never left as independently-writable fields.

---

## 5. Error reporting and API error shapes

### 5.1 Failed writes returned `success: true` `[V]`

Issue **#183** (closed via PR #185): two scenarios — (a) EVOK can't reach the Modbus server: *"no reply at all, just something in syslog"*; (b) writing to a **non-existent register**: *"returns `"success": true`, mbpoll returns ERROR Slave device or server failure."* Summary: *"Evok does not timeout; Evok does return success."* `[V]`

The fix chain is instructive because it took **three** commits to make errors *exist* at all:
- `07b5dc9` — *"Add raising Exceptions from pymodbus"*: pymodbus returns `ExceptionResponse` / `ModbusIOException` as **return values**, not raises. EVOK had been treating a Modbus exception PDU (illegal data address, slave device failure) as a successful result. Fix: `if type(aret) in exception_classes: raise ModbusException(...)`.
- `66f874b` — bound the pre-write connection wait with a timeout (previously unbounded → no error, just a hang).
- `f2db299` (PR #185) — surface it in the API response.

Note `type(aret) in exception_classes` is an **exact-type** check, so any pymodbus exception subclass slips through. `[V-src]`

> **Lessons.** **A protocol-level error response is a failure, full stop.** Model transport results as a discriminated union (`{ok:true, registers} | {ok:false, kind:'modbusException', code, name} | {ok:false, kind:'timeout'|'io'|'notConnected'}`) so the compiler forbids ignoring the error arm. Never `instanceof`/exact-type-check a library's error taxonomy; normalise it at the adapter boundary. Distinguish, in the API, at least: `bad_request`, `unknown_circuit`, `unsupported_property`, `value_out_of_range`, `device_offline`, `bus_timeout`, `modbus_exception(code)`, `internal`. Map them to stable HTTP codes and a stable JSON error object, and cover each with an integration test that *forces* the failure (dead server, bad coil address, offline slave) — #183's scenarios make an excellent starting test matrix.

### 5.2 Error-shape and diagnosability fixes `[V]`

`d55cda2`/`7d06ccc` — JSON-RPC now returns *Invalid params* on an invalid circuit; **#58** *"Internal Error response when request on non-existent device issued"*; **#57** `TypeError: 'NoneType' object is not subscriptable` on `relay_set` over JSON-RPC; `d55bf51` *"Change behavior on Exception during restapi GET"*; `482e29f`/**#114** *"Exception print in debug mode"* — tracebacks were only added under debug in **2024**; `08a18cf` *"Fixed bug in bulk operation endpoint handler"*; `193911e` *"Fixed broken control logic/indenting, causing unnecessary errors in the EVOK log"*; `d8d3fff` (2018) *"Improved error-reporting behaviour when ModBus map fails a scan pass"*; **#13** *"Set proper logging levels"*; **#66** *"evok.log grows uncontrollably"*; **#93** *"unipi-modbus-tools 1.2.38 fills harddisk with logs"*; **#200** (open) *"Evok does not handle not running owserver properly"* — a 60-line nested `ExceptionGroup` traceback where the actionable fact is `ConnectionRefusedError: [Errno 111] … ('127.0.0.1', 4304)`. Reporter's ask: *"Evok complains about owserver not running."*

Also: **#149** *"Add authentication for API"* is **open** — and `WsHandler.check_origin` unconditionally `return True`. `[V-src]` The default listen address is `127.0.0.1` with nginx in front, which is the only thing standing between an unauthenticated write API and the network.

> **Lessons.** Structured logging (JSON, with `bus`, `device`, `circuit`, `errorKind` fields), per-key rate limiting and dedup, rotation with a size cap by default, and never truncate the log on boot. Translate every dependency failure into one operator-actionable line — *"1-Wire disabled: owserver not reachable at 127.0.0.1:4304 (connection refused); is `owserver` running?"* — and keep the raw stack behind a debug flag. Decide authentication and origin policy on day one; retrofitting auth onto an API with a decade of unauthenticated clients is a migration nobody wants.

---

## 6. WebSocket / subscription lifecycle and payload contract

### 6.1 Payload shape has never been invariant `[V]`

- **#71** *"EVOK WebSocket inconsistences"*: setting one relay published **all relays in that group**, *"causing an overload of messages on the websocket"*; LED changes on an extension emitted nothing; and a contributor found *"the websocket 'full' command… returns a dictionary rather then a list containing a dictionary so if you are processing all the incoming message as a list you miss the 'full' messages."* A maintainer confirmed: *"There is a bug in ws return value format for Unipi1.x. Since the fix is an api-changing modification, it will be introduced in the following major version release."*
- **#44**: LED events emitted only for `1_01`.
- **#36**, **#72**, `4c308bc`/`0f6351b`/`53e922a` (Dec 2018, three commits in four days) — `cmd:all` filtering behaviour was changed, broken, restored, and re-defaulted.
- **#163** (open): *"more comprehensive filter possibility with web_socket."*
- Third-party clients crash on it: `TypeError: message.forEach is not a function` (`node-red-contrib-unipi-evok` #8, still open); *"Evok sending updates as array. Sometimes one dimensional / sometimes multidimensional"* (`pimatic-unipi-evok` #12).
- A user's *"missing events on digital inputs"* on a Neuron L203 turned out to be coalescing: *"The problem was me not detecting multiple messages in the same payload from the Websocket node."* (forum topic/965)
- Renames broke the ecosystem: `relay`→`ro`, `input`→`di` (PR #158, issue #157), `temp`→`1wire`/`sensor`, `unit_register`→`data_point`.
- **#214** (open) is a fresh instance: Modbus `register` updates reach REST but never the WebSocket. **Root cause confirmed in source:** `parse_feature_register` is the *only* feature parser that never calls `__register_eventable_device`, so `Register` devices are absent from `modbus_slave.eventable_devices` and `do_scan` never evaluates them for changes. `[V-src]` (The reporter's PR #215 is open; the maintainer replied *"this is not a supported device type anymore."*)

Forum-side lifecycle gaps `[V]`: no keepalive pings (*"The websocket interface doesn't have keepalive pings enabled"*), so users send `cmd:all` every 60 s as a heartbeat — a full-state dump abused as a ping; filter state is silently lost on reconnect; disconnect policy is inherited from Tornado defaults rather than specified; ~15 s post-boot dead window; unexplained drops with no client-visible reason (forum topic/1404, unresolved); and the WS command surface is not isomorphic with REST (*"WebSocket API… does not support setting aliases, or indeed many other properties"*).

> **Lessons.**
> - **One frame envelope, always, from every source:** `{ v: 1, type: "change"|"snapshot"|"pong"|"error", ts, seq, changes: Device[] }`. `changes` is always an array, even for one device. Define it once in TS and validate outbound frames in dev/test builds so a new event source physically cannot emit a different shape.
> - **Monotonic `seq` per connection.** Clients detect gaps and request a resync; you are then free to coalesce under load (§2.2) without ever silently losing edges.
> - **Protocol ping/pong on a timer** regardless of traffic, plus an explicit `resync`/`snapshot` command. Always close with a code and reason, and log it.
> - **Echo the effective subscription** on connect and after every `filter` change, and reject unknown filter values (§2.4). A client should never have to guess whether its filter took.
> - **Registering a device as event-emitting must not be opt-in per feature type.** Build the eventable set from the device registry itself, or make `register()` require an explicit `eventable: true|false` so omission is a type error — that is #214 designed out of existence.
> - **Stable opaque ids** decoupled from human labels, `{ id, kind, family, busPath, label, aliases[] }`, plus a versioned API (`/api/v1`) and old type names retained as documented aliases for one major version. The `relay`→`ro` rename broke every downstream integration in the ecosystem, and the cost was avoidable.
> - **REST and WS share one command schema and one handler.** Two divergent surfaces guarantees the WS one rots.

---

## 7. Config and aliases

- **#119** (closed): the alias file format and the API representation disagreed — file used `Kitchen: input_1_02`, API used `{circuit, devtype}` with a numeric devtype. Fixed by `127000a`.
- Alias handling churn: `802b631` *"Remove prefix `al_` from aliases"* (a naming convention users had been told was mandatory); `3247fc3` *"Fix mapping adapter of aliases"*; `1f660d3`, `d772a7f` *"Fixed alias list file sync when set for ULED instance"*; `3b18ed3` — alt-names now checked during alias devtype validation, and saving an unchanged alias config no longer returns an error; **#80** *"Aliases do not work on UniPi 1"*; **#86** *"Web control panel alias setting error."*
- Version straddling is handled with warnings at runtime rather than a migration: `Aliases.__init__` does `logger.warning(f"Aliases: Detected old devtype '{key}'! Upgrading...")` `[V-src]`, and `06e759a` fixes *"alias conf version detection."*
- Persistence is not atomic: `save_aliases` does `open(path, 'w+')` then `yfile.write(yaml.dump(...))` — truncate-then-write with no temp file, no `fsync`, no rename. A power cut mid-write leaves a truncated or empty alias file. `[V-src]` (This is the plausible mechanism behind community "aliases lost" reports; the "saved 5 minutes after change" claim I could **not** verify — treat as unverified.) The API does expose a force-save (`set_force_save`) and a dirty callback, which implies deferred writes. `[V-src]`
- An alias referring to a circuit absent from the current hardware raises per-entry: forum-verified `Invalid device circuit number 1_01 … Exception`; `register_device` catches it and logs *"Error on setting saved alias"*. `[V-src]`
- Config ergonomics that generated support load `[V]`: v2's `evok.conf` opened with `#!!! Do not use '#' for comments !!!` (comments were `;`), carried `config_version = 2.5 ; DO NOT CHANGE!`, shipped `use_schema_verification = False` because enabling it *"RESULTS IN A SIGNIFICANT INCREASE IN LATENCY"*, and `log_file = /var/log/evok.log ; will be cleared on boot`. v3 moved to YAML with `evok.d/` includes and an `autogen.yaml` (`1be8a87`, `96e7e7e`, `aa0c507`) — an improvement — but `105d95d`…`fab6b9a` are **ten consecutive commits** on one day all titled *"Fix autodetection nginx"*, i.e. install-time platform autodetection was pure trial and error.
- **#197** (open): *"Provide an example of API configuration"*; **#28**: *"port config parameter is ignored"*; **#131** (open): *"Message if Modbus address conflict occurs"* — duplicate slave ids are not detected.

> **Lessons.** Aliases and other user data are **durable state**: write via temp-file + `fsync` + atomic `rename`, synchronously on change (or with an explicit, documented, bounded flush window plus flush-on-shutdown). One canonical representation shared by file and API — derive both from the same schema. Validation always on and always cheap (a compiled JSON-schema/Zod validator costs microseconds; there is no excuse for an off-by-default validator). Real migrations with a version chain and a `--migrate` command, not runtime "Detected old devtype! Upgrading..." warnings. Aliases that don't resolve against current hardware are **warnings in a diagnostics list, retained** so a later hardware change re-binds them — never per-entry exceptions, never silently dropped. Detect duplicate slave ids, duplicate circuit names, and duplicate coil/register mappings at startup and refuse to run (§3.4).

---

## 8. 1-Wire / OWFS

- **#101** (closed, fixed in 3.0.1): *"no 1-wire sensors will read values when one sensors is missing"* — one configured-but-absent DS18B20 froze **all** sensors; the working sensor *"loaded its value just once… Neither value nor timestamp refreshes"*, and commenting out the missing one restored it. Reporter: *"I think that situation, when one of the sensors is damaged/removed/stolen/… and others stop working is not good."* `[V]`
- **#200** (open): owserver not running → a 60-line nested `ExceptionGroup` and no usable message (§5.2). `[V]`
- **#187**, **#212**, **#177**, **#162**: recurring "1-Wire shows no devices" on new OS releases and platforms. In #212 the presence of 1-Wire hardware caused the *downstream* `unipi-one-modbus` service to crash-loop on `Gpiochip … Device or resource busy`, which surfaced through EVOK as `Failed to connect [Errno 111]` and an empty UI — a bus-ownership conflict presented as a connection error. `[V]`
- **#46** / forum: `DS2482-100 bus master reconnected` every ~20 s, indefinitely.
- **#30** (closed *wontfix*): *"websocket event for 1-Wire devices hangs after 1 - 2 weeks"* — then REST returned *"allways the same"* value and timestamp, `systemctl restart evok` failed, warm reboot didn't help, only a **cold power cycle** recovered it. Maintainer diagnosed I²C interference and closed it. `[V]` Whatever the hardware cause, the software behaviour — serving a frozen value for days with no staleness signal — is a software defect.
- Forum-verified: the 1-Wire worker process **dying** on `exNoController` / `exUnknownSensor: '/uncached'` while EVOK kept running, leaving temperatures frozen forever; 1-Wire driver exclusivity with CODESYS/Mervis.
- Implementation churn: `78c41e4` swapped `python-ow` for the `onewire` pip package for Bullseye availability; `c677525`/`b7ce314` *"Fixed Exception handling in 1-Wire module and ow_bus reset"*; `13ea264`, `dd93345` `reset_bus`/`do_reset` renames; `d1db494` *"Fix 1W device types support"*; `8ab85ab` *"Workaround incompatibility of cython 3 and pyyaml pip packages."*

Current EVOK 3 does better in places: `owdevice.py::poll` has a per-sensor `lost` flag with edge detection (`if not mysensor.lost: mysensor.set_lost()`), a shared `bus_lock`, and a `DeviceNotFound` handler. `[V-src]` But the outer `run()` builds the OWFS task group in a way that an `add_server` failure tears the whole group down (#200's traceback), and `mon`'s `except Exception: pass` swallows unknown-device errors.

> **Lessons.** Each bus is a **supervised child** with its own lifecycle (`starting|up|degraded|down`), automatic restart with backoff, an error counter, and a state visible in the API — a bus worker dying must never be silent. **Per-device isolation and quarantine**: N consecutive failures → quarantine with slow retry; one missing sensor can never stall the others (#101, #4.4-community). **Staleness is part of the data model**: every reading carries `value`, `readAt`, `age`, `stale` — the single change that eliminates #30, #101, the forum's frozen-temperature reports, and the external "no update in 10 min" monitors users bolted on, and it is what open issue **#201** asks for verbatim (*"Value last communication timestamp… Value communication flag (ok, timeout, error…)"*). Prefer talking to the 1-Wire master directly (or the kernel's `/sys/bus/w1`) over inheriting OWFS semantics; if you do wrap `owserver`, treat it as an optional dependency whose absence is a one-line warning and a `degraded` bus, never a startup traceback. Declare exclusive bus ownership and refuse to start a bus you cannot own, naming the conflict.

---

## 9. Design lessons for `evok-node`

Ordered by how much real-world pain each one prevents.

**Correctness of the hardware map (highest severity — these actuate the wrong physical output)**
1. **Single audited address-computation function** per feature type: `(blockBase, channelIndex) → {registerAddress, bankOffset, bitMask, coilAddress}`, with the `/16` bank stride and `%16` mask in exactly one place, and a table-driven test per hardware model. Then **assert global uniqueness** of circuit ids and of coil/register mappings at startup; a collision is a fatal config error. (#209, #195)
2. **Own the request↔response correlation.** Explicit `Map<number, PendingRequest>` with `has()` semantics, plus a property test that crosses the 0xFFFF→0 tid boundary. (pymodbus TID overflow)
3. **Atomic multi-word reads.** Validate at definition-load that any 32-bit value lies wholly within one register block at one frequency; publish `width`/`wrapAt` and a server-side monotonic `bigint` total. (§4.1)
4. **Immutable hardware definitions** (frozen, `readonly`, types generated from the schema) so per-device state can never be aliased. (`80c95f1`)
5. **Total decode functions.** `decode(registers) => State` with exhaustive unions, never in-place mutation with fall-through. (#121)

**Transport reliability**
6. **Serialise per transport, structurally** — a queue owned by the connection, so a frame cannot bypass it. (§1.2)
7. **Explicit RS-485 timing**: t3.5/t1.5 gates computed from baud rate against real timestamps. No µs `sleep` hacks. (§1.3)
8. **Circuit breaker with hysteresis and a bus time budget**: `consecutiveFailures`, `lastSuccessAt`, `healthy|degraded|quarantined`; require N consecutive successes to close; quarantined slaves get one probe per interval and never consume the healthy devices' slots. (#123, #210, §1.4)
9. **Per-block error isolation** — always emit the changes you did observe; a failed block degrades coverage, never truth. (§1.5)
10. **Every wait has a deadline.** No unbounded `while (!connected)` loops; await a connection-state promise. (`2a5a4d7`/`66f874b`)
11. **Transport results are discriminated unions.** A Modbus exception PDU is a failure; the compiler must forbid ignoring it. Normalise library error taxonomies at the adapter boundary — never exact-type-check them. (#183)

**Concurrency and delivery**
12. **Device I/O never runs in a socket handler.** Accept → validate → enqueue → correlation id; per-device worker executes. Per-bus isolation so an RS485 stall cannot touch a TCP device. (#190)
13. **Commands expire.** Deadline per queued write; timeout → error to the client. Never replay a stale write onto hardware. (#190)
14. **Backpressure by design.** Await/manage every socket write; bounded per-client queue; on overflow degrade to a coalesced last-value-wins snapshot with `resynced: true`. Load-test N clients × M Hz in CI with assertions on RSS and latency. (#141)
15. **No bare catch on the event path.** Log-and-count with dedup; never `except: pass`. (`devents.py`)
16. **Bounded, isolated webhook delivery**: own queue, concurrency cap, timeout, retry-with-backoff, circuit breaker. A slow subscriber cannot influence the scan loop. (§2.3)

**API contract**
17. **One invariant frame envelope** `{v, type, ts, seq, changes: Device[]}` from every source, always an array, validated in dev builds. (#71, #214, third-party crashes)
18. **Monotonic `seq` + explicit `resync`** so coalescing is safe and gaps are detectable. (forum topic/965)
19. **Protocol ping/pong, close codes with reasons, subscription echo, loud rejection of unknown filter values.** Retire the `cmd:all`-as-heartbeat hack. (§2.4, §6)
20. **Stable opaque ids** separate from labels; versioned API; old type names as documented aliases for one major version. (`relay`→`ro`)
21. **REST and WS share one command schema and one handler.** (forum: aliases unsettable over WS)
22. **Eventability is not opt-in per feature parser** — derive it from the registry, or make `eventable` a required field. (#214)
23. **Rich, typed error taxonomy** mapped to stable HTTP codes; integration tests that force each failure. Never leak internal attribute names. (#183, #58, #57, forum `_regcounter`)
24. **Write responses reflect reality**: read-back, or `202` + `pending` + a confirming event. (#122, #125)
25. **Staleness in the data model**: `value`, `readAt`, `age`, `stale` on every reading; explicit lifecycle state on every device and bus. This is open issue **#201**, and it is the single highest-leverage addition. (#30, #101, #201)
26. **Decide auth and origin policy on day one.** (#149; `check_origin` returning `true`)

**Lifecycle and operability**
27. **Discovery is continuous and supervised; the device tree is hot-mutable.** Configured devices always appear in the API with a state; offline devices are re-probed on backoff; registration is idempotent; `device.online`/`offline` events. **This is the most important item in the report** — it eliminates #192, #164, #42, #66, #68, #82, #83, #130, #51, #18 and the whole `sleep 200 && restart` culture. (#192, #164)
28. **Two error classes, two behaviours.** Config/dependency errors: validate everything, report all at once with file/pointer, exit non-zero **once**, self-rate-limit restarts. Runtime hardware errors: stay up, mark offline, keep retrying. Never crash-loop on `EADDRINUSE`. (#43, forum topic/516)
29. **`doctor` / `GET /diagnostics`**: config schema, port availability, `/dev` + `/run/unipi-plc` nodes, kernel modules, device-tree overlays, board firmware vs. a known-good floor, owserver reachability, exclusive bus ownership — with pass/fail per check. Replaces a decade of re-typed forum checklists. (#212, forum topics 500/516/545/557/1351/1436)
30. **Name the failing dependency.** *"1-Wire disabled: owserver unreachable at 127.0.0.1:4304"*, not a nested `ExceptionGroup`. (#200)
31. **Supervised bus workers** with restart+backoff and API-visible state; a dying bus task is never silent. (forum 1-Wire worker deaths)
32. **Structured logs, dedup + rate limiting, periodic rollups, size-capped rotation, never truncate on boot.** (#66, #93, #13, forum `evok.conf`)
33. **Metrics endpoint**: event-loop lag, per-bus transaction rate and latency p50/p99, scan-cycle duration, per-slave error counts, WS client count and queue depths, uptime, restart count. Makes "high CPU"/"it hangs" answerable in one request. (#199, #68, #74)
34. **Config**: YAML/TOML with unambiguous comments, validation always on, real migrations, strict rejection of nonsensical values (`scan_frequency: 0` is an error, not a 10 kHz loop), duplicate-slave-id detection. (§7, #199, #131)
35. **Durable user data**: temp-file + `fsync` + atomic rename, synchronous on change or with a bounded flush window plus flush-on-shutdown; unresolvable aliases retained as warnings, not exceptions. (§7)
36. **Per-device polling modes** (`poll(hz)` / `onDemand(ttl)` / `event`) as explicit config — never coupled to subscriber counts. (§2.5, #199)
37. **Interlocks in the device layer**, not in clients: declarative mutual-exclusion groups with minimum dwell time, plus per-device command serialisation. A third-party author reports burning out relay outputs by driving a cover's up/down relays together. (`marko2276/ha-unipi-neuron`)
38. **Ship a first-party TS client** with reconnect, backoff and automatic resubscribe, so integrators stop reinventing it five different ways.

**Meta-lesson.** The bug tail here is dominated by *state* problems, not algorithm problems: one-shot initialisation, cache aliasing, torn multi-word reads, unbounded queues, swallowed exceptions, and shapes that vary by code path. A from-scratch TypeScript implementation gets most of these for free **if** the domain is modelled with discriminated unions, `readonly`, exhaustive switches, and one canonical envelope — and gives them all back if the types are `any` at the boundaries. The second meta-lesson: EVOK's own maintainers know most of this. Issues #164 (async init), #192 (hot-plug), #153 (per-device TCP session), #201 (validity flag + timestamp), #74 (bus contention), #131 (address conflict detection) are all **open**, authored largely by the maintainers themselves. They are a to-do list written by people who have run this in production for a decade — build them in from the start rather than as v2 features.

---

## Sources

### Commits (this clone, `UniPiTechnology/evok`)
`47c95c8` (HEAD, main) · `950a9e3` PR#191 "Fix websocket blocking requests" · `f2db299` PR#185 write-failure API response · `66f874b` Modbus TCP reconnect timeout · `07b5dc9` raise pymodbus exceptions · `96cb8e1` + `d4d0f72` switch to pymodbus fork · `80c95f1` shared cache map / `copy`→`deepcopy` · `710b4fa` RTU timeout 4s→1s · `b53a4ed` re-add RTU autoreconnect · `2a5a4d7` MbTCP wait-for-connect · `757da36` **RTU 50 µs hotfix (unmerged branch)** · `a4ea47a` hw_definition dict-order bug · `1cdcbb3` float==NaN invalid JSON · `267be74` UnitRegister valid-mask · `d7fee1e` cache-map init · `c9fa927` + `2996eb0` 32-bit DI counter · `06e759a` ws:all + alias version detection · `4c308bc`/`0f6351b`/`53e922a` `cmd:all` filtering churn · `3d1a208`/`c470267` immediate state changes · `879151f`/`78f707b`/`47bcae6` RS485 dead-time (fix→revert→fix) · `d8d3fff` scan-pass error reporting · `0d84318` webhook POST failure · `85dc7e1` webhook content-type · `802b631` remove `al_` prefix · `3b18ed3` alias altnames · `3247fc3` alias mapping adapter · `127000a` #119 alias API · `1f660d3`/`d772a7f` alias sync · `8822a41`/`fe83cd0` negative values · `8b5e0d2` resistance float · `a1b1666` secondary AI ws updates · `348c88b`/`0d2c654` PWM freq formula · `c3e77d7` PWM mode/readout · `0964ca4` PWM recalc · `a326d00` DO section · `39c418e` multiple i2c open · `193911e` control-logic/indenting · `08a18cf` bulk endpoint · `d55bf51` REST GET exception behaviour · `482e29f` debug tracebacks · `78c41e4` python-ow→onewire · `c677525`/`b7ce314` 1-Wire exception handling + ow_bus reset · `13ea264`/`dd93345` reset_bus rename · `d1db494` 1W device types · `8ab85ab` cython3/pyyaml workaround · `105d95d`…`fab6b9a` ten "Fix autodetection nginx" commits · `1be8a87`/`96e7e7e`/`aa0c507` config restructure · `3cb91d7`/`f0d329d` unit_register→data_point · `a483945`/`6ba9aaa` #167 hw-defs folder · `a633e4a` DataPoint default reg type · `d55cda2`/`7d06ccc` RPC invalid params · `6aa24f2` DO/RO split · `4bb8caa` RS485 write-multiple-registers

### Source files read (EVOK 3.0.6, in-repo paths)
`evok/modbus_unipi.py` · `evok/modbus_slave.py` · `evok/evok.py` · `evok/devents.py` · `evok/devices.py` · `evok/owdevice.py` · `evok/config.py` · `pyproject.toml`

### GitHub issues (`https://github.com/UniPiTechnology/evok/issues/<n>`)
Read in full: **214, 212, 210, 209, 201, 200, 199, 195, 192, 190, 183, 164, 153, 141, 123, 122, 121, 119, 101, 91, 74, 71, 68, 66, 54, 44, 43, 30**. Enumerated from the full 7-page listing (27 open / 126 closed): 218, 217, 216, 213, 211, 208, 207, 206, 204, 203, 202, 198, 197, 196, 194, 193, 188, 189, 187, 186, 185, 182, 180, 179, 178, 177, 176, 175, 174, 173, 172, 171, 170, 169, 167, 166, 165, 163, 162, 161, 160, 159, 158, 157, 156, 155, 149, 148, 145, 144, 139, 137, 133, 131, 130, 129, 127, 126, 125, 124, 120, 118, 117, 116, 114, 107, 106, 105, 104, 103, 102, 99, 98, 97, 95, 94, 93, 90, 88, 87, 86, 85, 84, 83, 82, 81, 80, 79, 76, 75, 73, 72, 67, 64, 63, 62, 61, 60, 59, 58, 57, 56, 55, 53, 52, 51, 50, 49, 48, 46, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 29, 28, 26, 25, 24, 23, 22, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 8, 7, 5, 4, 3, 1

### Pull requests
`https://github.com/UniPiTechnology/evok/pulls?q=is%3Apr` — 3 open (**#215** register WS updates, **#193** Rework Evok initialize [draft], **#154** separate TCP connection per device), 60 closed (incl. **#219** MQTT, closed unmerged).

### pymodbus fork
`https://github.com/martyy665/pymodbus/commits/fix-tid-overflow` · `https://github.com/martyy665/pymodbus/commit/566cd7d`

### Community (gathered and verified by the parallel pass; see its notes for verification level per item)
forum.unipi.technology topics **99, 400, 500, 513, 516, 519, 545, 557, 558, 585, 753, 772, 965, 1042, 1276, 1351, 1360, 1404, 1436** · `github.com/marko2276/ha-unipi-neuron` · `github.com/matthijsberg/unipi-mqtt` · `github.com/mhemeryck/evok2mqtt` · `github.com/mwittig/pimatic-unipi-evok/issues/12` · `github.com/phillipsnick/node-red-contrib-unipi-evok/issues/8` · `community.home-assistant.io/t/evok-unipi/20455`

### Explicitly not verified
- The "aliases auto-saved 5 minutes after change" claim — could not be confirmed on any reachable page. The atomicity problem in `save_aliases` **is** verified in source; the timing is not.
- A forum report of an hourly cron restart of `evok.service` on a Neuron 203 + 2×xS30 + xS40 — the underlying page could not be located.
- Issue **#212**'s final resolution — the captured page text truncated before the closing comments.
- No credible evidence of a memory leak in EVOK was found; the "leak-like" reports resolve to restart loops (#43) or the unbounded-queue mechanisms in §2.2–2.3, which are *plausible* leak paths `[I]` but were not observed as RSS growth by any reporter. Do not claim EVOK leaks memory.agentId: a737ce2a299be0391 (use SendMessage with to: 'a737ce2a299be0391', summary: '<5-10 word recap>' to continue this agent)
<usage>subagent_tokens: 195710
tool_uses: 36
duration_ms: 1415656</usage>