# Test hardware and coverage

Available now: **Patron M527, Patron S167-LTE, Patron L527, Gate** (+ at least one xS11
extension, inferred from the 16 ms RS-485 measurement — confirm). Neuron and Unipi 1.1 to be
bought approaching 1.0; Edge when the fast-follow starts.

> **Correction, 2026-08-10.** The xS11 is **confirmed** on hand, and an **xG18 is also on hand** —
> so 1-Wire over RTU (§5 priority 5) is coverable now and is not a purchase. **No xS51**; it is
> approved but not yet ordered, and until it arrives AI/AO over RTU remains reachable only through
> the local TCP path. Also confirmed: **all three Patrons and the Gate run Debian 13**, so §5's "run one
> Patron on each generation" is met instead by imaging the incoming second M527 as Debian 12 rather
> than reflashing a unit — reflashing would destroy the stock-EVOK fixtures. See
> [`docs/plan/STATUS.md`](../plan/STATUS.md), open questions and *Blocked / waiting on hardware*. The
> capture runbook this used to point at was deleted on 2026-08-16 and is rewritten with the new plan;
> `STATUS.md` carries the list of what must be captured in the meantime.

This document maps what that hardware does and does not exercise, derived from
`derived/model-io-census.csv`.

---

## 1. What the available units cover

### Patron L527 — the richest single unit in the set

| Section | DI | DO | RO | AI | AO | LED | Exercises |
|---|---|---|---|---|---|---|---|
| 1 | 4 | 4 | – | 1 | 1 | 4 | "Brain" section: DO with PWM, **2-mode AI** (`Configuration(U/I)` at reg 1024), **AOR** (`BAO` — the AO that can also measure resistance), ULED |
| 2 | 4 | – | 5 | 4 | 4 | – | **6-mode AI** (`Configuration(U/I/R)` at 1019–1022), plain AO, RO |
| 3 | **16** | – | 14 | – | – | – | **the exactly-16 bank boundary** — bit mask `1 << 15`, the last channel that fits in one register |

Three sections also means it is the unit that verifies **unit-0 aggregate addressing**
(`address + (unitId-1) × 100` → section 2 at +100, section 3 at +200) and that the
`Via Unit 0` exclusion list behaves as the maps claim.

Section 3's 16 DI is valuable: it's the off-by-one boundary of the bank-stride arithmetic
without crossing it. Cheap insurance for the tier-1 addressing bug even though it can't
reproduce it.

### Patron M527 — the multi-bus rig

Two sections (same shape as L527 sections 1–2) plus, per the Patron portmap, **two RS-485
lines**: `RS485-1` on `ttyNS0` and `RS485-4` on `ttyNS1`. That makes it the unit for:

