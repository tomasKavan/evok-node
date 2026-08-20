# Latency and the scan budget

Anchored on a measurement from a real device: **a full read of an xS11 over RS-485 takes
~16 ms.** This document works out where that 16 ms goes, because the answer determines the
whole scan architecture.

## 1. The 16 ms is wire time, not software

Modbus RTU at the Unipi default of **19200 baud, 8N1** = 10 bits per character:

```
character time = 10 / 19200 = 0.5208 ms
```

For a read-holding-registers transaction of N registers:

```
request  = 8 bytes                (addr, fc, start hi/lo, count hi/lo, crc lo/hi)
response = 5 + 2N bytes           (addr, fc, bytecount, data…, crc lo/hi)
total     = (13 + 2N) × 0.5208 ms
```

| N registers | Bytes on the wire | Time @19200 8N1 |
|---|---|---|
| 4 | 21 | 10.9 ms |
| **10** | **33** | **17.2 ms** |
| 20 | 53 | 27.6 ms |
| 34 (xS11 whole I/O band) | 81 | 42.2 ms |

**A ~10-register block costs 17.2 ms.** The measured 16 ms is that transaction, essentially
exactly — and EVOK's own documented xS11 block is `start_reg: 0, count: 10`. So the observation
is *fully explained by serial bit time*. There is no software latency to reclaim: the process,
the language and the Modbus library are all irrelevant at this scale.

That is a liberating result. It means:

- **Node.js is not a limiting factor** for extension polling, and neither is HTTP vs unix
  socket. A whole HTTP round trip on loopback is ~0.2 ms — 1 % of one Modbus transaction.
- It retroactively confirms deferring the low-level transport (`05` §7.3).
- The levers that *do* matter are all in the Modbus layer: **baud rate, block layout, and bus
  scheduling.**

## 2. Inter-frame gaps are a real, mandatory cost

Modbus RTU requires 3.5 character times of silence between frames. Per spec, for baud > 19200
a fixed 1.750 ms is used; at or below, it is computed:

```
t3.5 @19200 = 3.5 × 11 / 19200 = 2.005 ms      (spec uses 11 bits/char)
t1.5 @19200 = 1.5 × 11 / 19200 = 0.859 ms
```

So a correct implementation adds **~2 ms per transaction** at 19200 — 12 % overhead on a
10-register read. That is not optional; it is the difference between a framer that recovers
from noise and one that silently returns the previous response (see `09`/§4 below and the
Modbus-library notes in `05` §7.5).

Realistic per-transaction cost at 19200: **~19 ms** for a 10-register block.

## 3. Raising the baud rate is the biggest single lever

Extensions support up to 115200 (`02-hardware-model.md` §5):

| Baud | 10-reg transaction | + t3.5 | Speedup |
|---|---|---|---|
| 9600 | 34.4 ms | 38.4 ms | 0.5× |
| **19200** (default) | **17.2 ms** | **19.2 ms** | 1× |
| 38400 | 8.6 ms | 10.4 ms | 1.85× |
| 57600 | 5.7 ms | 7.5 ms | 2.6× |
| 115200 | 2.9 ms | 4.6 ms | **4.2×** |

Caveats before recommending it: the KB advises choosing the *lowest adequate* baud for the EMC
environment, extensions provide no RS-485 bias resistors (the master end must), and the
DIP-vs-software configuration precedence changes parity as a side effect. So this is a
site-tunable, not a default — but evok-node should make it easy and should *report* the
computed per-bus cycle time so the tradeoff is visible.

## 4. The bus is the budget, not the device

Latency is per-**bus**, serialised. With M devices each needing one block:

```
cycle time ≈ Σ (transaction + t3.5) over all blocks on the bus
```

Four xS11s on one RS-485 line at 19200 ≈ **77 ms** round-robin. Eight ≈ 154 ms. This is why:

- **Per-bus scheduling with an explicit time budget** is mandatory, not a nicety
  (R04-32). A quarantined device must not consume a slot.
- The MWD interaction is a hard constraint: default MWD timeout is **2500 ms**, and a dead peer
  that eats the bus can starve a healthy device's watchdog into firing — exactly what issue
  #123 reported. The scheduler must guarantee every enabled MWD is refreshed well inside its
  timeout **regardless of how many peers are failing**.
- Report the computed cycle time per bus at startup and refuse (or loudly warn) if it exceeds a
  fraction of the shortest MWD timeout on that bus.

Modbus TCP to `unipitcp` on loopback is a completely different regime — sub-millisecond — so
internal PLC sections and RS-485 extensions should never share a scheduler or a latency budget.

## 5. Block layout is a design decision with a measurable price

The counters are the sharp case. On an xS11:

| Data | Registers | Cost @19200 |
|---|---|---|
| DI state bitmap | 1 (reg 2) | in the base block |
| DI counters (12 × uint32) | **24** (regs 3–26) | **+25 ms** |

Polling counters at full rate roughly **triples** the cycle time. This is precisely what EVOK's
per-block `frequency` divisor exists for, and it means:

- **Fast block**: DI/RO bitmaps, AI values — small, polled every cycle.
- **Slow block**: counters, debounce, config — larger, polled at `frequency` N.

### The counter-as-change-detector idea

Using DI counters to detect edges missed between reads is sound and worth building in, with two
caveats:

1. **Counters only count rising edges.** You learn *how many* pulses occurred, not when, and not
   the resulting level. So the event you emit is "N pulses since last read", which is honest and
   useful, but is not a substitute for edge timing.
2. **It costs the 25 ms above** if the counters are in the fast block. There is a genuine
   tension: fast counters give edge *recovery*, a fast bitmap gives edge *latency*. You cannot
   have both cheaply at 19200.

The resolution: put counters in a medium-frequency block, and expose both the raw counter and a
server-computed monotonic `bigint` total plus a `pulsesSinceLastRead` delta. Clients that care
about "did anything happen" use the delta; clients that care about level use the bitmap. This is
R04-24, with a concrete justification.

If genuinely fast edge response is needed, the hardware answers are **DirectSwitch** (firmware
couples DI→DO with no host involvement) or possibly the undocumented `Interrupt Mask` register —
not a faster poll loop.

## 6. Targets to hold ourselves to

| Metric | Target | Rationale |
|---|---|---|
| Software overhead per Modbus transaction | **< 1 ms** | vs 17 ms of wire time; anything more is our bug |
| Event-loop lag under full scan load | **< 5 ms p99** | must not add jitter to bus scheduling |
| Local API round trip (REST/WS on loopback) | **< 2 ms p99** | ~10 % of one RTU transaction; below the noise |
| Per-bus cycle time | reported, and **< 25 % of the shortest MWD timeout** on that bus | prevents the #123 failure |
| Scan schedule drift | corrected, not accumulated | EVOK chains `call_later`, which drifts by the handler duration every cycle |

That last one is a real bug class in EVOK: `loop.call_later(interval, scan_boards)` re-armed at
the *end* of each pass means the true period is `interval + pass_duration`, so the effective
scan rate silently depends on bus health. Use a fixed-rate scheduler with an explicit overrun
policy (skip the missed tick; never queue up).
