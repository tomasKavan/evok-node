# Test kit design

The kit will be driven by **coding agents, not humans**. That single constraint determines the
whole design: every fault an agent needs to inject must be reachable through software, the
wiring must be described in a machine-readable file rather than in someone's head, and nothing
must require a person to move a wire between test runs.

Three tiers, in order of how often they run.

---

## Tier 0 — Simulator (no hardware, runs on every commit)

**This is the primary loop, and it must exist before feature work starts.** Agents iterate in
seconds against it; the physical rig is for confirmation, not for the inner loop.

Built from `docs/modbus-reg-map/` — the CSV/XLSX corpus is machine-readable, so the simulator
and its expected-value tables are *generated*, not hand-written:

- **A Modbus slave per model and section**, with the real register layout, real bit packing,
  real `Via Unit 0` offsets (`address + (unitId-1) × 100`), and the correct
  `Reserved`/`Obsolete` categories refusing or ignoring access as the maps say.
- **Generated address tables** asserting `(model, section, type, channel) → (register, bit,
  coil)` for **every model in the corpus, including the discontinued 28-RO and 30-DI Neurons**.
  Those units are still in the field and are exactly the ones that stress the bank arithmetic.
  This is the only way that bug class can ever be covered — see §4.
- **Codec golden tables**: `i16`, `u16`, `u32` (word-swapped CDAB), `float32`, raw 0..4000 AO
  counts, resistance scaling — including negatives, boundaries and NaN.
- **Fault injection at the protocol level**: exception PDUs, timeouts, late responses, CRC
  errors, wrong unit id, truncated frames, garbage bytes, t3.5 violations, connection drops
  mid-transaction.
- **Behavioural models** for the family forks: MWD countdown and section reboot, "config not
  persisted" (Unipi 1.1), "RS485 config lost on section restart" (Neuron), FW 6.26-vs-6.28 MWD
  refresh semantics.

Also Tier 0: **golden-transcript replay** of the captured stock-EVOK responses (see
`09-test-hardware-coverage.md` §4) against a simulator seeded to the same register values.

---

## Tier 1 — Hardware-in-the-loop rig

### Design principles

1. **No human in the loop, ever.** If a test needs a device to disappear, a relay does it.
2. **Closed loops.** Wire outputs back to inputs so the rig can verify an end-to-end write
   without trusting the thing being tested.
3. **Declarative topology.** A `rig.yaml` describes every connection; tests express intent
   ("make the extension bus unreachable"), never wiring.
4. **Low voltage only.** 24 V DC throughout. No mains switching anywhere in the rig — agents
   will be driving these relays unattended.
5. **The rig is not the thing under test.** Fault injection and power control run on an
   independent host, so a wedged evok-node cannot disable the mechanism that recovers it.

### Units