- two independent RTU buses with independent schedulers and circuit breakers,
- proving that a stalled bus cannot affect the other bus or the local TCP sections
  (the #190 cross-bus blocking failure),
- per-bus cycle-time budgeting with extensions distributed across both lines.

### Patron S167-LTE — the minimal unit

Single section, one `ttyNS0`. Its value is as the **smallest valid configuration**: one
section, no section 2/3, LTE present. Good for asserting we don't assume multi-section
layouts, and for checking that the LTE modem's serial port isn't mistaken for a Modbus line.

### Gate — the zero-I/O and extension-only rig

Gate has **no local I/O at all**. Two distinct uses, both genuinely important:

1. **The empty-device-tree case.** Autogen produces no sections. A surprising amount of code
   assumes at least one board exists — EVOK's own `readboards()` and `/rest/all` behaviour
   degrade oddly here. Must not crash, must serve an empty (not erroring) API.
2. **Extension behaviour in isolation.** With only RS-485 extensions attached, RTU framing,
   t3.5 pacing, per-device quarantine and bus scheduling can be measured with no local Modbus
   TCP traffic confounding it. This is the cleanest rig for the transport-layer work — and the
   16 ms measurement was presumably taken this way.

---

## 2. ⚠ The critical gap: >16 channels is Neuron-only

Derived from the census — **every model with more than 16 channels of a single type is a
Neuron**:

| Model | Section | Channels | Type |
|---|---|---|---|
| Neuron M303 | 2 | **30** | DI |
| Neuron L303 | 2, 3 | **30** | DI |
| Neuron M403 | 2 | **28** | RO |
| Neuron L403 | 2, 3 | **28** | RO |

**No Patron model has more than 16 of any type.** Consequently the available hardware
**cannot reproduce the tier-1 severity bug** — the one where EVOK silently drives the wrong
physical relay (issues #209 / #195, field-reported on an M403).

Two consequences:

1. That bug class must be covered **entirely by the simulator plus table-driven address tests
   generated from the map CSVs**, and those tests are non-negotiable before 1.0. See
   `04-known-bugs-and-lessons.md` rules 1 and 2.
2. **It cannot be bought either.** Verified against the Unipi e-shop (July 2026): **M303, M403,
   L303 and L403 are all discontinued**, and **no currently-purchasable Unipi device — controller
   or extension — exceeds 16 channels of one type in a single section.** Unipi published no
   successor; the 2019 clearance notice said they "will not be available anymore", and Patron
   replaces *Axon*, not Neuron. Ceiling across the whole current catalogue:

   | | Best available today |
   |---|---|
   | Most DI in one section | **16** — Neuron M203/L203/L523, Patron M207/M267/L207/L527 |
   | Most RO in one section | **14** — Neuron L203/M203/L523, Patron L207/M207/M267/L527 |
   | Largest extension ever made | **xS11** — 12 DI / 13 RO |

   So the generated address tables become the **primary** safeguard rather than a supplement, and
   we add a startup assertion that makes the bug *impossible* rather than detectable: duplicate
   circuit ids, or two circuits resolving to the same coil or (register, bit), is a **fatal**
   error. See [`10-test-kit.md`](10-test-kit.md) §4 for the full reasoning and for the
   partial reproduction that *is* possible on the L527.

   **When buying a Neuron, buy an L203.** It won't exercise the bank stride — nothing will — but
   it gives the Neuron platform (RPi, `ttyNS*`, DS2482 on i2c-1, and the RS485-config-lost-on-
   section-restart fork) plus the largest single-section I/O still purchasable: 3 sections of
   16 DI / 14 RO. A Neuron S103 or M103 would verify almost nothing the Patrons don't already
   cover.

---

## 3. Coverage matrix

| Capability | Covered by available HW | Gap |
|---|---|---|
| Modbus TCP to `unipitcp` on `127.0.0.1:502` | ✅ all three Patrons | |
| Multi-section units (2 and 3 sections) | ✅ M527 (2), L527 (3) | |
| Unit-0 aggregate addressing `+100×(n−1)` | ✅ L527 | |
| Section-1 "Brain" I/O: DO+PWM, 2-mode AI, AOR | ✅ all three | |
| Section-2/3 6-mode AI, plain AO | ✅ M527, L527 | |
| ULED | ✅ all three (section 1) | Edge's **unit-0** ULED (reg 3998 / coils 3000–3002) ✗ |
| RO | ✅ M527/L527 sec2 (5), L527 sec3 (14) | |
| Exactly-16 channel boundary | ✅ L527 sec3 (16 DI) | |
| **>16 channels / bank stride** | ✗ | **Neuron M403/M303 only** |
| Two RS-485 buses on one unit | ✅ M527 | |
| RTU extensions, t3.5, framing, quarantine | ✅ Gate + xS11 (cleanest), any Patron | more extension models (xS51 for AI/AO, xG18 for 1-Wire) would help |
| Zero-local-I/O unit | ✅ Gate | |
| Master watchdog per section | ✅ all Patrons | FW 6.26-vs-6.28 behaviour fork needs two firmware versions ✗ |
| 1-Wire / OWFS | ✅ Patrons (DS2482 on i2c-2) | Neuron uses **i2c-1** ✗ |
| **Neuron: RS485 config lost on section restart** | ✗ | verified doc fork, untestable on Patron — a real behavioural difference |
| Neuron platform paths (RPi, `ttyNS*`, microSD) | ✗ | |
| **Unipi 1.1**: port 50200, `unipi-one-modbus`, no board FW, no NV save, config not persisted, 18-bit AI | ✗ | entirely unverified until purchased |
| Debian 12 vs 13 identity paths | partly — depends which OS images are on the Patrons | run at least one Patron on each generation |
| Edge: slot/card, per-channel AI modes, 4–20 mA / 90–2000 Ω | ✗ | fast-follow scope |

---

## 4. Immediate actions

1. **Capture golden API transcripts from stock EVOK 3.0.6 on all three Patrons before touching
   them** — `GET /rest/all`, per-type GETs, a WS session (default filter *and* filtered), a
   webhook capture, and `GET /json/all`. L527 is the priority: three sections, both AI
   abstractions, and the 16-DI boundary in one dump. This is the compatibility oracle and it is
   gone once EVOK is replaced. See `05-evok-node-design-notes.md` §7.4 item 7.
2. **Record `/etc/evok/hw_definitions/*.yaml` and `/etc/evok/autogen.yaml` from each unit.**
   They are more trustworthy than the published doc examples. Also capture `unipiid` output (or the
   sysfs equivalent on Debian 12) and board firmware versions per section.

   > **Corrected 2026-08-13 (ADR-0014).** They are not "the stock definitions our overlay merges onto" —
   > there is no overlay and we read nothing from `/etc/evok` at runtime. They are one of the two **offline
   > sources** our own definitions are transcribed from, and the only source of the AI/AO mode
   > enumerations for CSV-only families, which makes this step **blocking** rather than merely useful.
3. **Confirm which extensions are on hand.** xS11 gives DI/RO/counters/ULED; an **xS51** would
   add AI (6-mode, float32) and AO (raw 0..4000) over RTU, which is otherwise only reachable
   through the local TCP path. Worth adding if not present.
4. **Run one Patron on Debian 12 and one on Debian 13**, so the identity provider chain
   (§8.1 in `05`) is exercised both ways rather than discovered late.
5. **Note which OS images / firmware versions each unit carries**, so the FW 6.26-vs-6.28 MWD
   behaviour fork can be tested if any unit predates 6.28.

## 5. Purchasing recommendations, in order of value

| Priority | Unit | What it unlocks |
|---|---|---|
| 1 | **xS51 extension** | Cheapest meaningful gain: AI/AO over RTU (float32 AI, raw-count AO, 6-mode enum on an extension) — otherwise only reachable via the local TCP path |
| 2 | **Neuron L203** | The Neuron platform: RPi base, `ttyNS*`, DS2482 on i2c-1, and the verified "RS485 config lost on section restart" fork. Plus 3 × (16 DI / 14 RO) — the largest single-section I/O still purchasable |
| 3 | **Unipi 1.1** | An entirely unverified family: `unipi-one-modbus` on port 50200, no board firmware, no NV save, config lost on power cycle, 18-bit AI |
| 4 | **Edge E410** | Fast-follow scope: slot/card identity, unit-0 ULED, per-channel AI modes, 4–20 mA / 90–2000 Ω. Note Edge's product page **does** list EVOK support, even though EVOK's README doesn't mention Edge |
| 5 | xG18 | 1-Wire over RTU, if we want that path covered |

Not purchasable at any priority: anything with >16 channels of one type. See §2.

Axon is out of scope. Its map CSVs stay in `docs/modbus-reg-map/axon/` as free cross-check data
for the Neuron register model, but no Axon hardware is needed and no Axon support is claimed.