| Unit | Role in the rig |
|---|---|
| **Patron L527** | Primary DUT. 3 sections → unit-0 aggregate addressing; both AI abstractions; **exactly 16 DI on section 3** (the bank boundary) |
| **Patron M527** (#1) | Secondary DUT. 2 sections and **two RS-485 lines** → multi-bus isolation testing |
| **Gate** | Zero-local-I/O DUT and the clean RS-485-only rig |
| **Patron S167-LTE** | Kept out of the rig as the **second-OS-generation unit** (Debian 12 vs 13) and as the minimal single-section case |
| **Patron M527** (#2) | **Test host / rig controller.** Runs the `rig` service, the fault-injection Modbus slave, and holds SSH to all DUTs. Its own I/O *is* the instrumentation — see §"Test host on a Patron" |

### Test host on a Patron

Using a second M527 as the test host is a better fit than a mini PC, because **its own I/O
replaces most of the extra hardware**:

| Rig function | On a mini PC | On the M527 test host |
|---|---|---|
| Power switching (extensions, DUTs) | USB relay board | its **5 RO** (section 2) |
| RS-485 bus cutting | USB relay board | its **RO / 4 DO** |
| 1-Wire sensor disconnect | USB relay board | its RO |
| Observing DUT outputs independently | — | its **8 DI** — and DI counters give pulse counting for free |
| Driving analog into a DUT | signal generator | its **5 AO** → DUT AI |
| Measuring a DUT's analog output | DMM | DUT AO → its **5 AI** |
| Fault-injection Modbus slave | USB-RS485 adapter | its **`/dev/ttyNS0` / `ttyNS1`** directly |

Channel budget works out comfortably: 5 RO + 4 DO = 9 switching channels (3 power + 2 bus-cut +
spares), 8 DI for observation, 5 AI / 5 AO for analog loops. **No USB relay board needed**, and
a listen-only bus sniffer is the only USB-RS485 adapter still worth buying.

**Cross-unit loopbacks are the real win.** Instead of wiring a DUT's own AO to its own AI —
where a shared codec bug could cancel out and produce a passing test — drive **test-host AO →
DUT AI** and **DUT AO → test-host AI**. Each direction is then measured by an independent
device. Same for RO: the DUT closes a relay, the *test host's* DI observes it.

Also useful: same architecture and OS as the DUTs, so anything built there is built for the real
arm64 target — no cross-compilation surprises.

#### Rule: the instrument must not share code with the thing being measured

The rig service **must not use evok-node, and must not use our Modbus stack.** If it did, a bug
in the shared transport could make a test pass that should fail — and a wedged evok-node would
disable the mechanism meant to recover it.

So the rig drives its own I/O through **sysfs only** (`/run/unipi-plc/by-sys/…`): plain file
reads and writes to `DO/RO/DI/AI/AO` and `ULED` nodes, no Modbus client, no `unipitcp`
involvement. That is a completely different mechanism from the code under test, which is exactly
the property we want from an instrument. (The documented ULED Modbus/sysfs caching conflict
doesn't apply, because the test host will never use Modbus on its own boards.)

#### Test-host setup requirements

1. **Uninstall or disable EVOK on the test host.** Otherwise it grabs the RS-485 ttys and we
   can't run the fault-injection slave, and it polls boards we want to drive by hand.
2. Keep `unipi-kernel-modules` (sysfs is the rig's access path) but `systemctl disable --now
   evok unipitcp` — the rig needs neither.
3. Verify RO **DC derating** before switching 24 V DC extension power. Relay ratings are quoted
   for AC; DC switching derates substantially. Low-current 24 V DC should be fine, but check the
   Patron technical-parameters page for the actual figure.
4. The test host **cannot power-cycle itself.** Acceptable — nothing requires it — but note that
   recovering the rig controller itself is a manual operation.

#### ⚠ Separate the rig controller from the CI runner

An M527 is an excellent rig controller and a **poor CI runner**: i.MX 8M Mini, **1 GB RAM,
8 GB eMMC**. A full `tsc` + test run in 1 GB is marginal, `node_modules` and build caches will
crowd 8 GB fast, and — more importantly — **CI write churn wears the eMMC**, which is not
replaceable. Note the hardware itself tracks this: registers 4000/4001 report erase cycles used
and good blocks remaining.

Recommended split:

- **Rig service on the M527** — tiny, long-running, almost no disk writes. Ideal.
- **CI runner elsewhere**: a mini PC / NUC, or cloud runners, with a `hardware`-labelled job that
  *drives* the rig over the network rather than executing on it. Tier 0 (simulator) doesn't need
  the rig at all and should run on cheap generic runners.
- If you'd rather keep everything on the M527, at minimum put the workspace on an **external USB
  SSD** and monitor registers 4000/4001. That fixes space and endurance, not RAM.

### Loopbacks — the core of the kit

| Loop | Wiring | What it proves |
|---|---|---|
| **RO → DI** | Relay NO contact switches 24 V into a DI on a *different* section | End-to-end write→read. Toggle N times, assert `counter += N`. This is the single most valuable test in the kit — it catches the wrong-relay bug class on the channels we do have |
| **DO → DI** | Section 1 DO → DI on section 2/3 | The DO code path is separate from RO. And **PWM becomes measurable**: drive DO at 100 Hz for 1 s, assert the DI counter reads ≈100. That validates the `pwm_reg`/`pwm_ps_reg`/`pwm_c_reg` trio end-to-end, which upstream got wrong twice |
| **AO → AI** | Section 1 AO (0–10 V) → section 2 AI in voltage mode | Scaling and codecs in both directions, plus mode switching. Write 0.0/2.5/5.0/10.0, assert round-trip within tolerance |
| **AO → AI, current** | 4–20 mA loop | The current-mode scaling path, separately from voltage |
| **Fixed resistors → AI** | Precision resistors on resistance-capable AI, ideally switchable between two values via relay | The 2-wire/3-wire resistance modes and the 400 ms conversion-time constraint |
| **RS-485 bus A** | M527 line 1 → xS11 + xS51 (+ xG18 if available) | Real extension behaviour, real t3.5 timing, the 16 ms latency budget |
| **RS-485 bus B** | DUT M527 line 2 → **test-host M527 `ttyNS1`, running our fault-injection slave** | **The most important channel in the kit.** Software-controlled late responses, CRC errors, silence, wrong unit id, exception PDUs — against real serial hardware, Patron-to-Patron, no USB adapter needed |
| **1-Wire** | 3–4 DS18B20, **one behind a relay** | The #101 case: one sensor disappearing must not freeze the others. Also tests staleness reporting |

Confirm the electrical details (DI input voltage and sourcing/sinking, DO type and load
requirements, AI input impedance, whether a series resistor is needed on the AO→AI link)
against the technical-parameters page for the specific Patron models before wiring — I have not
verified pin-level specifics, and getting DO polarity wrong will damage something.

### Software-controlled fault injection

Everything below must be an API call, not a screwdriver:

| Fault | Mechanism |
|---|---|
| Extension disappears mid-scan | Relay breaks the RS-485 A/B pair, or cuts extension power |
| Extension appears late / after start | Extension power off at boot, on at T+N → the **#192 hot-plug** case, and the one that eliminated a decade of `sleep 200 && restart` cron jobs |
| Device power-cycles under load | Switched power per extension |
| Section reboots (MWD fires) | Write the MWD registers via a side channel and let it expire |
| Slave responds late / not at all / with garbage | Fault-injection slave on RS-485 bus B |
| Two masters contend on one bus | Deliberately drive bus B from both the M527 and the host adapter — a bus-arbitration stress case |
| `owserver` unavailable | Stop the service over SSH |
| Local Modbus server unavailable | Stop `unipitcp` over SSH → tests the "name the failing dependency" requirement |
| Power cut during an alias write | Cut DUT power while a write is in flight → tests atomic temp-file+rename persistence |
| Slow / dead API client | Test host opens a WS connection and stops reading → backpressure (#141) |

Power control and bus-cutting relays are the **test host's own RO/DO**, driven via sysfs — never
a DUT's, or a wedged DUT can't be recovered.

### `rig.yaml` — the machine-readable topology

Tests must never hardcode wiring. Something like:

```yaml
version: 1

# The rig controller. Its own I/O is the instrumentation, driven via sysfs.
host:
  unit: Patron_M527
  address: 10.0.0.10
  io_access: sysfs                 # never Modbus, never evok-node
  sysfs_root: /run/unipi-plc/by-sys

units:                             # devices under test
  l527: { model: Patron_L527, address: 10.0.0.21, os: debian13, sections: 3 }
  m527: { model: Patron_M527, address: 10.0.0.22, os: debian12, sections: 2 }
  gate: { model: Gate_G110,   address: 10.0.0.23, os: debian13, sections: 0 }

buses:
  ext_a: { unit: m527, tty: /dev/ttyNS0, baud: 19200, devices: [xS11@1, xS51@2] }
  ext_b: { unit: m527, tty: /dev/ttyNS1, baud: 19200, role: fault-injection,
           peer: "host:ttyNS1" }

# Cross-unit loopbacks: each direction measured by an independent device.
loopbacks:
  - { kind: ro_to_di, from: "l527:ro/2_01",  to: "host:DI1.1" }
  - { kind: do_to_di, from: "l527:do/1_01",  to: "host:DI1.2", pwm: true }
  - { kind: ao_to_ai, from: "l527:ao/1_01",  to: "host:AI2.1", tolerance_v: 0.05 }
  - { kind: ao_to_ai, from: "host:AO2.1",    to: "l527:ai/2_01", tolerance_v: 0.05 }
  - { kind: ro_to_di, from: "host:RO2.1",    to: "l527:di/3_01" }   # inject a DI edge
  - { kind: fixed_resistor, to: "l527:ai/2_03", ohms: 1000, tolerance_pct: 1 }

# All switching is the host's own RO/DO via sysfs.
power:
  ext_xs11: { host_output: RO2.2 }
  ext_xs51: { host_output: RO2.3 }
  l527:     { host_output: RO2.4 }
switches:
  ext_a_bus:  { host_output: RO2.5, cuts: bus:ext_a }
  ow_sensor3: { host_output: DO1.1, cuts: onewire:2895DCD509000035 }
```

Note `host:RO2.1 → l527:di/3_01`: the host can **inject** DI edges into a DUT, which is how you
test counters and debounce deterministically — drive N pulses at a known rate and assert the
DUT's counter and debounce filtering agree.

### `rig` control service

A small HTTP/CLI service on the test host, so agents express intent:

```
rig describe                          # emit rig.yaml + live health of every element
rig power off ext_xs11 / on ext_xs11
rig bus cut ext_a / restore ext_a
rig onewire disconnect ow_sensor3
rig fault inject --bus ext_b --kind late-response --ms 500
rig fault clear --bus ext_b
rig loopback verify ro_to_di          # independent of evok-node: drive and observe directly
rig capture start|stop --bus ext_a    # bus-level frame capture for post-hoc analysis
rig reset                             # known-good state: all power on, all buses restored, no faults
```

`rig reset` is essential — every test starts from a known state, and a crashed test run must not
leave the rig in a state that breaks the next one.

A **bus sniffer** (a second USB-RS485 adapter in listen-only mode on bus A) is worth the €20:
when a timing test fails, frame-level capture is the difference between a diagnosis and a guess.

---

## Tier 2 — Soak and acceptance

- **Long-running soak**: days of continuous polling with periodic injected faults, asserting
  bounded RSS, bounded latency p99, zero lost counter increments, and no unexplained state.
  Upstream's worst bugs (#141, #30) only appeared after days or weeks.
- **Upstream's own `examples/test_*.py`** run unmodified against evok-node.
- **Real client acceptance**: Node-RED with `@unipitechnology/node-red-contrib-unipi-evok`, and
  Home Assistant with `ha-unipi-neuron` — **through nginx on :80**, since that is the only way
  the HA client can talk to us at all.

---

## Bill of materials

| Item | Qty | Notes |
|---|---|---|
| Patron L527, M527, S167-LTE, Gate | have | |
| **Patron M527 (second unit)** | 1 | the rig controller — its own I/O replaces the USB relay board, the signal generator and one USB-RS485 adapter |
| xS11 extension | have | largest DI/RO extension that exists |
| **xS51 extension** | 1 | adds AI (V/I/R, float32) + AO (raw counts) over RTU — otherwise only reachable via local TCP |
| xG18 | optional | 1-Wire over RTU, if we want that path covered |
| **Neuron L203** | 1 | see §4 — the Neuron platform, and the largest single-section I/O now purchasable (16 DI / 14 RO) |
| Unipi 1.1 | 1, later | an entirely unverified family |
| DS18B20 sensors | 4 | one on a switchable line |
| 24 V DC PSU | 1–2 | sized for relays + DI loops |
| ~~USB relay board~~ | — | **not needed** — the test-host Patron's RO/DO do this |
| **USB-RS485 adapter** | 1 | listen-only sniffer on bus A. Frame capture is the difference between a diagnosis and a guess when a timing test fails |
| Precision resistors (e.g. 100 Ω, 1 kΩ) | few | resistance-mode AI |
| DIN rail, terminal blocks, fuses, enclosure | — | |
| **CI runner host** (mini PC / NUC, or cloud) | 1 | separate from the rig controller — see the eMMC/RAM warning above |
| External USB SSD | optional | only if CI must run on the M527 |
| Managed switch or separate VLAN | 1 | keep the rig off the main network |

---

## §4 — The >16-channel problem is now permanent

Verified against the Unipi e-shop (July 2026): **M303, M403, L303 and L403 are all
discontinued** — not just the two I was told about — and **no currently-purchasable Unipi
device, controller or extension, has more than 16 channels of one type in a single section.**

| | Best available today |
|---|---|
| Most DI in one section | **16** — Neuron M203/L203/L523, Patron M207/M267/L207/L527 |
| Most RO in one section | **14** — Neuron L203/M203/L523, Patron L207/M207/M267/L527 |
| Largest extension | **xS11**: 12 DI / 13 RO — and nothing bigger has ever existed |

Unipi published **no successor** for the high-density models: the 2019 clearance notice said
plainly they "will not be available anymore". Patron replaces *Axon*, not Neuron, and no Patron
corresponds to an M403. A 28-RO section may be obtainable through Unipi's custom-manufacturing
programme, but that needs a direct quote and is not a catalogue part.

**So the highest-severity bug class can never be verified on new hardware.** Three consequences:

1. **The generated address tables in Tier 0 become the primary safeguard, not a supplement.**
   They must cover every model in the corpus including the discontinued ones, and they must be
   generated from the map CSVs so they cannot drift from the hardware truth.
2. **Add a startup assertion that makes the bug impossible rather than detectable**: registering
   two devices with the same circuit id, or two circuits resolving to the same coil or the same
   (register, bit), is a **fatal** error. That converts a silent wrong-relay actuation into a
   refusal to start — safe under all conditions, including hardware we have never seen.
3. **Test the dangerous half on hardware we do have.** The M403 failure had two components:
   the missing bank stride (needs >16 channels — untestable) *and* `RO`/`DO`/`LED` ignoring
   `start_index` when a definition declares two feature blocks of the same type (testable
   anywhere). On the L527's section 3 we can write a deliberately split definition — two RO
   blocks of 7 with `start_index` — and assert that circuits do not collide and that each drives
   the coil it claims, verified through the RO→DI loopback. That exercises the actual code path
   that mis-registered the circuits, on real hardware.

Item 3 is the closest thing to a reproduction available, and the RO→DI loopback is what makes it
conclusive: the rig observes which relay actually closed, independently of what the API claims.
